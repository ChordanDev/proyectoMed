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

UENUM(BlueprintType)
enum class EStationSessionStatus : uint8
{
	Active,
	Completed,
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
