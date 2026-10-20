#include "PatientVoiceComponent.h"

#include "AudioDevice.h"
#include "Components/AudioComponent.h"
#include "Engine/Engine.h"
#include "Features/IModularFeatures.h"
#include "HAL/IConsoleManager.h"
#include "ILiveLinkClient.h"
#include "LiveKitPatientStream.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "PatientMouthSolver.h"
#include "PatientVoiceLiveLinkSource.h"
#include "PatientVoiceSpikeLog.h"
#include "Sound/SoundWaveProcedural.h"

namespace
{
	// The LiveKit FFI delivers remote audio resampled to 48 kHz mono by default.
	constexpr int32 PlaybackSampleRate = 48000;
	constexpr int32 PlaybackChannels = 1;

	TAutoConsoleVariable<FString> CVarUrl(TEXT("patientvoice.Url"), TEXT(""),
		TEXT("Overrides UPatientVoiceComponent::ServerUrl when not empty."));
	TAutoConsoleVariable<FString> CVarToken(TEXT("patientvoice.Token"), TEXT(""),
		TEXT("Overrides UPatientVoiceComponent::Token when not empty."));
	TAutoConsoleVariable<FString> CVarBackend(TEXT("patientvoice.Backend"),
#if PLATFORM_WINDOWS
		TEXT("NNERuntimeORTDml"),
#else
		TEXT("NNERuntimeORTCpu"),
#endif
		TEXT("NNE backend for the speech solver, as in mh.RealtimeAudio.Backend."));
}

UPatientVoiceComponent::UPatientVoiceComponent()
{
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.bStartWithTickEnabled = true;
}

void UPatientVoiceComponent::BeginPlay()
{
	Super::BeginPlay();
	Connect();
}

void UPatientVoiceComponent::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	Disconnect();
	Super::EndPlay(EndPlayReason);
}

