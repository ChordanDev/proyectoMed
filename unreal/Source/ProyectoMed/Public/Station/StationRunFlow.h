// The learner's way through a station run: on first launch the microphone
// disclosure, then the Pre-Station Notice, then the brief Phoenix serves with the
// choice of a text or a voice training or a simulated exam (#421), then the run, where typed turns are
// always available and exam and impresso requests have their own channel, then
// the feedback once the learner or the Station Timer ends it. A run that loses
// Phoenix is invalidated instead (#196). Interface code renders it; only the
// station client talks to the network.

#pragma once

#include "CoreMinimal.h"
#include "Station/StationMicPermission.h"
#include "StationClientTypes.h"
#include "StationVoice.h"
#include "UObject/Object.h"

#include "StationRunFlow.generated.h"

class UStationClient;

UENUM()
enum class EStationRunStep : uint8
{
	/** First launch: what the microphone is used for, and the system permission. */
	Microphone,
	/** The Pre-Station Notice is shown and not yet acknowledged. */
	Notice,
	/** The brief is shown; the learner picks a text or a voice training, or a simulated exam. */
	Brief,
	/** Phoenix is creating the session. */
	Starting,
	/** The session exists and the Station Timer is counting down. */
	Running,
	/** The run has ended for the learner: Phoenix is closing and grading it. */
	Finishing,
	/** The feedback, or why it could not be loaded, until the learner discards the run. */
	Feedback,
	/**
	 * Phoenix stopped answering during the run: it is over, with no feedback and no
	 * partial result, until the learner restarts the station (#196).
	 */
	Invalidated,
};

UENUM()
enum class EStationTrainingMode : uint8
{
	Text,
	Voice,
};

/** One exam or impresso request of this run and Phoenix's decision on it. */
USTRUCT()
struct PROYECTOMED_API FStationExamRequest
{
	GENERATED_BODY()

	/** What the learner asked for, trimmed. */
	UPROPERTY()
	FString Text;

	UPROPERTY()
	FStationImpressoReply Reply;
};

/** A voice training needs Phoenix to serve realtime voice. */
PROYECTOMED_API bool IsVoiceTrainingAvailable(const FStationSummary& Station);

/**
 * Why a simulated exam cannot start, in Brazilian Portuguese, for the brief to
 * show; empty when it can. A simulated exam is performed only by voice, so it
 * needs realtime voice and a microphone the system has not blocked (#421).
 */
PROYECTOMED_API FText SimulatedExamUnavailableText(const FStationSummary& Station, EStationMicPermission Permission);

/**
 * The learner-facing text for a failed call. Phoenix's message is shown only when
 * Phoenix answered with an error status; everything else (unreachable Phoenix, a
 * body the client cannot read) gets `Fallback`, which is Brazilian Portuguese.
 */
PROYECTOMED_API FText StationErrorText(const FStationClientError& Error, const FText& Fallback);

/** The Station Timer as `mm:ss`, rounding partial seconds up so it reads 00:00 only at the deadline. */
PROYECTOMED_API FText FormatStationTimer(const FTimespan& Remaining);

/** Where the flow asks for the microphone and remembers that it did; tests replace it. */
struct PROYECTOMED_API FStationMicrophoneSetup
{
	TFunction<EStationMicPermission()> GetPermission;
	TFunction<void(TFunction<void(EStationMicPermission)>)> RequestPermission;
	TFunction<bool()> WasDisclosureShown;
	TFunction<void()> RememberDisclosureShown;

	/** The operating system's permission, remembered in the game user settings. */
	static FStationMicrophoneSetup System();
};

/** Where the patient's voice goes: the scene's speaker and face; tests pass fakes. */
struct FStationPatientOutput
{
	/** Interleaved int16 PCM from the voice link; a LiveKit thread. */
	TFunction<void(TConstArrayView<int16>, int32, int32)> Audio;
	/** Game thread: stop at once and drop whatever still arrives, until `Resume`. */
	TFunction<void()> Silence;
	/** Game thread: let the voice of the next reply play. */
	TFunction<void()> Resume;
};

