#include "StationVoice.h"

#include "Async/Async.h"
#include "Containers/Ticker.h"
#include "StationClientLog.h"
#include "StationLiveKit.h"
#include "StationPcm.h"
#include "StationVoiceLiveness.h"

THIRD_PARTY_INCLUDES_START
#include "livekit/livekit.h"
THIRD_PARTY_INCLUDES_END

#include <atomic>
#include <exception>
#include <memory>
#include <string>
#include <vector>

const TCHAR* FStationVoiceLink::WorkerIdentity = TEXT("voice-worker");
const TCHAR* FStationVoiceLink::PatientTrackName = TEXT("patient-voice");

namespace
{
	const char* TranscriptTopic = "transcript";
	const char* MicrophoneTrackName = "microphone";

	std::string ToStd(const FString& Value)
	{
		return std::string(TCHAR_TO_UTF8(*Value));
	}
}

/**
 * Everything LiveKit touches. Lives as long as the longest of the link and any
 * callback still queued for the game thread; `bAlive` turns those callbacks into
 * no-ops once the link disconnects.
 */
struct FStationVoiceLink::FImpl : public livekit::RoomDelegate
{
	FString Url;
	FString Token;
	FString SessionId;
	FStationVoiceHandlers Handlers;
	TWeakPtr<FStationVoiceLink, ESPMode::ThreadSafe> Owner;

	std::atomic<bool> bAlive{true};
	std::atomic<bool> bPublished{false};
	std::atomic<bool> bWorkerPresent{false};
	std::atomic<bool> bReconnecting{false};
	/** The state is `WaitingForWorker` or `Ready`: microphone audio is sent. */
	std::atomic<bool> bListening{false};

	/** Game thread only: whether the voice can still be heard, and its 10-second watch. */
	FStationVoiceLiveness Liveness;
	bool bWatching = false;

	std::unique_ptr<livekit::Room> Room;
	TFuture<void> ConnectTask;

	/** Guards the microphone path against `Disconnect` releasing it. */
	FCriticalSection MicLock;
	FStationPcmFramer Framer;
	std::shared_ptr<livekit::AudioSource> Source;
	std::shared_ptr<livekit::LocalAudioTrack> Track;

	/** The echo canceller sees the patient's voice and the microphone from two threads. */
	FCriticalSection ApmLock;
	std::unique_ptr<livekit::AudioProcessingModule> Apm;

	/** This object, for callbacks queued to the game thread. */
	TWeakPtr<FImpl, ESPMode::ThreadSafe> Self;

	void PostState(EStationVoiceState NewState, const FString& NewFailure = FString())
	{
		AsyncTask(ENamedThreads::GameThread, [WeakImpl = Self, NewState, NewFailure]()
		{
			const TSharedPtr<FImpl, ESPMode::ThreadSafe> Impl = WeakImpl.Pin();
			if (!Impl || !Impl->bAlive)
			{
				return;
			}
			if (const TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> Link = Impl->Owner.Pin())
			{
				Link->SetState(NewState, NewFailure);
			}
		});
	}

	void PostEvent(FStationVoiceEvent Event)
	{
		AsyncTask(ENamedThreads::GameThread, [WeakImpl = Self, Event = MoveTemp(Event)]()
		{
			const TSharedPtr<FImpl, ESPMode::ThreadSafe> Impl = WeakImpl.Pin();
			if (Impl && Impl->bAlive && Impl->Handlers.OnEvent)
			{
				Impl->Handlers.OnEvent(Event);
			}
		});
	}

	void PostReadiness()
	{
		if (!bPublished)
		{
			return;
		}
		const FStationVoiceLiveness::FSignals Signals{ bWorkerPresent, bReconnecting };
		AsyncTask(ENamedThreads::GameThread, [WeakImpl = Self, Signals]()
		{
			const TSharedPtr<FImpl, ESPMode::ThreadSafe> Impl = WeakImpl.Pin();
			if (Impl && Impl->bAlive)
			{
				Impl->ShowLiveness(Impl->Liveness.Update(Signals, FPlatformTime::Seconds()));
			}
		});
	}

