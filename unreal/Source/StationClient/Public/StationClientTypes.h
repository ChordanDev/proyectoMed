// Value types of the station client module's public interface. They mirror the
// Phoenix HTTP API (backend/lib/backend_web/router.ex) field by field and carry
// only what Phoenix serves: no clinical rules and no Station Package content.

#pragma once

#include "CoreMinimal.h"
#include "Templates/ValueOrError.h"

#include "StationClientTypes.generated.h"

/** How the station accepts spoken turns, as `voice_mode` in `GET /api/stations/active`. */
UENUM(BlueprintType)
enum class EStationVoiceMode : uint8
{
	/** Spoken turns travel over LiveKit and the voice worker. */
	Realtime,
	/** Spoken turns are uploaded one at a time. */
	Turn,
	/** Voice is unavailable; the station runs on typed turns only. */
	Off,
};

/**
 * The Station Mode the learner chose before entering (#421), as `mode` in the
 * session responses. Fixed for the whole run.
 */
UENUM(BlueprintType)
enum class EStationSessionMode : uint8
{
	/** "Treino". A session Phoenix serves without a mode is a training. */
	Training,
	/** "Prova simulada": performed only by voice, which needs audio consent. */
	SimulatedExam,
};

UENUM(BlueprintType)
enum class EStationSessionStatus : uint8
{
	Active,
	Completed,
};

/** Why a run ends, as `reason` in `POST .../finish`. */
UENUM(BlueprintType)
enum class EStationFinishReason : uint8
{
	/** The learner finished early. */
	User,
	/** The Station Timer reached zero. Phoenix refuses it more than 2 s before the deadline. */
	Timer,
};

UENUM(BlueprintType)
enum class EStationSpeaker : uint8
{
	Learner,
	Patient,
};

UENUM(BlueprintType)
enum class EStationTurnModality : uint8
{
	Text,
	/** A spoken turn already transcribed by the client. Realtime voice goes through LiveKit instead. */
	Voice,
};

/** What Phoenix did with a learner turn. */
UENUM(BlueprintType)
enum class EStationTurnOutcome : uint8
{
	/** The patient answered with text Phoenix approved. */
	PatientReply,
	/** The turn was addressed to the examiner: kept, with no patient reply. */
	ExaminerAcknowledged,
};

UENUM(BlueprintType)
enum class EStationImpressoDecision : uint8
{
	Released,
	AlreadyReleased,
	/** Phoenix declined: nothing matching the request may be shown. */
	Unavailable,
};

UENUM(BlueprintType)
enum class EStationCriterionStatus : uint8
{
	Assessed,
	Uncertain,
	NotObservable,
	NotApplicable,
};

/** The active station as the learner may see it before and during a run. */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationSummary
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString StationId;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Version;

	/** BCP 47 tag of the station content, for example `pt-BR`. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Language;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString DisplayTitle;

	/** The candidate brief scenario, shown before the run starts. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Scenario;

	/** The candidate brief tasks, in the order Phoenix serves them. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	TArray<FString> Tasks;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	EStationVoiceMode VoiceMode = EStationVoiceMode::Off;
};

/** One transcript line of the run. */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationMessage
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	EStationSpeaker Speaker = EStationSpeaker::Learner;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Text;
};