/** What the voice of a running voice training shows the learner. */
struct FStationVoiceView
{
	EStationVoiceState State = EStationVoiceState::Disconnected;
	/**
	 * The learner's words while they speak. The final transcript of the turn joins
	 * the conversation (`GetTranscript`) and this is cleared.
	 */
	FString LearnerText;
	/**
	 * The patient's reply while it is spoken, as Phoenix approved it, sentence by
	 * sentence. The whole reply joins the conversation and this is cleared.
	 */
	FString PatientText;
	/** The latest spoken turn went to the examiner, who noted it without a reply. */
	bool bExaminerNoted = false;
	/** The voice stopped for good (`Fatal`, or the link failed). */
	bool bLost = false;
	/** The system microphone would not open for this run; the learner continues in writing. */
	bool bMicrophoneUnavailable = false;
};

UCLASS()
class PROYECTOMED_API UStationRunFlow : public UObject
{
	GENERATED_BODY()

public:
	/**
	 * Shows the microphone disclosure on first launch, otherwise the notice, and
	 * loads the active station in the background.
	 */
	void Begin(UStationClient* InClient, FStationMicrophoneSetup InMicrophone = FStationMicrophoneSetup::System());

	/**
	 * Microphone to notice. `bAllow` asks the system for the microphone now; the
	 * disclosure counts as shown either way, so it is not shown again.
	 */
	void AnswerMicrophone(bool bAllow);

	/** Notice to brief. Does nothing on any other step. */
	void AcknowledgeNotice();

	/** Reloads the station after a failed load. */
	void RetryLoadStation();

	/**
	 * True on the brief once the station is loaded. Voice also needs Phoenix to serve
	 * realtime voice and a microphone the system has not blocked.
	 */
	bool CanEnter(EStationTrainingMode Mode) const;

	/**
	 * Starts the run: the session's audio consent is the chosen mode. A voice
	 * training first asks the system for the microphone if it never did, then asks
	 * Phoenix for the LiveKit credential and joins the room. Without a credential the
	 * run continues as text and `IsVoiceFallback` is true.
	 */
	void Enter(EStationTrainingMode Mode);

	/**
	 * True on the brief once the station is loaded, when `SimulatedExamUnavailableText`
	 * is empty. Trainings stay available either way.
	 */
	bool CanEnterSimulatedExam() const;

	/**
	 * Starts a simulated exam ("Prova simulada", #421): a voice run with audio consent
	 * that Phoenix records as a simulated exam for the whole run. The microphone is
	 * asked for first if the system never did; without it the brief stays, with the
	 * reason. Until #422-#426, the run itself behaves like a voice training.
	 */
	void EnterSimulatedExam();

	/** The microphone as the system allows it now. */
	EStationMicPermission GetMicrophonePermission() const;

	/** What the voice of a voice training shows; empty otherwise. */
	const FStationVoiceView& GetVoice() const { return Voice; }

	/**
	 * The microphone should capture: the run is going on, its voice link is in the room
	 * and the microphone did not fail to open for this run.
	 */
	bool IsListening() const;

	/**
	 * The microphone would not open. Remembered until the run restarts, so the
	 * capture is not retried on every change and the HUD says so.
	 */
	void ReportMicrophoneUnavailable();

	/**
	 * Receives the patient's voice; set it before entering. The flow silences it when
	 * the learner speaks over the patient or the run ends (#193), and lets it play
	 * again with the text of the next reply, which the worker sends before its voice.
	 */
	void SetPatientOutput(FStationPatientOutput InPatient)
	{
		Patient = MoveTemp(InPatient);
	}

	EStationRunStep GetStep() const { return Step; }
	bool IsStationLoading() const { return bLoadingStation; }
	const FStationSummary* GetStation() const { return Station.GetPtrOrNull(); }
	EStationTrainingMode GetMode() const { return Mode; }
	/** The Station Mode of the current or last run; a training until a simulated exam starts. */
	EStationSessionMode GetSessionMode() const { return SessionMode; }
	bool IsVoiceFallback() const { return bVoiceFallback; }

