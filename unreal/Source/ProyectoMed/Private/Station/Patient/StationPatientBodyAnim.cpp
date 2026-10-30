#include "Station/Patient/StationPatientBodyAnim.h"

#include "Animation/AnimSequence.h"
#include "Animation/AnimationPoseData.h"
#include "BoneContainer.h"
#include "BonePose.h"

namespace
{
	/** The joints that turn the head, from the shoulders up, and the share of the turn each takes. */
	const FName NeckJoints[] = { TEXT("neck_01"), TEXT("neck_02"), TEXT("head") };
	constexpr float NeckShares[] = { 0.25f, 0.3f, 0.45f };
}

FAnimInstanceProxy* UStationPatientBodyAnim::CreateAnimInstanceProxy()
{
	return new FStationPatientBodyProxy(this);
}

void UStationPatientBodyAnim::DestroyAnimInstanceProxy(FAnimInstanceProxy* InProxy)
{
	delete static_cast<FStationPatientBodyProxy*>(InProxy);
}

void FStationPatientBodyProxy::PreUpdate(UAnimInstance* InAnimInstance, float DeltaSeconds)
{
	FAnimInstanceProxy::PreUpdate(InAnimInstance, DeltaSeconds);

	UStationPatientBodyAnim* Body = CastChecked<UStationPatientBodyAnim>(InAnimInstance);
	Idle = Body->Idle;
	if (Idle && Idle->GetPlayLength() > 0.f)
	{
		IdleTime = FMath::Fmod(IdleTime + DeltaSeconds, double(Idle->GetPlayLength()));
	}
	HeadTurn = Body->HeadTurn;
	Weight = Body->Weight;
	HeadForward = Body->HeadForward;
	HeadLeft = Body->HeadLeft;
	HeadUp = Body->HeadUp;
}

bool FStationPatientBodyProxy::Evaluate(FPoseContext& Output)
{
	if (Idle)
	{
		FAnimationPoseData PoseData(Output);
		Idle->GetAnimationPose(PoseData, FAnimExtractContext(IdleTime, false, {}, true));
	}
	else
	{
		Output.ResetToRefPose();
	}

	if (Weight <= 0.f)
	{
		return true;
	}
	const FBoneContainer& Bones = Output.Pose.GetBoneContainer();
	FCompactPoseBoneIndex Joints[UE_ARRAY_COUNT(NeckJoints)] = { FCompactPoseBoneIndex(INDEX_NONE),
		FCompactPoseBoneIndex(INDEX_NONE), FCompactPoseBoneIndex(INDEX_NONE) };
	for (int32 Index = 0; Index < UE_ARRAY_COUNT(NeckJoints); ++Index)
	{
		FBoneReference Joint(NeckJoints[Index]);
		if (!Joint.Initialize(Bones) || !Joint.IsValidToEvaluate(Bones))
		{
			// A LOD without the neck keeps the idle loop.
			return true;
		}
		Joints[Index] = Joint.GetCompactPoseIndex(Bones);
	}

	// The whole turn, in component space, from where the idle loop has the face point.
	FCSPose<FCompactPose> Component;
	Component.InitPose(Output.Pose);
	const FQuat HeadRotation = Component.GetComponentSpaceTransform(Joints[2]).GetRotation();
	const FVector Forward = HeadRotation.RotateVector(HeadForward);
	const FVector Wanted = StationGaze::Direction(Forward, HeadRotation.RotateVector(HeadLeft),
		HeadRotation.RotateVector(HeadUp), { HeadTurn.Yaw * Weight, HeadTurn.Pitch * Weight });
	const FQuat Turn = FQuat::FindBetweenNormals(Forward.GetSafeNormal(), Wanted.GetSafeNormal());

	// Each joint turns its share about itself; the joints below it have already turned it that far.
	FQuat Turned = FQuat::Identity;
	for (int32 Index = 0; Index < UE_ARRAY_COUNT(NeckJoints); ++Index)
	{
		const FCompactPoseBoneIndex Parent = Bones.GetParentBoneIndex(Joints[Index]);
		if (Parent == INDEX_NONE)
		{
			return true;
		}
		const FQuat ParentRotation = Turned * Component.GetComponentSpaceTransform(Parent).GetRotation();
		const FQuat Share = FQuat::Slerp(FQuat::Identity, Turn, NeckShares[Index]);
		FTransform& Local = Output.Pose[Joints[Index]];
		Local.SetRotation(StationGaze::TurnLocal(ParentRotation, Local.GetRotation(), Share).GetNormalized());
		Turned = Share * Turned;
	}
	return true;
}
