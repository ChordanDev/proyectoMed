// The analog clock on the office desk (#425): a plain clock with hands, like the
// one on the table in the Revalida practical exam, instead of an on-screen
// countdown. The player controller sets it every frame from the run flow, which
// reads Phoenix's clock through the station client. It also sounds the exam's
// start and end beeps, so the level references the sounds and the cook takes them.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Station/StationRunFlow.h"

#include "StationDeskClock.generated.h"

class UMaterialInterface;
class USceneComponent;
class USoundBase;
class UStaticMeshComponent;

/** Where the hands point, in degrees clockwise from twelve as seen from the front. */
struct FStationClockHands
{
	double Hour = 0.0;
	double Minute = 0.0;
	double Second = 0.0;
};

/** The hands for a time of day; they sweep, the second hand included. */
PROYECTOMED_API FStationClockHands StationClockHands(const FDateTime& Time);

/**
 * A hand's rotation on a face that looks along the clock's +X, with twelve at +Z:
 * clockwise as seen from the front, so three o'clock is at -Y.
 */
PROYECTOMED_API FRotator StationClockHandRotation(double Degrees);

UCLASS()
class PROYECTOMED_API AStationDeskClock : public AActor
{
	GENERATED_BODY()

public:
	AStationDeskClock();

	/** Points the hands at `LocalTime`, a time of day. */
	void ShowTime(const FDateTime& LocalTime);

	/** Plays the cue's sound, if the level set one. */
	void PlayCue(EStationExamCue Cue);

	/** The beep when a simulated exam's time starts. */
	UPROPERTY(EditAnywhere, Category = "Station")
	TObjectPtr<USoundBase> StartSound;

	/** The beep when a simulated exam's time is up. */
	UPROPERTY(EditAnywhere, Category = "Station")
	TObjectPtr<USoundBase> EndSound;

protected:
	virtual void OnConstruction(const FTransform& Transform) override;
	virtual void BeginPlay() override;

private:
	friend class FStationDeskClockUnitSpec;

	UStaticMeshComponent* AddPart(const TCHAR* Name, USceneComponent* Parent, bool bCylinder,
		const FVector& Location, const FVector& Scale, const FRotator& Rotation = FRotator::ZeroRotator);

	/** Gives each part its colour; the level runs no construction script in a packaged build. */
	void PaintParts();

	/**
	 * A hand: a pivot at the face's centre, turned by the time, holding a bar that points
	 * to twelve. The bar joins `Colour`, one of the part lists below.
	 */
	USceneComponent* AddHand(const TCHAR* Name, double Length, double Width, double Depth,
		TArray<TObjectPtr<UStaticMeshComponent>>& Colour);

	UPROPERTY(VisibleAnywhere, Category = "Station")
	TObjectPtr<USceneComponent> Face;

	UPROPERTY(VisibleAnywhere, Category = "Station")
	TObjectPtr<USceneComponent> HourHand;

	UPROPERTY(VisibleAnywhere, Category = "Station")
	TObjectPtr<USceneComponent> MinuteHand;

	UPROPERTY(VisibleAnywhere, Category = "Station")
	TObjectPtr<USceneComponent> SecondHand;

	/** The engine's plain material with a `Color` parameter, tinted for each kind of part. */
	UPROPERTY()
	TObjectPtr<UMaterialInterface> PlainMaterial;

	/** Every part, by colour, for `PaintParts`. */
	UPROPERTY()
	TArray<TObjectPtr<UStaticMeshComponent>> CaseParts;

	UPROPERTY()
	TArray<TObjectPtr<UStaticMeshComponent>> DialParts;

	UPROPERTY()
	TArray<TObjectPtr<UStaticMeshComponent>> InkParts;

	UPROPERTY()
	TArray<TObjectPtr<UStaticMeshComponent>> SecondParts;
};