	/** For #191 to join the room. Secret: never log or display the token. */
	const FStationVoiceCredential* GetVoiceCredential() const { return VoiceCredential.GetPtrOrNull(); }

	/**
	 * True while the run is running, no typed turn is waiting for Phoenix and the
	 * transcript is not being reloaded, whatever the microphone does.
	 */
	bool CanSendTurn() const;

	/**
	 * Sends a typed turn, trimmed. Returns false, and sends nothing, when the
	 * text is blank or `CanSendTurn` is false. Once Phoenix answers, the turn and
	 * the reply Phoenix approved join the transcript.
	 */
	bool SendTypedTurn(const FString& Text);

	bool IsTurnInFlight() const { return PendingTurn.IsSet(); }

	/** The typed turn waiting for Phoenix; empty when there is none. */
	FString GetPendingTurnText() const { return PendingTurn.Get(FString()); }

	/** The conversation of this run, in order: only turns Phoenix took and replies it approved. */
	const TArray<FStationMessage>& GetTranscript() const { return Transcript; }

	/** True after a lost answer, while the transcript is reloaded from Phoenix. */
	bool IsReloadingTranscript() const { return bReloadingTranscript; }

	/**
	 * The last typed turn Phoenix did not take, for the interface to give back to
	 * the learner; it is returned once. Empty while the transcript is reloading,
	 * because Phoenix may still have taken it.
	 */
	FString TakeUnsentTurn();

	/** The last failure, in Brazilian Portuguese; empty when there is none. */
	const FText& GetErrorText() const { return ErrorText; }

	/**
	 * True while the run is running and no exam request is waiting for Phoenix.
	 * Exam requests have their own channel (ADR-008): they never wait for, or
	 * join, the patient dialogue.
	 */
	bool CanRequestExam() const;

	/**
	 * Asks Phoenix, with the text trimmed, for physical exam findings or an impresso. Returns
	 * false, and sends nothing, when the text is blank or `CanRequestExam` is
	 * false. Phoenix decides what is released; the flow only keeps its answer.
	 * Resending the text of a request Phoenix did not answer reuses its request
	 * id, so Phoenix records it once.
	 */
	bool RequestExam(const FString& Text);

	bool IsExamRequestInFlight() const { return PendingExamRequest.IsSet(); }

	/** The exam request waiting for Phoenix; empty when there is none. */
	FString GetPendingExamRequestText() const { return PendingExamRequest.IsSet() ? PendingExamRequest->Text : FString(); }

	/** The exam requests Phoenix answered in this run, in order, declined ones included. */
	const TArray<FStationExamRequest>& GetExamRequests() const { return ExamRequests; }

	/** Every document Phoenix released in this run, as of its last answer. */
	const TArray<FStationImpresso>& GetReleasedImpressos() const { return ReleasedImpressos; }

	/** The last exam request Phoenix did not answer, returned once. */
	FString TakeUnsentExamRequest();

	/** The last exam request failure, in Brazilian Portuguese; empty when there is none. */
	const FText& GetExamErrorText() const { return ExamErrorText; }

	/**
	 * In a voice training whose voice and microphone work, exam requests are said
	 * aloud while a button is held (#364); otherwise they are typed.
	 */
	bool ShouldRequestExamsAloud() const;

	/**
	 * True while the run is running, `ShouldRequestExamsAloud` holds and no spoken
	 * exam request is being armed, listened for or answered. A released button whose
	 * grace still runs may be pressed again.
	 */
	bool CanAskExamAloud() const;

	/**
	 * The learner pressed the exam button to say the request aloud. Phoenix arms an
	 * exam mode: the learner's next utterance goes to the impresso request instead
	 * of the patient, and its outcome joins `GetExamRequests` as a typed request's
	 * does. Returns false, and asks nothing, when `CanAskExamAloud` is false.
	 */
	bool AskExamAloud();

	/** True while Phoenix arms the exam mode. */
	bool IsArmingExamAloud() const { return bArmingSpokenExam; }

	/** True while the armed exam mode waits for the learner to start speaking. */
	bool IsListeningForExam() const;

