// The run's LiveKit voice link (#191): publishes the learner's microphone to the
// run's room and delivers what the voice worker sends back, the patient's voice
// as PCM and the `transcript` events. Audio never goes through Phoenix. Its
// contract is documented in docs/unreal-station-client.md.

#pragma once

#include "CoreMinimal.h"
#include "StationClientTypes.h"
#include "Templates/SharedPointer.h"

/** What the voice worker said on the `transcript` topic, as the web client reads it. */
enum class EStationVoiceEventKind : uint8
{
	/** The learner's speech: an interim caption, or the final turn transcript. */
	Learner,
	/** One verified sentence of the patient reply, as spoken. */
	PatientText,
	/** Every sentence of a streamed reply was sent; carries no text. */
	PatientComplete,
	/** The turn was addressed to the examiner; Phoenix kept it unanswered. */
	ExaminerAcknowledged,
	/** The patient reply was refused; Phoenix kept the learner turn without one. */
	PatientUnanswered,
	/** A failure of one turn, for example `synthesis_failed`; the run goes on. */
	TurnFailure,
	/** The worker stopped listening to this run. */
	Fatal,
};

struct STATIONCLIENT_API FStationVoiceEvent
{
	EStationVoiceEventKind Kind = EStationVoiceEventKind::Learner;
	/** Phoenix's turn id; 0 only for `Fatal`. */
	int32 TurnId = 0;
	/** `Learner` only: false for an interim caption. */
	bool bFinal = false;
	/** `PatientText` only: the sentence index of a streamed reply, or INDEX_NONE. */
	int32 Segment = INDEX_NONE;
	/** `Learner` and `PatientText`: the text. Shown to the learner, never logged. */
	FString Text;
	/** `TurnFailure` and `Fatal`: the failure code. */
	FString Failure;
};

/**
 * Reads one `transcript` data message. Strict like the web parser
 * (web/src/features/station/hooks/voiceTranscriptEvents.ts): anything malformed,
 * or bound to another session, is dropped.
 */
STATIONCLIENT_API TOptional<FStationVoiceEvent> ParseStationVoiceEvent(TConstArrayView<uint8> Payload, const FString& SessionId);

enum class EStationVoiceState : uint8
{
	/** Not joined, or left. */
	Disconnected,
	/** Joining the room and publishing the microphone. */
	Connecting,
	/** In the room with the microphone published, waiting for the voice worker. Becomes `Failed` after 20 seconds. */
	WaitingForWorker,
	/** The voice worker is in the room: speech is heard and answered. */
	Ready,
	/**
	 * LiveKit is retrying the room connection, or the voice worker that answered has
	 * left. The microphone is dropped. Becomes `Failed` after 10 seconds.
	 */
	Reconnecting,
	/**
	 * Joining or publishing failed, or the voice worker never joined or did not come
	 * back; `GetFailure()` says why. Final: the link has left the room.
	 */
	Failed,
};

/** Callbacks of a voice link. Each runs on the thread its comment names. */
struct FStationVoiceHandlers
{
	/** Game thread. */
	TFunction<void(const FStationVoiceEvent&)> OnEvent;
	/** Game thread. */
	TFunction<void(EStationVoiceState)> OnStateChanged;
	/**
	 * A LiveKit thread, every 10 ms while the patient speaks: interleaved int16 PCM
	 * of the worker's `patient-voice` track. Must not block.
	 */
	TFunction<void(TConstArrayView<int16> Samples, int32 SampleRate, int32 NumChannels)> OnPatientPcm;
};

/**
 * One run's voice link. Create it through `UStationClient::ConnectVoice`, which
 * also ends it with the run. The microphone is whatever the caller pushes: the game
 * pushes the captured device, tests push generated audio. It is push-to-talk (#419):
 * published muted, it sends only while `SetMicrophoneOpen(true)`. Echo of the
 * patient's voice is cancelled before the audio leaves the machine.
 */
class STATIONCLIENT_API FStationVoiceLink : public TSharedFromThis<FStationVoiceLink, ESPMode::ThreadSafe>
{
public:
	/** Identity and track the voice worker publishes the patient's voice with. */
	static const TCHAR* WorkerIdentity;
	static const TCHAR* PatientTrackName;

	FStationVoiceLink(const FStationVoiceCredential& Credential, const FString& SessionId, FStationVoiceHandlers Handlers);
	~FStationVoiceLink();

	/** Joins the room on a background thread; returns at once. Game thread. */
	void Connect();

	/**
	 * Leaves the room in the background and returns at once, even while a join to an
	 * unreachable server is still hanging. No game-thread handler runs after it
	 * returns, and the microphone is dropped; an `OnPatientPcm` call already under
	 * way may still finish. Safe to call twice. Game thread.
	 */
	void Disconnect();

	/**
	 * Learner microphone audio, interleaved float samples in [-1, 1], any rate and
	 * channel count. Dropped unless the link is `WaitingForWorker` or `Ready` and the
	 * microphone is open. Any thread, one at a time.
	 */
	void PushMicrophonePcm(TConstArrayView<float> Samples, int32 SampleRate, int32 NumChannels);

	/**
	 * Opens or closes the microphone; it starts closed. The track stays published and
	 * is muted while closed, and the voice worker hears the mute as the learner
	 * releasing the talk key: it ends the turn at once instead of waiting for the end
	 * of speech, and an unmute interrupts the patient (#419). The learner cannot
	 * publish data (#364), so the mute is the signal. Game thread.
	 */
	void SetMicrophoneOpen(bool bOpen);
	bool IsMicrophoneOpen() const;

	/** Game thread. */
	EStationVoiceState GetState() const { return State; }
	/** Why the link failed, in English, for logs; empty unless `Failed`. */
	const FString& GetFailure() const { return Failure; }

private:
	struct FImpl;
	/** Set once and kept until the link is destroyed, so other threads can always reach it. */
	TSharedRef<FImpl, ESPMode::ThreadSafe> Impl;
	bool bClosed = false;
	EStationVoiceState State = EStationVoiceState::Disconnected;
	FString Failure;

	void SetState(EStationVoiceState NewState, const FString& NewFailure = FString());
};
