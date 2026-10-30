#pragma once

#include "Components/ActorComponent.h"
#include "CoreMinimal.h"
#include "Station/Patient/StationGaze.h"

#include "StationPatientGaze.generated.h"

class UAnimSequence;
class USkeletalMeshComponent;
enum class EStationRunStep : uint8;

/**
 * Where the patient looks during the consultation (#449): at the learner's view,
 * the camera tagged `StationView`, for stretches while either of them speaks, and
 * away now and then. It turns the body's neck and head, which the face follows,
 * and the face's eye-look controls while the face plays `UStationPatientFaceAnim`.
 * The mouth and the seated body idle keep playing underneath.
 */
UCLASS(Transient)
class UStationPatientGaze : public UActorComponent
{
	GENERATED_BODY()

public:
	UStationPatientGaze();

	/** The first camera tagged `StationView` in `World`, or null. */
	static AActor* FindLookTarget(UWorld* World);

	/**
	 * The gaze for a run at `Step`: spoken runs only, and listening while the learner
	 * holds the talk key, answering while the patient answers, resting otherwise.
	 */
	static EStationGazeMode ModeFor(EStationRunStep Step, bool bSpokenRun, bool bLearnerTalking, bool bPatientAnswering);

	/**
	 * Starts on the patient's `Body` and `Face`, with the body's idle loop kept
	 * underneath. `Mode` is asked every frame.
	 */
	void Start(USkeletalMeshComponent* Body, USkeletalMeshComponent* Face, TFunction<EStationGazeMode()> Mode);

	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

protected:
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

private:
	/** Where the patient's eyes are, between the two eye joints. */
	FVector EyeCenter() const;

	FStationGazeModel Model;
	TFunction<EStationGazeMode()> ModeSource;
	TWeakObjectPtr<AActor> LookTarget;

	/** The head joint's own axes for where the face points, its left and up. */
	FVector HeadForward = FVector::YAxisVector;
	FVector HeadLeft = FVector::XAxisVector;
	FVector HeadUp = FVector::ZAxisVector;

	UPROPERTY(Transient)
	TObjectPtr<USkeletalMeshComponent> BodyMesh;

	UPROPERTY(Transient)
	TObjectPtr<USkeletalMeshComponent> FaceMesh;

	UPROPERTY(Transient)
	TObjectPtr<UAnimSequence> BodyIdle;
};
