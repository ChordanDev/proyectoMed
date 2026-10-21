// The learner's way into a station run: Pre-Station Notice, then the brief
// Phoenix serves with the choice of a text or a voice training, then the run.
// Interface code renders it; only the station client talks to the network.

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
};

UENUM()
enum class EStationTrainingMode : uint8
{
	Text,
	Voice,
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

	/** The last failure, in Brazilian Portuguese; empty when there is none. */
	const FText& GetErrorText() const { return ErrorText; }

	UStationClient* GetClient() const { return Client; }

	/** Broadcast after every change the interface should render. */
	FSimpleMulticastDelegate OnChanged;

private:
	void LoadStation();
	void SetError(const FStationClientError& Error, const FText& Fallback);

	UPROPERTY()
	TObjectPtr<UStationClient> Client;

	EStationRunStep Step = EStationRunStep::Notice;
	EStationTrainingMode Mode = EStationTrainingMode::Text;
	TOptional<FStationSummary> Station;
	TOptional<FStationVoiceCredential> VoiceCredential;
	FText ErrorText;
	bool bLoadingStation = false;
	bool bVoiceFallback = false;
};