void UPatientVoiceComponent::Connect()
{
	Disconnect();

	const FString Url = CVarUrl.GetValueOnGameThread().IsEmpty() ? ServerUrl : CVarUrl.GetValueOnGameThread();
	FString RoomToken = CVarToken.GetValueOnGameThread().IsEmpty() ? Token : CVarToken.GetValueOnGameThread();
	if (RoomToken.IsEmpty())
	{
		// Written by scripts/spike-189/*.sh; Saved/ is git-ignored, so no token lands in a level.
		const FString TokenFile = FPaths::Combine(FPaths::ProjectSavedDir(), TEXT("PatientVoiceSpike"), TEXT("token.txt"));
		if (FFileHelper::LoadFileToString(RoomToken, *TokenFile))
		{
			RoomToken.TrimStartAndEndInline();
		}
	}
	if (RoomToken.IsEmpty())
	{
		SetStatus(TEXT("No token. Run a scripts/spike-189 script or set patientvoice.Token, then call Connect."));
		return;
	}

	// Live Link source that the MetaHuman face reads.
	IModularFeatures& Features = IModularFeatures::Get();
	if (Features.IsModularFeatureAvailable(ILiveLinkClient::ModularFeatureName))
	{
		ILiveLinkClient& Client = Features.GetModularFeature<ILiveLinkClient>(ILiveLinkClient::ModularFeatureName);
		LiveLinkSource = MakeShared<FPatientVoiceLiveLinkSource>(SubjectName);
		LiveLinkSourceGuid = Client.AddSource(LiveLinkSource);
	}
	else
	{
		SetStatus(TEXT("Live Link is not available; the face will not move."));
	}

	TWeakPtr<FPatientVoiceLiveLinkSource> WeakSource = LiveLinkSource;
	MouthSolver = MakeShared<FPatientMouthSolver>(MouthDriver, CVarBackend.GetValueOnGameThread(), LookaheadMs, EnvelopeGain,
		[this, WeakSource](FPatientMouthFrame&& Frame)
		{
			if (TSharedPtr<FPatientVoiceLiveLinkSource> Source = WeakSource.Pin())
			{
				Source->PushRawControls(Frame.RawControls);
			}
			FScopeLock Lock(&StateLock);
			MouthLatencyMsTotal += (Frame.SolvedSeconds - Frame.NewestAudioArrivalSeconds) * 1000.0;
			++MouthFrames;
			++MouthFramesTotal;
		});
	SetStatus(MouthSolver->GetDescription());

	// Procedural wave fed straight from the LiveKit callback; QueueAudio is thread-safe.
	VoiceWave = NewObject<USoundWaveProcedural>(this);
	VoiceWave->SetSampleRate(PlaybackSampleRate);
	VoiceWave->NumChannels = PlaybackChannels;
	VoiceWave->Duration = INDEFINITELY_LOOPING_DURATION;
	VoiceWave->SoundGroup = SOUNDGROUP_Voice;
	VoiceWave->bLooping = false;

	AudioComponent = NewObject<UAudioComponent>(GetOwner());
	AudioComponent->bAutoActivate = false;
	AudioComponent->bAllowSpatialization = false;
	AudioComponent->SetupAttachment(GetOwner()->GetRootComponent());
	AudioComponent->RegisterComponent();
	AudioComponent->SetSound(VoiceWave);
	AudioComponent->Play();

	{
		FScopeLock Lock(&StateLock);
		StreamSampleRate = 0;
		StreamChannels = 0;
		bQueuedInitialDelay = false;
		PcmSecondsReceived = 0.0;
		MouthLatencyMsTotal = 0.0;
		MouthFrames = 0;
		MouthFramesTotal = 0;
	}

	FLiveKitPatientStream::FConfig Config{ Url, RoomToken, PublisherIdentity, TrackName };
	Stream = MakeShared<FLiveKitPatientStream>(MoveTemp(Config),
		[this](const int16* Samples, int32 SamplesPerChannel, int32 SampleRate, int32 NumChannels)
		{
			HandlePcm(Samples, SamplesPerChannel, SampleRate, NumChannels);
		},
		[this](const FString& Status) { SetStatus(Status); });
	Stream->Start();
}

void UPatientVoiceComponent::Disconnect()
{
	// Stop the producer first, then the consumers it feeds.
	if (Stream)
	{
		Stream->Stop();
		Stream.Reset();
	}
	MouthSolver.Reset();

	if (LiveLinkSource && IModularFeatures::Get().IsModularFeatureAvailable(ILiveLinkClient::ModularFeatureName))
	{
		IModularFeatures::Get().GetModularFeature<ILiveLinkClient>(ILiveLinkClient::ModularFeatureName).RemoveSource(LiveLinkSourceGuid);
	}
	LiveLinkSource.Reset();

	if (AudioComponent)
	{
		AudioComponent->Stop();
		AudioComponent->DestroyComponent();
		AudioComponent = nullptr;
	}
	VoiceWave = nullptr;
}

void UPatientVoiceComponent::HandlePcm(const int16* Samples, int32 SamplesPerChannel, int32 SampleRate, int32 NumChannels)
{
	const double Arrival = FPlatformTime::Seconds();

	{
		FScopeLock Lock(&StateLock);
		StreamSampleRate = SampleRate;
		StreamChannels = NumChannels;
		PcmSecondsReceived += double(SamplesPerChannel) / FMath::Max(SampleRate, 1);
	}

	if (SampleRate == PlaybackSampleRate && NumChannels == PlaybackChannels && VoiceWave)
	{
		if (!bQueuedInitialDelay)
		{
			bQueuedInitialDelay = true;
			if (AudioDelayMs > 0)
			{
				TArray<uint8> Silence;
				Silence.SetNumZeroed(PlaybackSampleRate * AudioDelayMs / 1000 * sizeof(int16));
				VoiceWave->QueueAudio(Silence.GetData(), Silence.Num());
			}
		}
		VoiceWave->QueueAudio(reinterpret_cast<const uint8*>(Samples), SamplesPerChannel * NumChannels * sizeof(int16));
	}

	if (MouthSolver)
	{
		TArray<float> Mono;
		Mono.SetNumUninitialized(SamplesPerChannel);
		for (int32 Frame = 0; Frame < SamplesPerChannel; ++Frame)
		{
			float Sum = 0.0f;
			for (int32 Channel = 0; Channel < NumChannels; ++Channel)
			{
				Sum += Samples[Frame * NumChannels + Channel];
			}
			Mono[Frame] = Sum / (NumChannels * 32768.0f);
		}
		MouthSolver->PushAudio(MoveTemp(Mono), SampleRate, Arrival);
	}
}

