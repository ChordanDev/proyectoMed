#pragma once

#include "Animation/AnimInstance.h"
#include "Animation/AnimInstanceProxy.h"
#include "CoreMinimal.h"
#include "Station/Patient/StationGaze.h"

#include "StationPatientBodyAnim.generated.h"

class UAnimSequence;

/** Plays the body idle loop and turns the neck and head over it (see `UStationPatientBodyAnim`). */
struct FStationPatientBodyProxy : public FAnimInstanceProxy
{
	FStationPatientBodyProxy() = default;
	explicit FStationPatientBodyProxy(UAnimInstance* Instance) : FAnimInstanceProxy(Instance) {}

	virtual void PreUpdate(UAnimInstance* InAnimInstance, float DeltaSeconds) override;
	virtual bool Evaluate(FPoseContext& Output) override;

	TObjectPtr<UAnimSequence> Idle;
	double IdleTime = 0.0;
	FStationGazeAngles HeadTurn;
	float Weight = 0.f;
	FVector HeadForward = FVector::YAxisVector;
	FVector HeadLeft = FVector::XAxisVector;
	FVector HeadUp = FVector::ZAxisVector;
};

/**
 * The patient's body during the consultation (#449). It plays the seated idle loop
 * from #319 and turns `neck_01`, `neck_02` and `head` by the gaze's head turn, a
 * share each, about their own joints. The face copies these joints from the body,
 * so it turns with them.
 */
UCLASS(Transient)
class UStationPatientBodyAnim : public UAnimInstance
{
	GENERATED_BODY()

public:
	/**
	 * Game thread. `Forward`, `Left` and `Up` are where the face points, its left
	 * and its up, in the head joint's own axes.
	 */
	void Setup(UAnimSequence* InIdle, const FVector& Forward, const FVector& Left, const FVector& Up)
	{
		Idle = InIdle;
		HeadForward = Forward;
		HeadLeft = Left;
		HeadUp = Up;
	}

	/** How far the head turns from the idle loop, applied with `InWeight`; game thread. */
	void SetHeadTurn(const FStationGazeAngles& Turn, float InWeight)
	{
		HeadTurn = Turn;
		Weight = InWeight;
	}

protected:
	virtual FAnimInstanceProxy* CreateAnimInstanceProxy() override;
	virtual void DestroyAnimInstanceProxy(FAnimInstanceProxy* InProxy) override;

private:
	friend struct FStationPatientBodyProxy;

	UPROPERTY(Transient)
	TObjectPtr<UAnimSequence> Idle;

	FStationGazeAngles HeadTurn;
	float Weight = 0.f;
	FVector HeadForward = FVector::YAxisVector;
	FVector HeadLeft = FVector::XAxisVector;
	FVector HeadUp = FVector::ZAxisVector;
};