	static bool IsWatched(EStationVoiceState State)
	{
		return State == EStationVoiceState::WaitingForWorker || State == EStationVoiceState::Reconnecting;
	}

	/** Game thread. While the voice waits for the worker or reconnects, checks it twice a second until it is ready or lost. */
	void ShowLiveness(EStationVoiceState NewState)
	{
		const TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> Link = Owner.Pin();
		if (!Link || Link->GetState() == EStationVoiceState::Failed)
		{
			return;
		}
		bListening = NewState == EStationVoiceState::WaitingForWorker || NewState == EStationVoiceState::Ready;
		FString Reason;
		if (NewState == EStationVoiceState::Failed)
		{
			Reason = Link->GetState() == EStationVoiceState::WaitingForWorker
				? TEXT("The voice worker did not join within 20 seconds.")
				: TEXT("The voice did not come back within 10 seconds.");
		}
		Link->SetState(NewState, Reason);
		if (!IsWatched(NewState) || bWatching)
		{
			return;
		}
		bWatching = true;
		FTSTicker::GetCoreTicker().AddTicker(TEXT("StationVoiceLiveness"), 0.5f, [WeakImpl = Self](float)
		{
			const TSharedPtr<FImpl, ESPMode::ThreadSafe> Impl = WeakImpl.Pin();
			if (!Impl || !Impl->bAlive)
			{
				return false;
			}
			const EStationVoiceState Current = Impl->Liveness.Tick(FPlatformTime::Seconds());
			if (IsWatched(Current))
			{
				return true;
			}
			Impl->bWatching = false;
			Impl->ShowLiveness(Current);
			return false;
		});
	}

	void Connect()
	{
		if (!StationLiveKit::EnsureInitialized())
		{
			PostState(EStationVoiceState::Failed, TEXT("The LiveKit SDK did not initialise."));
			return;
		}
		try
		{
			livekit::AudioProcessingModule::Options ApmOptions;
			ApmOptions.echo_cancellation = true;
			ApmOptions.noise_suppression = true;
			ApmOptions.high_pass_filter = true;
			ApmOptions.auto_gain_control = true;
			Apm = std::make_unique<livekit::AudioProcessingModule>(ApmOptions);

			Room = std::make_unique<livekit::Room>();
			Room->setDelegate(this);
			// Registered before connecting: the dispatcher attaches it when the track arrives.
			Room->setOnAudioFrameCallback(ToStd(WorkerIdentity), ToStd(PatientTrackName),
				[this](const livekit::AudioFrame& Frame) { OnPatientFrame(Frame); });

			livekit::RoomOptions Options;
			Options.auto_subscribe = true;
			if (!bAlive || !Room->connect(ToStd(Url), ToStd(Token), Options))
			{
				if (bAlive)
				{
					PostState(EStationVoiceState::Failed, TEXT("Could not join the LiveKit room."));
				}
				return;
			}

			{
				FScopeLock Lock(&MicLock);
				if (!bAlive)
				{
					return;
				}
				Source = std::make_shared<livekit::AudioSource>(FStationPcmFramer::SampleRate, 1);
				Track = livekit::LocalAudioTrack::createLocalAudioTrack(MicrophoneTrackName, Source);
			}
			livekit::TrackPublishOptions PublishOptions;
			PublishOptions.source = livekit::TrackSource::SOURCE_MICROPHONE;
			PublishOptions.dtx = false;
			if (const std::shared_ptr<livekit::LocalParticipant> Local = Room->localParticipant().lock())
			{
				Local->publishTrack(Track, PublishOptions);
			}
			else
			{
				PostState(EStationVoiceState::Failed, TEXT("The room has no local participant."));
				return;
			}

			for (const std::weak_ptr<livekit::RemoteParticipant>& Weak : Room->remoteParticipants())
			{
				const std::shared_ptr<livekit::RemoteParticipant> Participant = Weak.lock();
				if (Participant && Participant->identity() == ToStd(WorkerIdentity))
				{
					bWorkerPresent = true;
				}
			}
			bPublished = true;
			PostReadiness();
		}
		catch (const std::exception& Error)
		{
			UE_LOG(LogStationClient, Warning, TEXT("Voice link failed: %hs"), Error.what());
			PostState(EStationVoiceState::Failed, FString::Printf(TEXT("LiveKit error: %hs"), Error.what()));
		}
	}