void UPatientVoiceComponent::SetStatus(const FString& Status)
{
	{
		FScopeLock Lock(&StateLock);
		LatestStatus = Status;
	}
	if (TSharedPtr<FPatientVoiceLiveLinkSource> Source = LiveLinkSource)
	{
		Source->SetStatus(Status);
	}
}

void UPatientVoiceComponent::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);

	const double Now = FPlatformTime::Seconds();
	if (Now - LastStatsSeconds >= 1.0)
	{
		LastStatsSeconds = Now;
		LogStats();
	}
}

void UPatientVoiceComponent::LogStats()
{
	FString Status;
	int32 SampleRate = 0;
	int32 Channels = 0;
	double Received = 0.0;
	double MouthLatencyMs = 0.0;
	int32 FramesTotal = 0;
	{
		FScopeLock Lock(&StateLock);
		Status = LatestStatus;
		SampleRate = StreamSampleRate;
		Channels = StreamChannels;
		Received = PcmSecondsReceived;
		MouthLatencyMs = MouthFrames > 0 ? MouthLatencyMsTotal / MouthFrames : 0.0;
		FramesTotal = MouthFramesTotal;
		MouthLatencyMsTotal = 0.0;
		MouthFrames = 0;
	}

	const double SolveMs = MouthSolver ? MouthSolver->ConsumeAverageSolveMs() : 0.0;
	const double BacklogMs = VoiceWave ? 1000.0 * VoiceWave->GetAvailableAudioByteCount() / (PlaybackSampleRate * PlaybackChannels * sizeof(int16)) : 0.0;

	double DeviceMs = 0.0;
	if (FAudioDevice* Device = GEngine ? GEngine->GetMainAudioDeviceRaw() : nullptr)
	{
		DeviceMs = 1000.0 * Device->GetBufferLength() * Device->GetNumBuffers() / FMath::Max(Device->GetSampleRate(), 1.0f);
	}

	// Estimated time from PCM arrival to each output. Mouth frames reflect audio
	// LookaheadMs in the past, so the mouth trails the newest audio by that much.
	const double AudioPathMs = BacklogMs + DeviceMs;
	const double MouthPathMs = (MouthDriver == EPatientMouthDriver::SpeechSolver ? LookaheadMs : 0) + MouthLatencyMs;
	const FString Stats = FString::Printf(
		TEXT("pcm %d Hz x%d, %.1f s received | mouth frames %d, solve %.2f ms, arrival->solved %.1f ms | audio backlog %.0f ms + device %.0f ms | est. mouth-minus-audio %+.0f ms"),
		SampleRate, Channels, Received, FramesTotal, SolveMs, MouthLatencyMs, BacklogMs, DeviceMs, MouthPathMs - AudioPathMs);

	if (Received > 0.0)
	{
		UE_LOG(LogPatientVoiceSpike, Log, TEXT("%s"), *Stats);
	}

	if (bShowOnScreenStats && GEngine)
	{
		const uint64 Key = GetUniqueID();
		GEngine->AddOnScreenDebugMessage(Key * 2, 1.5f, FColor::Cyan, Status);
		GEngine->AddOnScreenDebugMessage(Key * 2 + 1, 1.5f, FColor::Yellow, Stats);
	}
}
