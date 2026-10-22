#include "LiveKitPatientStream.h"

#include "Async/Async.h"
#include "PatientVoiceSpikeLog.h"

THIRD_PARTY_INCLUDES_START
#include "livekit/livekit.h"
THIRD_PARTY_INCLUDES_END

#include <atomic>
#include <memory>
#include <string>

namespace
{
	std::atomic<bool> GSdkInitialized{false};

	std::string ToStd(const FString& Value)
	{
		return std::string(TCHAR_TO_UTF8(*Value));
	}

	FString ToUnreal(const std::string& Value)
	{
		return FString(UTF8_TO_TCHAR(Value.c_str()));
	}
}

struct FLiveKitPatientStream::FImpl : public livekit::RoomDelegate
{
	FConfig Config;
	FOnPcm OnPcm;
	FOnStatus OnStatus;

	std::unique_ptr<livekit::Room> Room;
	TFuture<void> ConnectTask;
	TFuture<void> AttachTask;
	std::atomic<bool> bStopRequested{false};
	std::atomic<bool> bLoggedFormat{false};
	std::atomic<bool> bAttachRequested{false};
	/** Track the audio callback is registered for; written before Stop reads it. */
	std::string AttachedTrackName;

	void Status(const FString& Line)
	{
		UE_LOG(LogPatientVoiceSpike, Log, TEXT("%s"), *Line);
		if (OnStatus)
		{
			OnStatus(Line);
		}
	}

	void AttachAudio(const std::string& TrackName)
	{
		AttachedTrackName = TrackName;
		Room->setOnAudioFrameCallback(
			ToStd(Config.PublisherIdentity),
			TrackName,
			[this](const livekit::AudioFrame& Frame)
			{
				if (!bLoggedFormat.exchange(true))
				{
					Status(FString::Printf(TEXT("First patient audio frame: %d Hz, %d channel(s), %d samples per channel."),
						Frame.sampleRate(), Frame.numChannels(), Frame.samplesPerChannel()));
				}
				if (OnPcm && !bStopRequested)
				{
					OnPcm(Frame.data().data(), Frame.samplesPerChannel(), Frame.sampleRate(), Frame.numChannels());
				}
			});
	}

	void Connect()
	{
		Room = std::make_unique<livekit::Room>();
		Room->setDelegate(this);

		// With a known track name, register before connecting: the dispatcher
		// attaches the stream when that track is subscribed. Without one, the first
		// audio track of the publisher is attached in onTrackSubscribed.
		if (!Config.TrackName.IsEmpty())
		{
			bAttachRequested = true;
			AttachAudio(ToStd(Config.TrackName));
		}

		livekit::RoomOptions Options;
		Options.auto_subscribe = true;

		Status(FString::Printf(TEXT("Connecting to %s..."), *Config.Url));
		const double StartSeconds = FPlatformTime::Seconds();
		const bool bConnected = Room->connect(ToStd(Config.Url), ToStd(Config.Token), Options);
		const double ElapsedMs = (FPlatformTime::Seconds() - StartSeconds) * 1000.0;

		if (bConnected)
		{
			Status(FString::Printf(TEXT("Connected in %.0f ms. Waiting for track '%s' from '%s'."),
				ElapsedMs, *Config.TrackName, *Config.PublisherIdentity));
		}
		else
		{
			Status(FString::Printf(TEXT("Connection failed after %.0f ms."), ElapsedMs));
		}
	}

	// livekit::RoomDelegate. These run on the SDK event thread and must not block.
	void onTrackSubscribed(livekit::Room&, const livekit::TrackSubscribedEvent& Event) override
	{
		const FString Identity = Event.participant ? ToUnreal(Event.participant->identity()) : TEXT("?");
		const FString Track = Event.track ? ToUnreal(Event.track->name()) : TEXT("?");
		Status(FString::Printf(TEXT("Subscribed to track '%s' from '%s'."), *Track, *Identity));

		const bool bIsPublisherAudio = Event.track && Event.track->kind() == livekit::TrackKind::KIND_AUDIO
			&& Identity == Config.PublisherIdentity;
		if (bIsPublisherAudio && Config.TrackName.IsEmpty() && !bAttachRequested.exchange(true))
		{
			// Registering a callback from inside a delegate callback could block the
			// SDK event thread, so attach from a worker thread.
			const std::string TrackName = Event.track->name();
			AttachTask = Async(EAsyncExecution::Thread, [this, TrackName]()
			{
				if (!bStopRequested)
				{
					AttachAudio(TrackName);
				}
			});
		}
	}

	void onTrackUnsubscribed(livekit::Room&, const livekit::TrackUnsubscribedEvent&) override
	{
		Status(TEXT("A remote track was unsubscribed."));
	}

	void onParticipantConnected(livekit::Room&, const livekit::ParticipantConnectedEvent& Event) override
	{
		const FString Identity = Event.participant ? ToUnreal(Event.participant->identity()) : TEXT("?");
		Status(FString::Printf(TEXT("Participant joined: %s"), *Identity));
	}

	void onDisconnected(livekit::Room&, const livekit::DisconnectedEvent&) override
	{
		Status(TEXT("Disconnected from the room."));
	}

	void onReconnecting(livekit::Room&, const livekit::ReconnectingEvent&) override
	{
		Status(TEXT("Reconnecting..."));
	}

	void onReconnected(livekit::Room&, const livekit::ReconnectedEvent&) override
	{
		Status(TEXT("Reconnected."));
	}
};

FLiveKitPatientStream::FLiveKitPatientStream(FConfig InConfig, FOnPcm InOnPcm, FOnStatus InOnStatus)
	: Impl(MakeUnique<FImpl>())
{
	Impl->Config = MoveTemp(InConfig);
	Impl->OnPcm = MoveTemp(InOnPcm);
	Impl->OnStatus = MoveTemp(InOnStatus);
}

FLiveKitPatientStream::~FLiveKitPatientStream()
{
	Stop();
}

void FLiveKitPatientStream::Start()
{
	if (!InitializeSdk())
	{
		Impl->Status(TEXT("LiveKit SDK failed to initialise."));
		return;
	}

	FImpl* RawImpl = Impl.Get();
	Impl->ConnectTask = Async(EAsyncExecution::Thread, [RawImpl]() { RawImpl->Connect(); });
}

void FLiveKitPatientStream::Stop()
{
	if (!Impl || Impl->bStopRequested.exchange(true))
	{
		return;
	}

	if (Impl->ConnectTask.IsValid())
	{
		Impl->ConnectTask.Wait();
	}
	if (Impl->AttachTask.IsValid())
	{
		Impl->AttachTask.Wait();
	}

	if (Impl->Room)
	{
		if (!Impl->AttachedTrackName.empty())
		{
			Impl->Room->clearOnAudioFrameCallback(ToStd(Impl->Config.PublisherIdentity), Impl->AttachedTrackName);
		}
		Impl->Room->disconnect();
		Impl->Room->setDelegate(nullptr);
		Impl->Room.reset();
	}
}

bool FLiveKitPatientStream::InitializeSdk()
{
	if (GSdkInitialized)
	{
		return true;
	}

	// `initialize` answers false when the station client already did it.
	livekit::initialize(livekit::LogLevel::Warn);
	GSdkInitialized = true;
	return GSdkInitialized;
}

void FLiveKitPatientStream::ShutdownSdk()
{
	if (GSdkInitialized.exchange(false))
	{
		livekit::shutdown();
	}
}