	void PushMicrophone(TConstArrayView<float> Samples, int32 SampleRate, int32 NumChannels)
	{
		FScopeLock Lock(&MicLock);
		if (!bAlive || !bPublished || !bListening || !Source)
		{
			return;
		}
		Framer.Push(Samples, SampleRate, NumChannels, [this](TConstArrayView<int16> Pcm)
		{
			livekit::AudioFrame Frame(std::vector<std::int16_t>(Pcm.GetData(), Pcm.GetData() + Pcm.Num()),
				FStationPcmFramer::SampleRate, 1, Pcm.Num());
			try
			{
				{
					FScopeLock ApmGuard(&ApmLock);
					if (Apm)
					{
						Apm->processStream(Frame);
					}
				}
				Source->captureFrame(Frame);
			}
			catch (const std::exception& Error)
			{
				UE_LOG(LogStationClient, Verbose, TEXT("Dropped a microphone frame: %hs"), Error.what());
			}
		});
	}

	void OnPatientFrame(const livekit::AudioFrame& Frame)
	{
		if (!bAlive)
		{
			return;
		}
		if (Handlers.OnPatientPcm)
		{
			Handlers.OnPatientPcm(TConstArrayView<int16>(Frame.data().data(), Frame.data().size()),
				Frame.sampleRate(), Frame.numChannels());
		}
		// The echo canceller takes 10 ms frames; LiveKit delivers the remote track in them.
		if (Frame.samplesPerChannel() * 100 == Frame.sampleRate())
		{
			livekit::AudioFrame Reference = Frame;
			try
			{
				FScopeLock ApmGuard(&ApmLock);
				if (Apm)
				{
					Apm->processReverseStream(Reference);
				}
			}
			catch (const std::exception&)
			{
				// Without this frame the canceller only adapts a little later.
			}
		}
	}

	/** Leaves the room. Runs off the game thread: a join to an unreachable server can take 30 s to give up. */
	void Close()
	{
		bAlive = false;
		if (ConnectTask.IsValid())
		{
			ConnectTask.Wait();
		}
		{
			FScopeLock Lock(&MicLock);
			bPublished = false;
			Framer.Reset();
		}
		if (Room)
		{
			try
			{
				Room->clearOnAudioFrameCallback(ToStd(WorkerIdentity), ToStd(PatientTrackName));
				Room->disconnect();
			}
			catch (const std::exception& Error)
			{
				UE_LOG(LogStationClient, Warning, TEXT("Voice link did not close cleanly: %hs"), Error.what());
			}
			Room->setDelegate(nullptr);
			Room.reset();
		}
		FScopeLock Lock(&MicLock);
		Track.reset();
		Source.reset();
		FScopeLock ApmGuard(&ApmLock);
		Apm.reset();
	}

	// livekit::RoomDelegate. These run on the SDK event thread and must not block.
	void onParticipantConnected(livekit::Room&, const livekit::ParticipantConnectedEvent& Event) override
	{
		if (Event.participant && Event.participant->identity() == ToStd(WorkerIdentity))
		{
			bWorkerPresent = true;
			PostReadiness();
		}
	}