/** One ephemeral station run. The session id is its only credential. */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationSession
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString SessionId;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString StationId;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString StationVersion;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	bool bAudioConsent = false;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	EStationSessionMode Mode = EStationSessionMode::Training;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	EStationSessionStatus Status = EStationSessionStatus::Active;

	/** Why the run ended (`user` or `timer`); empty while it is active. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString CompletionReason;

	/** UTC. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FDateTime StartedAt;

	/** UTC. The Station Timer reaches zero here; Phoenix owns the duration. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FDateTime DeadlineAt;

	/** UTC. Phoenix forgets the session after this. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FDateTime ExpiresAt;

	/** UTC. Set when this client finished the run; Phoenix's show body does not carry it. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FDateTime CompletedAt;

	/** The transcript so far, in order. Only `RefreshSession` fills it. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	TArray<FStationMessage> Messages;
};

/**
 * A short-lived LiveKit join token for this run's room only
 * (`station-session-<id>`, identity `learner-<id>`). Phoenix signs it for about
 * two minutes; join before `ExpiresAt` and ask again for a later join.
 */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationVoiceCredential
{
	GENERATED_BODY()

	/** LiveKit server URL, for example `ws://127.0.0.1:7880`. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Url;

	/** Secret. Never log or display it. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Token;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Room;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Identity;

	/** UTC. The token stops admitting joins here. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FDateTime ExpiresAt;
};

/** A document Phoenix released during the run: an impresso or exam findings. */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationImpresso
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Id;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Title;

	/** Phoenix's category, for example `report`. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Category;

	/** Markdown, shown as Phoenix serves it. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Content;
};

/** Phoenix's answer to a learner turn. */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationTurnReply
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	EStationTurnOutcome Outcome = EStationTurnOutcome::PatientReply;

	/** The approved patient reply; empty for an examiner-addressed turn. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString ReplyText;

	/** Synthesized reply audio for turn-based voice; empty when there is none. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString ReplyAudioUrl;

	/** Impressos an examiner-addressed turn released. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	TArray<FStationImpresso> NewlyReleased;
};

/** Phoenix's decision on an impresso request. */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationImpressoReply
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString RequestId;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	EStationImpressoDecision Decision = EStationImpressoDecision::Unavailable;

	/** Everything released so far in this run. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	TArray<FStationImpresso> ReleasedImpressos;

	/** What this request released. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	TArray<FStationImpresso> NewlyReleased;

	/** Brazilian Portuguese text to show the learner about the decision. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString FeedbackMessage;
};

/** A transcript excerpt that supports a criterion result. */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationEvidence
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Id;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	EStationSpeaker Speaker = EStationSpeaker::Learner;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Text;
};

/** One rubric criterion of the educational result. Points are decimal strings, as Phoenix serves them. */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationCriterionResult
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Id;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Description;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	EStationCriterionStatus Status = EStationCriterionStatus::Uncertain;

	/** Why the criterion was not assessed; empty when it was. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Reason;

	/** Set only when assessed. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Level;

	/** Set only when assessed. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString LevelDescription;

	/** Set only when assessed. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Points;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString MaxPoints;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Recommendation;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	TArray<FStationEvidence> Evidence;
};

/** The unofficial educational result of a finished run (`GET /api/v2/.../result`). */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationResult
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString SessionId;

	/** True when Phoenix served a placeholder instead of a real assessment. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	bool bPlaceholder = false;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	TArray<FStationCriterionResult> Criteria;

	/** Estimated total; empty while any criterion is unresolved. */
	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString EstimatedTotal;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString ScoredSubtotal;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString ScoredMax;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString EligibleMax;
};

/**
 * Why a station client call failed. `Code` is Phoenix's `error` field (for
 * example `session_not_found`) or one of the client's own codes listed in
 * docs/unreal-station-client.md. `HttpStatus` is 0 when no Phoenix answer was
 * involved: Phoenix was unreachable, or the client refused the call itself.
 */
USTRUCT(BlueprintType)
struct STATIONCLIENT_API FStationClientError
{
	GENERATED_BODY()

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	int32 HttpStatus = 0;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Code;

	UPROPERTY(BlueprintReadOnly, Category = "Station")
	FString Message;
};

/** The outcome of a station client call: a value, or why there is none. */
template <typename T>
using TStationResult = TValueOrError<T, FStationClientError>;

/** Completion callback of an asynchronous station client call; runs on the game thread. */
template <typename T>
using TStationCallback = TFunction<void(const TStationResult<T>&)>;

/** The result of a call that returns nothing on success. */
struct FStationNone
{
};
