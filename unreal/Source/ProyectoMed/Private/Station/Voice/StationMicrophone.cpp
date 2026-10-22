#include "Station/Voice/StationMicrophone.h"

#include "AudioCapture.h"
#include "StationVoice.h"

DEFINE_LOG_CATEGORY_STATIC(LogStationMicrophone, Log, All);

bool UStationMicrophone::Start(TWeakPtr<FStationVoiceLink, ESPMode::ThreadSafe> Link)
{
	Stop();
	Capture = NewObject<UAudioCapture>(this);
	if (!Capture->OpenDefaultAudioStream())
	{
		UE_LOG(LogStationMicrophone, Warning, TEXT("No microphone could be opened."));
		Capture = nullptr;
		return false;
	}
	const int32 SampleRate = Capture->GetSampleRate();
	const int32 NumChannels = Capture->GetNumChannels();
	// Runs on the capture thread.
	Handle = Capture->AddGeneratorDelegate([Link, SampleRate, NumChannels](const float* Audio, int32 NumSamples)
	{
		if (const TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> Voice = Link.Pin())
		{
			Voice->PushMicrophonePcm(TConstArrayView<float>(Audio, NumSamples), SampleRate, NumChannels);
		}
	});
	Capture->StartCapturingAudio();
	UE_LOG(LogStationMicrophone, Log, TEXT("Microphone on: %d Hz, %d channel(s)."), SampleRate, NumChannels);
	return true;
}

void UStationMicrophone::Stop()
{
	if (!Capture)
	{
		return;
	}
	Capture->StopCapturingAudio();
	Capture->RemoveGeneratorDelegate(Handle);
	Handle = FAudioGeneratorHandle();
	Capture = nullptr;
	UE_LOG(LogStationMicrophone, Log, TEXT("Microphone off."));
}

bool UStationMicrophone::IsCapturing() const
{
	return Capture && Capture->IsCapturingAudio();
}

void UStationMicrophone::BeginDestroy()
{
	Stop();
	Super::BeginDestroy();
}