	void onParticipantDisconnected(livekit::Room&, const livekit::ParticipantDisconnectedEvent& Event) override
	{
		if (Event.participant && Event.participant->identity() == ToStd(WorkerIdentity))
		{
			bWorkerPresent = false;
			PostReadiness();
		}
	}

	void onUserPacketReceived(livekit::Room&, const livekit::UserDataPacketEvent& Event) override
	{
		if (!bAlive || Event.topic != TranscriptTopic || !Event.participant
			|| Event.participant->identity() != ToStd(WorkerIdentity))
		{
			return;
		}
		TOptional<FStationVoiceEvent> Parsed = ParseStationVoiceEvent(
			TConstArrayView<uint8>(Event.data.data(), Event.data.size()), SessionId);
		if (Parsed.IsSet())
		{
			PostEvent(MoveTemp(Parsed.GetValue()));
		}
	}

	void onReconnecting(livekit::Room&, const livekit::ReconnectingEvent&) override
	{
		bReconnecting = true;
		PostReadiness();
	}

	void onReconnected(livekit::Room&, const livekit::ReconnectedEvent&) override
	{
		bReconnecting = false;
		PostReadiness();
	}

	void onDisconnected(livekit::Room&, const livekit::DisconnectedEvent&) override
	{
		if (bAlive)
		{
			bPublished = false;
			PostState(EStationVoiceState::Failed, TEXT("LiveKit closed the room connection."));
		}
	}
};

FStationVoiceLink::FStationVoiceLink(const FStationVoiceCredential& Credential, const FString& SessionId, FStationVoiceHandlers Handlers)
	: Impl(MakeShared<FImpl, ESPMode::ThreadSafe>())
{
	Impl->Url = Credential.Url;
	Impl->Token = Credential.Token;
	Impl->SessionId = SessionId;
	Impl->Handlers = MoveTemp(Handlers);
	Impl->Self = Impl;
}

FStationVoiceLink::~FStationVoiceLink()
{
	Disconnect();
}

void FStationVoiceLink::Connect()
{
	check(IsInGameThread());
	if (State != EStationVoiceState::Disconnected || !Impl->bAlive)
	{
		return;
	}
	Impl->Owner = AsShared();
	SetState(EStationVoiceState::Connecting);
	FImpl* RawImpl = &Impl.Get();
	Impl->ConnectTask = Async(EAsyncExecution::Thread, [RawImpl]() { RawImpl->Connect(); });
}

void FStationVoiceLink::Disconnect()
{
	if (bClosed)
	{
		return;
	}
	bClosed = true;
	// From here no handler runs on the game thread; the room is left in the background.
	Impl->bAlive = false;
	StationLiveKit::RunTeardown([Closing = Impl]() { Closing->Close(); });
	if (State != EStationVoiceState::Disconnected && State != EStationVoiceState::Failed)
	{
		State = EStationVoiceState::Disconnected;
		Failure.Reset();
	}
}

void FStationVoiceLink::PushMicrophonePcm(TConstArrayView<float> Samples, int32 SampleRate, int32 NumChannels)
{
	Impl->PushMicrophone(Samples, SampleRate, NumChannels);
}

void FStationVoiceLink::SetState(EStationVoiceState NewState, const FString& NewFailure)
{
	if (State == NewState && Failure == NewFailure)
	{
		return;
	}
	State = NewState;
	Failure = NewFailure;
	if (NewState == EStationVoiceState::Failed)
	{
		UE_LOG(LogStationClient, Warning, TEXT("Voice link failed: %s"), *NewFailure);
		// The voice is lost for good: leave the room so nothing more is heard or sent.
		if (!bClosed)
		{
			bClosed = true;
			Impl->bAlive = false;
			StationLiveKit::RunTeardown([Closing = Impl]() { Closing->Close(); });
		}
	}
	if (Impl->Handlers.OnStateChanged)
	{
		Impl->Handlers.OnStateChanged(NewState);
	}
}
