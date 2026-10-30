#include "Station/Patient/StationPatientGaze.h"

#include "Animation/AnimSequence.h"
#include "AnimationRuntime.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "EngineUtils.h"
#include "Station/Patient/StationPatientBodyAnim.h"
#include "Station/StationPlayerController.h"
#include "Station/StationRunFlow.h"
#include "Station/Voice/StationPatientFaceAnim.h"

namespace
{
	const FName HeadJoint(TEXT("head"));
	const FName LeftEyeJoint(TEXT("FACIAL_L_Eye"));
	const FName RightEyeJoint(TEXT("FACIAL_R_Eye"));
}

UStationPatientGaze::UStationPatientGaze()
	: Model(int32(FPlatformTime::Cycles()))
{
	PrimaryComponentTick.bCanEverTick = true;
	PrimaryComponentTick.bStartWithTickEnabled = false;
}

AActor* UStationPatientGaze::FindLookTarget(UWorld* World)
{
	if (!World)
	{
		return nullptr;
	}
	for (TActorIterator<ACameraActor> It(World); It; ++It)
	{
		if (It->ActorHasTag(AStationPlayerController::StationViewTag))
		{
			return *It;
		}
	}
	return nullptr;
}

EStationGazeMode UStationPatientGaze::ModeFor(EStationRunStep Step, bool bSpokenRun, bool bLearnerTalking, bool bPatientAnswering)
{
	if (Step != EStationRunStep::Running || !bSpokenRun)
	{
		return EStationGazeMode::Off;
	}
	if (bLearnerTalking)
	{
		return EStationGazeMode::Listening;
	}
	return bPatientAnswering ? EStationGazeMode::Answering : EStationGazeMode::Resting;
}

void UStationPatientGaze::Start(USkeletalMeshComponent* Body, USkeletalMeshComponent* Face, TFunction<EStationGazeMode()> Mode)
{
	LookTarget = FindLookTarget(GetWorld());
	if (!Body || !Body->GetSkeletalMeshAsset() || !LookTarget.IsValid())
	{
		return;
	}
	const FReferenceSkeleton& Skeleton = Body->GetSkeletalMeshAsset()->GetRefSkeleton();
	const int32 Head = Skeleton.FindBoneIndex(HeadJoint);
	if (Head == INDEX_NONE)
	{
		return;
	}
	// A MetaHuman body faces +Y with its left on +X in the reference pose.
	const FQuat HeadRotation = FAnimationRuntime::GetComponentSpaceTransformRefPose(Skeleton, Head).GetRotation();
	HeadForward = HeadRotation.UnrotateVector(FVector::YAxisVector);
	HeadLeft = HeadRotation.UnrotateVector(FVector::XAxisVector);
	HeadUp = HeadRotation.UnrotateVector(FVector::ZAxisVector);

	BodyMesh = Body;
	FaceMesh = Face;
	BodyIdle = Cast<UAnimSequence>(Body->AnimationData.AnimToPlay);
	ModeSource = MoveTemp(Mode);

	Body->SetAnimationMode(EAnimationMode::AnimationBlueprint);
	Body->SetAnimInstanceClass(UStationPatientBodyAnim::StaticClass());
	if (UStationPatientBodyAnim* BodyAnim = Cast<UStationPatientBodyAnim>(Body->GetAnimInstance()))
	{
		BodyAnim->Setup(BodyIdle, HeadForward, HeadLeft, HeadUp);
	}
	SetComponentTickEnabled(true);
}

void UStationPatientGaze::TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction)
{
	Super::TickComponent(DeltaTime, TickType, ThisTickFunction);
	UStationPatientBodyAnim* BodyAnim = BodyMesh ? Cast<UStationPatientBodyAnim>(BodyMesh->GetAnimInstance()) : nullptr;
	const AActor* Target = LookTarget.Get();
	if (!BodyAnim || !Target)
	{
		return;
	}

	// Where the learner is, from the head as it is now, turned by the gaze already.
	const UCameraComponent* Camera = Target->FindComponentByClass<UCameraComponent>();
	const FVector View = Camera ? Camera->GetComponentLocation() : Target->GetActorLocation();
	const FTransform HeadNow = BodyMesh->GetSocketTransform(HeadJoint);
	const FVector Toward = HeadNow.InverseTransformVectorNoScale(View - EyeCenter());
	const FStationGazeAngles Seen = StationGaze::AnglesOf(HeadForward, HeadLeft, HeadUp, Toward);
	const float Applied = Model.GetWeight();
	const FStationGazeAngles ToLearner{ Seen.Yaw + Model.GetHead().Yaw * Applied, Seen.Pitch + Model.GetHead().Pitch * Applied };

	Model.Tick(DeltaTime, ModeSource ? ModeSource() : EStationGazeMode::Off, ToLearner);
	BodyAnim->SetHeadTurn(Model.GetHead(), Model.GetWeight());
	// The face plays `UStationPatientFaceAnim` only in a voice run (#191); otherwise its idle loop keeps the eyes.
	if (UStationPatientFaceAnim* FaceAnim = FaceMesh ? Cast<UStationPatientFaceAnim>(FaceMesh->GetAnimInstance()) : nullptr)
	{
		FaceAnim->SetEyeGaze(Model.GetEyes(), Model.GetWeight());
	}
}

void UStationPatientGaze::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (BodyMesh && BodyIdle)
	{
		// Back to the idle loop the scene starts with.
		BodyMesh->SetAnimationMode(EAnimationMode::AnimationSingleNode);
		BodyMesh->PlayAnimation(BodyIdle, true);
	}
	BodyMesh = nullptr;
	FaceMesh = nullptr;
	BodyIdle = nullptr;
	Super::EndPlay(EndPlayReason);
}

FVector UStationPatientGaze::EyeCenter() const
{
	if (FaceMesh && FaceMesh->GetBoneIndex(LeftEyeJoint) != INDEX_NONE && FaceMesh->GetBoneIndex(RightEyeJoint) != INDEX_NONE)
	{
		return (FaceMesh->GetSocketLocation(LeftEyeJoint) + FaceMesh->GetSocketLocation(RightEyeJoint)) * 0.5f;
	}
	return BodyMesh->GetSocketLocation(HeadJoint);
}