	/**
	 * The learner released the button: the dialogue goes on. A request the learner
	 * started stays the request. If nothing was heard yet, the mode waits two more
	 * seconds for the first caption, then Phoenix disarms it.
	 */
	void ReleaseExamAloud();

	/** True while the spoken exam request is heard or waits for its outcome. */
	bool IsSpokenExamInFlight() const { return SpokenExamTurn != 0; }

	/** What the learner said in that request so far; empty when there is none. */
	const FString& GetSpokenExamText() const { return SpokenExamText; }

	/** True while the run is running. */
	bool CanFinish() const;

	/**
	 * The learner ends the run early. No turn or exam request can be sent from
	 * here on; one still waiting for Phoenix is answered first, so Phoenix grades
	 * it. Then Phoenix closes the run and the flow loads its feedback.
	 */
	void Finish();

	/**
	 * Ends the run as `Finish` does, with the reason `timer`. Phoenix refuses it
	 * before its deadline: the run then goes on, with the deadline read again.
	 * The flow also calls it when Phoenix refuses a turn or exam request because
	 * Phoenix already ended the run, for example after the Mac slept.
	 */
	void ExpireTimer();

	/**
	 * Calls `ExpireTimer` once the Station Timer reads zero, and ends an exam mode the
	 * learner did not speak into once it expires. The interface calls it every frame.
	 */
	void CheckStationTimer();

	/** The feedback of the ended run; null until Phoenix serves it. */
	const FStationResult* GetResult() const { return Result.GetPtrOrNull(); }

	/** True on the feedback while no discard is waiting for Phoenix. */
	bool CanDiscard() const;

	/**
	 * Asks Phoenix to forget the run. Once it confirms, everything this run
	 * held is cleared and the brief is shown, ready for a new run; until then
	 * no new run can start.
	 */
	void Discard();

	/** True while a discard waits for Phoenix. */
	bool IsDiscarding() const { return bDiscarding; }

	/** True once the run is invalidated. */
	bool CanRestart() const;

	/**
	 * Starts over after an invalidated run: the brief is shown, ready for a new run,
	 * without waiting for Phoenix. Phoenix is asked to forget the run in case it is
	 * back; otherwise it forgets it on its own.
	 */
	void Restart();

	UStationClient* GetClient() const { return Client; }

	/** Broadcast after every change the interface should render. */
	FSimpleMulticastDelegate OnChanged;

private:
	// Test access to the voice event handling (StationRunFlowSpec.cpp).
	friend class FStationRunUnitSpec;
	friend class FStationRunPhoenixLossSpec;
	friend class FStationHudSnapshotSpec;
	friend class FStationHudUnitSpec;
	friend class FStationCardSnapshotSpec;

	void LoadStation();
	void BeginEntry(EStationTrainingMode InMode, EStationSessionMode InSessionMode);
	void SetError(const FStationClientError& Error, const FText& Fallback);
	void StartSession();
	void ConnectVoice();
	void HandleVoiceEvent(const FStationVoiceEvent& Event);
	void HandleVoiceState(EStationVoiceState State);

	/**
	 * The voice stopped for good. The run goes on in writing, unless Phoenix does not
	 * answer either.
	 */
	void LoseVoice();

	/**
	 * A call of this run got no answer from Phoenix. The run is invalidated unless
	 * Phoenix answers a check right away; then `OnAnswered` runs, if set.
	 */
	void CheckPhoenix(TFunction<void()> OnAnswered = nullptr);

	/** Phoenix is lost: the run ends here, with nothing kept and the patient silent. */
	void Invalidate();

	/** Moves the spoken reply, if any, into the conversation. */
	void CommitVoiceReply();

	/**
	 * The learner spoke over the current spoken turn before it had an outcome: the
	 * worker cancelled it and Phoenix did not keep it, so its learner line and its
	 * partial reply leave the conversation, as in the web client.
	 */
	void DropSupersededVoiceTurn();

	void SilencePatient();
	void ResumePatient();

	/**
	 * Phoenix answered the spoken exam turn as dialogue after all (the learner finished
	 * it after the mode expired): its learner line joins the conversation.
	 */
	void ReleaseSpokenExamAsDialogue();

