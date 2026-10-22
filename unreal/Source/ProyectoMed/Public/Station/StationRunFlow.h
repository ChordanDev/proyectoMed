// The learner's way through a station run: Pre-Station Notice, then the brief
// Phoenix serves with the choice of a text or a voice training, then the run,
// where typed turns are always available and exam and impresso requests have
// their own channel, then the feedback once the learner or the Station Timer
// ends it. Interface code renders it; only the station client talks to the
// network.

#pragma once

#include "CoreMinimal.h"
#include "StationClientTypes.h"
#include "UObject/Object.h"

#include "StationRunFlow.generated.h"

class UStationClient;

UENUM()
enum class EStationRunStep : uint8
{
	/** The Pre-Station Notice is shown and not yet acknowledged. */
	Notice,
	/** The brief is shown; the learner picks a text or a voice training. */
	Brief,
	/** Phoenix is creating the session. */
	Starting,
	/** The session exists and the Station Timer is counting down. */
	Running,
	/** The run has ended for the learner: Phoenix is closing and grading it. */
	Finishing,
	/** The feedback, or why it could not be loaded, until the learner discards the run. */
	Feedback,
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
 * The learner-facing text for a failed call. Phoenix's message is shown only when
 * Phoenix answered with an error status; everything else (unreachable Phoenix, a
 * body the client cannot read) gets `Fallback`, which is Brazilian Portuguese.
 */
PROYECTOMED_API FText StationErrorText(const FStationClientError& Error, const FText& Fallback);

/** The Station Timer as `mm:ss`, rounding partial seconds up so it reads 00:00 only at the deadline. */
PROYECTOMED_API FText FormatStationTimer(const FTimespan& Remaining);

UCLASS()
class PROYECTOMED_API UStationRunFlow : public UObject
{
	GENERATED_BODY()

public:
	/** Shows the notice and loads the active station in the background. */
	void Begin(UStationClient* InClient);

	/** Notice to brief. Does nothing on any other step. */
	void AcknowledgeNotice();

	/** Reloads the station after a failed load. */
	void RetryLoadStation();

	/** True on the brief once the station is loaded, and for voice only when Phoenix serves realtime voice. */
	bool CanEnter(EStationTrainingMode Mode) const;

	/**
	 * Starts the run: the session's audio consent is the chosen mode. A voice
	 * training then asks for the LiveKit credential; without one the run
	 * continues as text and `IsVoiceFallback` is true.
	 */
	void Enter(EStationTrainingMode Mode);

	EStationRunStep GetStep() const { return Step; }
	bool IsStationLoading() const { return bLoadingStation; }
	const FStationSummary* GetStation() const { return Station.GetPtrOrNull(); }
	EStationTrainingMode GetMode() const { return Mode; }
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

	/** Calls `ExpireTimer` once the Station Timer reads zero. The interface calls it every frame. */
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

	UStationClient* GetClient() const { return Client; }

	/** Broadcast after every change the interface should render. */
	FSimpleMulticastDelegate OnChanged;

private:
	void LoadStation();
	void SetError(const FStationClientError& Error, const FText& Fallback);
	void SetExamError(const FStationClientError& Error);

	void AddLine(EStationSpeaker Speaker, const FString& Text);

	/** Forgets everything the last run held. */
	void ResetRun();

	void BeginFinish(EStationFinishReason Reason);

	/** Closes the run once no turn or exam request is waiting for Phoenix. */
	void ContinueFinish();

	void LoadResult();

	/** The run is over, but its feedback could not be loaded. */
	void FailResult(const FStationClientError& Error);

	/**
	 * Replaces the transcript with Phoenix's record, for when `Turn`'s fate is
	 * unknown. `Turn` stays unsent unless the record ends with it.
	 */
	void ReloadTranscript(const FString& Turn);

	UPROPERTY()
	TObjectPtr<UStationClient> Client;

	EStationRunStep Step = EStationRunStep::Notice;
	EStationTrainingMode Mode = EStationTrainingMode::Text;
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
	EStationFinishReason FinishReason = EStationFinishReason::User;
	TOptional<FStationResult> Result;
	/** `FPlatformTime::Seconds()` before which the timer does not end the run again after Phoenix refused it. */
	double TimerRetryNotBefore = 0.0;
	bool bFinishInFlight = false;
	bool bDiscarding = false;
	bool bLoadingStation = false;
	bool bReloadingTranscript = false;
	bool bVoiceFallback = false;
};
