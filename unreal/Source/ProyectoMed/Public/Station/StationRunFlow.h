// The learner's way through a station run: on first launch the microphone
// disclosure, then the main menu, where the learner chooses a training or a
// simulated exam (#421), then the Pre-Station Notice once per launch, then the
// brief Phoenix serves with that mode's way in (a text or a voice training, or
// the simulated exam by voice), then the run, where typed turns are
// always available and exam and impresso requests have their own channel, then
// the feedback once the learner or the Station Timer ends it. A run that loses
// Phoenix is invalidated instead (#196). Interface code renders it; only the
// station client talks to the network.

#pragma once

#include "Containers/Ticker.h"
#include "CoreMinimal.h"
#include "Station/StationMicPermission.h"
#include "Station/StationTalkKey.h"
#include "StationClientTypes.h"
#include "StationVoice.h"
#include "UObject/Object.h"

#include <atomic>

#include "StationRunFlow.generated.h"

class UStationClient;

UENUM()
enum class EStationRunStep : uint8
{
	/** First launch: what the microphone is used for, and the system permission. */
	Microphone,
	/** The main menu: the learner chooses a training or a simulated exam (#421). */
	Menu,
	/** The Pre-Station Notice is shown and not yet acknowledged. */
	Notice,
	/**
	 * The brief is shown with the chosen mode's way in: a text or a voice training, or
	 * the simulated exam.
	 */
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
	 * Phoenix stopped answering during the run, or a simulated exam lost its voice
	 * (#422): it is over, with no feedback and no partial result, until the learner
	 * restarts the station (#196). `GetInvalidation` says which.
	 */
	Invalidated,
};

/** Why a run was invalidated. Neither reason keeps a result or a penalty (#318 business rule 8). */
UENUM()
enum class EStationInvalidation : uint8
{
	/** Phoenix stopped answering during the run (#196). */
	PhoenixLost,
	/** The voice or the microphone failed in a simulated exam, which is performed only by voice (#422). */
	VoiceLost,
};

UENUM()
enum class EStationTrainingMode : uint8
{
	Text,
	Voice,
};

/** A sound of the exam room in a simulated exam (#425), as the official entry and finishing beeps. */
UENUM()
enum class EStationExamCue : uint8
{
	/** The time starts running. */
	Start,
	/** The time is up. */
	End,
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

/** The invalidated screen's title, in Brazilian Portuguese; it names the run's Station Mode. */
PROYECTOMED_API FText StationInvalidatedTitle(EStationSessionMode SessionMode);

/** Why the run is over, in Brazilian Portuguese, for the invalidated screen. */
PROYECTOMED_API FText StationInvalidatedText(EStationSessionMode SessionMode, EStationInvalidation Reason);

/**
 * The Station Timer as `mm:ss`, rounding partial seconds up so it reads 00:00 only at
 * the deadline. Past it, a negative `Remaining` reads as the overtime, `+mm:ss` (#461).
 */
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
	 * Shows the microphone disclosure on first launch, otherwise the main menu, and
	 * loads the active station in the background.
	 */
	void Begin(UStationClient* InClient, FStationMicrophoneSetup InMicrophone = FStationMicrophoneSetup::System());

	/**
	 * Microphone to menu. `bAllow` asks the system for the microphone now; the
	 * disclosure counts as shown either way, so it is not shown again.
	 */
	void AnswerMicrophone(bool bAllow);

	/**
	 * Menu to the chosen Station Mode (#421): the notice the first time in this launch,
	 * otherwise straight to the brief. Does nothing on any other step. Why the station
	 * did not load stays shown; any other error is cleared.
	 */
	void ChooseMode(EStationSessionMode InMode);

	/** Notice to brief. Does nothing on any other step. */
	void AcknowledgeNotice();

	/**
	 * Notice or brief back to the menu. Does nothing on any other step. Why the station
	 * did not load stays shown; any other error is cleared.
	 */
	void BackToMenu();

	/** Reloads the station after a failed load. */
	void RetryLoadStation();

	/**
	 * True on a training's brief once the station is loaded. Voice also needs Phoenix to
	 * serve realtime voice and a microphone the system has not blocked.
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
	 * True on a simulated exam's brief once the station is loaded, when
	 * `SimulatedExamUnavailableText` is empty. Trainings stay available from the menu.
	 */
	bool CanEnterSimulatedExam() const;

	/**
	 * Starts a simulated exam ("Prova simulada", #421): a voice run with audio consent
	 * that Phoenix records as a simulated exam for the whole run. The microphone is
	 * asked for first if the system never did; without it the brief stays, with the
	 * reason. The run is voice only (#422) and shows the exam room (#425); #423, #424
	 * and #426 change it further.
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
	 * capture is not retried on every change and the HUD says so. A simulated exam,
	 * which is voice only, is invalidated (#422).
	 */
	void ReportMicrophoneUnavailable();

	/**
	 * Push-to-talk (#419): the learner pressed the talk key, the space bar or the
	 * HUD's talk button. The voice worker hears the learner only while it is held.
	 * While the patient answers, a single press does nothing: a tap followed by a
	 * press opens the microphone and cuts the patient at once. With `bForExam` (the
	 * exam button, or Shift + space bar) the press also arms the exam mode, so what
	 * is said goes to the impresso request (#364); it needs `CanAskExamAloud`. True
	 * when the press opened the microphone.
	 */
	bool PressTalkKey(bool bForExam = false, EStationTalkInput Input = EStationTalkInput::Keyboard);

	/**
	 * The learner released the talk key on `Input`. The microphone closes a moment later,
	 * so the last word still reaches the worker, and the worker then ends the turn at
	 * once. A release on an input that does not hold the key changes nothing.
	 */
	void ReleaseTalkKey(EStationTalkInput Input = EStationTalkInput::Keyboard);

	/** The talk key is held and the microphone open. */
	bool IsTalking() const { return TalkKey.IsHeld(); }

	/** The talk key is held for an exam request. */
	bool IsTalkingForExam() const { return TalkKey.IsHeld() && bTalkKeyForExam; }

	/** A press of the talk key can open the microphone: the voice of a running voice training is ready. */
	bool CanTalk() const;

	/**
	 * The patient is answering: the learner's spoken or typed turn waits for its reply,
	 * a typed turn's reply is about to be spoken, or the patient's voice was heard in
	 * the last half second.
	 */
	bool IsPatientAnswering() const;

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
	/** The Station Mode last chosen on the menu; a training until the learner first chooses one. */
	EStationSessionMode GetSessionMode() const { return SessionMode; }
	bool IsVoiceFallback() const { return bVoiceFallback; }
	/** Why the run was invalidated; meaningful only on `EStationRunStep::Invalidated`. */
	EStationInvalidation GetInvalidation() const { return Invalidation; }

	/** For #191 to join the room. Secret: never log or display the token. */
	const FStationVoiceCredential* GetVoiceCredential() const { return VoiceCredential.GetPtrOrNull(); }

	/**
	 * Whether the run takes typed turns and typed exam requests (#422): a training
	 * does, a simulated exam does not, since it is performed only by voice. Its
	 * exams are asked aloud (`AskExamAloud`).
	 */
	bool AllowsTypedInput() const { return SessionMode != EStationSessionMode::SimulatedExam; }

	/**
	 * Whether the HUD counts the Station Timer: a training does; a simulated exam shows
	 * no countdown, only the desk clock in the room (#425).
	 */
	bool ShowsStationTimer() const;

	/**
	 * The station's scenario and tasks may be shown: on a training's brief, and in a
	 * simulated exam only once its time runs, so reading them counts inside it (#318 T3).
	 */
	bool CanReadBrief() const;

	/**
	 * A running simulated exam shows its brief over the room. It opens when the time
	 * starts, and the learner closes it and opens it again at will.
	 */
	bool IsBriefOpen() const;

	/** Shows the brief again in a running simulated exam; does nothing otherwise. */
	void OpenBrief();

	/** Back to the room from the brief. */
	void CloseBrief();

	/**
	 * The time of day the desk clock shows (#425), in this machine's time zone: by
	 * Phoenix's clock (`GetServerTime`) once it is known, by the machine's before.
	 */
	FDateTime GetDeskClockTime() const;

	/**
	 * Broadcast for the room to sound a cue in a simulated exam: `Start` once its time
	 * runs, `End` once the run ends because its time is up (#425). Never in a training.
	 */
	TMulticastDelegate<void(EStationExamCue)> OnExamCue;

	/**
	 * True while the run is running, takes typed input (`AllowsTypedInput`), no
	 * typed turn is waiting for Phoenix and the transcript is not being reloaded,
	 * whatever the microphone does.
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
	 * True while the run is running, takes typed input (`AllowsTypedInput`) and no
	 * exam request is waiting for Phoenix. Exam requests have their own channel
	 * (ADR-008): they never wait for, or join, the patient dialogue.
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
	 * before `deadline_at`: the run then goes on, with the deadline read again.
	 * The flow also calls it when Phoenix refuses a turn or exam request because
	 * Phoenix already ended the run, for example after the Mac slept.
	 */
	void ExpireTimer();

	/**
	 * Calls `ExpireTimer` at the end Phoenix set for the run, `cap_at`, and ends an exam
	 * mode the learner did not speak into once it expires. A training runs on past the
	 * Station Timer's zero until then (#323). The interface calls it every frame.
	 */
	void CheckStationTimer();

	/** The feedback of the ended run; null until Phoenix serves it. */
	const FStationResult* GetResult() const { return Result.GetPtrOrNull(); }

	/** True on the feedback while no discard is waiting for Phoenix. */
	bool CanDiscard() const;

	/**
	 * Asks Phoenix to forget the run. Once it confirms, everything this run
	 * held is cleared and the menu is shown, ready for a new run; until then
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
	friend class FStationRunAudioOnlySpec;
	friend class FStationHudSnapshotSpec;
	friend class FStationHudUnitSpec;
	friend class FStationCardSnapshotSpec;
	friend class FStationBriefUnitSpec;

	void LoadStation();
	void BeginEntry(EStationTrainingMode InMode, EStationSessionMode InSessionMode);

	/** Clears the last mode's failure on the way through the menu, but not why the station did not load. */
	void ForgetModeError();
	void SetError(const FStationClientError& Error, const FText& Fallback);
	void StartSession();
	void ConnectVoice();
	void HandleVoiceEvent(const FStationVoiceEvent& Event);
	void HandleVoiceState(EStationVoiceState State);

	/**
	 * The voice stopped for good. A training goes on in writing, unless Phoenix does
	 * not answer either; a simulated exam, which is voice only, is invalidated (#422).
	 */
	void LoseVoice();

	/**
	 * A call of this run got no answer from Phoenix. The run is invalidated unless
	 * Phoenix answers a check right away; then `OnAnswered` runs, if set.
	 */
	void CheckPhoenix(TFunction<void()> OnAnswered = nullptr);

	/**
	 * Phoenix is lost, or the voice of a simulated exam is: the run ends here, with
	 * nothing kept and the patient silent.
	 */
	void Invalidate(EStationInvalidation Reason = EStationInvalidation::PhoenixLost);

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

	/** The learner cut the patient with the talk key: its voice stops and the turn it answers is dropped. */
	void CutPatient();
	/**
	 * Stamps `HeardAt` when `Samples` of the patient's voice are loud and would play,
	 * that is unless the patient is silenced. Any thread.
	 */
	static void NotePatientVoice(TConstArrayView<int16> Samples, std::atomic<double>& HeardAt, const std::atomic<bool>& bSilenced);
	/** Opens or closes the voice link's microphone to match the talk key. */
	void ApplyTalkKey();

	/**
	 * Phoenix answered the spoken exam turn as dialogue after all (the learner finished
	 * it after the mode expired): its learner line joins the conversation.
	 */
	void ReleaseSpokenExamAsDialogue();

	/** The outcome of the spoken exam request joins the exam requests. */
	void TakeSpokenExamOutcome(const FStationVoiceEvent& Event);

	/** A spoken exam request's outcome joins the exam requests, and the released impressos are read again. */
	void AddSpokenExamOutcome(const FString& Text, const FStationVoiceEvent& Event);

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
	/** The Pre-Station Notice was acknowledged in this launch; it is not shown again. */
	bool bNoticeAcknowledged = false;
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
	/**
	 * Spoken exam requests newer speech superseded before their outcome arrived, by
	 * turn, with what the learner asked for: Phoenix may have recorded them (#434).
	 */
	TMap<int32, FString> SupersededExamRequests;
	EStationFinishReason FinishReason = EStationFinishReason::User;
	TOptional<FStationResult> Result;
	/** `FPlatformTime::Seconds()` before which the timer does not end the run again after Phoenix refused it. */
	double TimerRetryNotBefore = 0.0;
	bool bFinishInFlight = false;
	bool bDiscarding = false;
	bool bLoadingStation = false;
	bool bReloadingTranscript = false;
	bool bVoiceFallback = false;
	/** A running simulated exam shows its brief (`IsBriefOpen`). */
	bool bBriefOpen = false;
	/** The `End` cue of this run sounded. */
	bool bEndCueSounded = false;
	EStationInvalidation Invalidation = EStationInvalidation::PhoenixLost;
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
	FStationTalkKey TalkKey;
	/** The held talk key arms the exam mode: its release releases the exam button too. */
	bool bTalkKeyForExam = false;
	/** Closes the microphone once the release tail is over. */
	FTSTicker::FDelegateHandle TalkTailTicker;
	/** `FPlatformTime::Seconds()` when the patient's voice was last heard; written on a LiveKit thread. */
	TSharedRef<std::atomic<double>, ESPMode::ThreadSafe> PatientHeardAt = MakeShared<std::atomic<double>, ESPMode::ThreadSafe>(0.0);
	/** The patient is silenced (`SilencePatient`) until its next reply resumes it; read on a LiveKit thread. */
	TSharedRef<std::atomic<bool>, ESPMode::ThreadSafe> PatientSilenced = MakeShared<std::atomic<bool>, ESPMode::ThreadSafe>(false);
	/** The spoken turn the learner cut with the talk key; its late events are dropped. */
	int32 CutVoiceTurnId = 0;
	/** `FPlatformTime::Seconds()` until which a typed turn's reply, already shown, waits for its voice. */
	double TypedReplyVoiceUntil = 0.0;
	/** The current spoken turn failed, for example its synthesis: the patient will not answer it. */
	bool bVoiceTurnFailed = false;
	/**
	 * Changes with every new, discarded or invalidated run. A Phoenix answer for an
	 * earlier one is dropped.
	 */
	uint32 Run = 0;
};