	/** The outcome of the spoken exam request joins the exam requests. */
	void TakeSpokenExamOutcome(const FStationVoiceEvent& Event);

	/** Asks Phoenix to disarm the exam mode. */
	void DisarmSpokenExam();

	/** Forgets the exam mode and the spoken exam request, if any. */
	void ResetSpokenExam();

	/** Reads the released impressos again, after a request this client did not send. */
	void ReloadReleasedImpressos();

	void SetExamError(const FStationClientError& Error);

	void AddLine(EStationSpeaker Speaker, const FString& Text);

	/** Forgets everything the last run held, and drops Phoenix's answers for it. */
	void ResetRun();

	void BeginFinish(EStationFinishReason Reason);

	/** Closes the run once no turn or exam request is waiting for Phoenix. */
	void ContinueFinish();

	void LoadResult();

	/** The run is over, but its feedback could not be loaded. */
	void FailResult(const FStationClientError& Error);

	/** `FailResult`, unless Phoenix gave no answer and does not answer a check either. */
	void FailResultUnlessLost(const FStationClientError& Error);

	/**
	 * Replaces the transcript with Phoenix's record, for when `Turn`'s fate is
	 * unknown. `Turn` stays unsent unless the record ends with it.
	 */
	void ReloadTranscript(const FString& Turn);

	UPROPERTY()
	TObjectPtr<UStationClient> Client;

	EStationRunStep Step = EStationRunStep::Notice;
	EStationTrainingMode Mode = EStationTrainingMode::Text;
	EStationSessionMode SessionMode = EStationSessionMode::Training;
	TOptional<FStationSummary> Station;
	TOptional<FStationVoiceCredential> VoiceCredential;
	TOptional<FString> PendingTurn;
	TArray<FStationMessage> Transcript;
	FString UnsentTurn;
	FText ErrorText;

	struct FPendingExamRequest
	{
		FString Text;
		FString RequestId;
	};
	TOptional<FPendingExamRequest> PendingExamRequest;
	TOptional<FPendingExamRequest> UnansweredExamRequest;
	TArray<FStationExamRequest> ExamRequests;
	TArray<FStationImpresso> ReleasedImpressos;
	FString UnsentExamRequest;
	FText ExamErrorText;
	bool bArmingSpokenExam = false;
	/** The learner released the button while Phoenix armed the mode, at `SpokenExamReleasedAt`. */
	bool bReleasedWhileArming = false;
	/** The button was released while the armed mode still listens. */
	bool bSpokenExamReleased = false;
	double SpokenExamReleasedAt = 0.0;
	/** `FPlatformTime::Seconds()` at which the armed exam mode expires; 0 while none is armed. */
	double SpokenExamExpiresAt = 0.0;
	/** The spoken turn the armed exam mode went to; 0 while there is none. */
	int32 SpokenExamTurn = 0;
	FString SpokenExamText;
	EStationFinishReason FinishReason = EStationFinishReason::User;
	TOptional<FStationResult> Result;
	/** `FPlatformTime::Seconds()` before which the timer does not end the run again after Phoenix refused it. */
	double TimerRetryNotBefore = 0.0;
	bool bFinishInFlight = false;
	bool bDiscarding = false;
	bool bLoadingStation = false;
	bool bReloadingTranscript = false;
	bool bVoiceFallback = false;
	FStationMicrophoneSetup Microphone;
	FStationVoiceView Voice;
	int32 VoiceTurnId = 0;
	/** The final transcript of the current spoken turn is in the conversation. */
	bool bVoiceLearnerCommitted = false;
	/** That line's index in `Transcript`; a reload from Phoenix's record forgets it. */
	int32 VoiceLearnerLine = INDEX_NONE;
	/**
	 * Phoenix settled the current spoken turn: a whole or ended reply, an examiner
	 * note, or a kept turn without a reply.
	 */
	bool bVoiceOutcome = false;
	FStationPatientOutput Patient;
	/**
	 * Changes with every new, discarded or invalidated run. A Phoenix answer for an
	 * earlier one is dropped.
	 */
	uint32 Run = 0;
};
