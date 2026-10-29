// The station client: the one object in the Unreal client that talks to
// Phoenix. It holds the current ephemeral session and the clock that anchors the
// Station Timer to Phoenix. Its contract is documented in
// docs/unreal-station-client.md; change it only with both Unreal tracks' agreement.

#pragma once

#include "CoreMinimal.h"
#include "StationClientTypes.h"
#include "StationClock.h"
#include "StationVoice.h"
#include "UObject/Object.h"

#include "StationClient.generated.h"

class FJsonObject;

UCLASS(Config = Game)
class STATIONCLIENT_API UStationClient : public UObject
{
	GENERATED_BODY()

public:
	virtual void PostInitProperties() override;
	virtual void BeginDestroy() override;

	/** Points the client at another Phoenix, for example a test server. */
	void SetPhoenixBaseUrl(const FString& InBaseUrl);
	const FString& GetPhoenixBaseUrl() const { return PhoenixBaseUrl; }

	/** `GET /api/stations/active`: the station a run would start, before any session exists. */
	void FetchActiveStation(TStationCallback<FStationSummary> OnDone);

	/**
	 * `POST /api/stations/active/sessions`: starts a training, and with it the
	 * Station Timer. Fails with `session_in_progress` while this client holds a
	 * session or is already starting one.
	 */
	void StartSession(bool bAudioConsent, TStationCallback<FStationSession> OnDone);

	/**
	 * Starts a run in the chosen Station Mode (#421), as `StartSession` above.
	 * Phoenix refuses a simulated exam without audio consent with
	 * `audio_consent_required`.
	 */
	void StartSession(bool bAudioConsent, EStationSessionMode Mode, TStationCallback<FStationSession> OnDone);

	/**
	 * `GET .../sessions/:id`: reloads the current session and re-anchors the
	 * timer. A run this client saw finish stays completed, with its completion
	 * time, even when the answer was read before the finish.
	 */
	void RefreshSession(TStationCallback<FStationSession> OnDone);

	/**
	 * `POST .../sessions/:id/discard`: asks Phoenix to forget the run. The local
	 * session is cleared only once Phoenix confirms, so a new run cannot start first.
	 */
	void DiscardSession(TStationCallback<FStationNone> OnDone);

	/**
	 * Forgets the current session here only, at once, and leaves its room: for a run
	 * Phoenix stopped answering. Phoenix forgets it after 30 minutes unless a
	 * `DiscardSession` sent first reaches it.
	 */
	void ForgetSession();

	/**
	 * `POST .../sessions/:id/voice`: a short-lived LiveKit credential for this
	 * run's room only. Phoenix refuses it with `no_consent` when the run started
	 * without audio consent, and with `voice_unavailable` when LiveKit is not set up.
	 */
	void RequestVoiceCredential(TStationCallback<FStationVoiceCredential> OnDone);

	/**
	 * `POST .../sessions/:id/messages`: sends a learner turn and returns what
	 * Phoenix approved. Refused locally with `session_completed` once the run ended.
	 * Not idempotent: after a `network_error`, Phoenix may still have taken the
	 * turn, so call `RefreshSession` and read the transcript before resending.
	 */
	void SendTurn(const FString& Text, EStationTurnModality Modality, TStationCallback<FStationTurnReply> OnDone);

	/**
	 * `POST .../sessions/:id/impressos/request`: asks for an impresso or exam
	 * findings outside the patient dialogue. Pass the same `RequestId` to retry a
	 * request; an empty one gets a new id, which only a successful reply returns,
	 * so a caller that may retry after a failure creates its own id first.
	 */
	void RequestImpresso(const FString& Text, const FString& RequestId, TStationCallback<FStationImpressoReply> OnDone);

	/** `GET .../sessions/:id/impressos`: everything released so far in this run. */
	void ListImpressos(TStationCallback<TArray<FStationImpresso>> OnDone);

	/**
	 * `POST .../sessions/:id/exam-mode` (#364): the learner's next utterance in
	 * the room goes to the impresso request instead of the patient, until
	 * `ExpiresAt`. The voice worker sends its outcome as an `ExaminerImpresso`
	 * event. Phoenix refuses it with `no_consent` on a run without audio consent.
	 * Pressing again re-arms it and restarts the expiry.
	 */
	void ArmExamMode(TStationCallback<FStationExamMode> OnDone);

	/** `DELETE .../sessions/:id/exam-mode`: disarms it; succeeds when nothing was armed too. */
	void CancelExamMode(TStationCallback<FStationNone> OnDone);

	/**
	 * `POST .../sessions/:id/finish`: ends the run for good. With `Timer`, Phoenix
	 * answers `deadline_not_reached` when called early; refresh and keep counting.
	 */
	void FinishSession(EStationFinishReason Reason, TStationCallback<FStationSession> OnDone);

	/**
	 * Joins this run's LiveKit room with a credential from `RequestVoiceCredential`
	 * and publishes the microphone the caller pushes into the returned link. The
	 * link leaves the room when the run finishes or is discarded, when
	 * `DisconnectVoice` is called and when this client goes away, so no learner
	 * audio outlives the run. Replaces any link already open. Returns null without
	 * a session in progress.
	 */
	TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> ConnectVoice(const FStationVoiceCredential& Credential,
		FStationVoiceHandlers Handlers);

	/** Leaves the room at once (see `FStationVoiceLink::Disconnect`). */
	void DisconnectVoice();

	/**
	 * The open voice link, or null. Game thread only: the pointer dies when the link is
	 * replaced or dropped. Other threads keep `AsShared()` in a `TWeakPtr` and `Pin()` it.
	 */
	FStationVoiceLink* GetVoice() const { return Voice.Get(); }

	/** `GET /api/v2/.../sessions/:id/result`: the educational result of a finished run. */
	void FetchResult(TStationCallback<FStationResult> OnDone);

	/** The current session, or null before a run starts and after it is discarded. */
	const FStationSession* GetSession() const { return Session.GetPtrOrNull(); }

	/** Station Timer: time left until the session deadline, by Phoenix's clock. Zero without an active session. */
	FTimespan GetRemainingTime() const;
	FTimespan GetRemainingTimeAt(double LocalSeconds) const;

private:
	void AcceptSession(const FStationSession& InSession, const FDateTime& ServerNow);

	/** The URL of a route under the current session, for example `/voice`. */
	FString SessionUrl(const TCHAR* Suffix) const;

	/**
	 * Sends a request and parses its body with `Parse`. Callers check for a
	 * session first. A `TimeoutSeconds` of 0 uses the default request timeout.
	 */
	template <typename T>
	void SendSessionRequest(const FString& Verb, const FString& Url, const TSharedPtr<FJsonObject>& Body,
		TFunction<bool(const FJsonObject&, T&)> Parse, TStationCallback<T> OnDone, float TimeoutSeconds = 0.f);

	/** Takes a refreshed session, keeping a completion this client already knows about. */
	FStationSession MergeRefreshed(const FStationSession& Refreshed) const;

	/** Phoenix origin, without a trailing slash. `-PhoenixUrl=` on the command line overrides it. */
	UPROPERTY(Config)
	FString PhoenixBaseUrl = TEXT("http://127.0.0.1:4000");

	TOptional<FStationSession> Session;
	FStationClock Clock;
	bool bStartInFlight = false;
	TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> Voice;
};
