#include "Station/Patient/StationGaze.h"

namespace
{
	// How quickly the eyes, the head and the gaze's hold over the idle loops settle.
	constexpr float EyeSeconds = 0.06f;
	constexpr float HeadSeconds = 0.3f;
	constexpr float WeightSeconds = 0.25f;

	// The head takes this share of a turn; the eyes do the rest.
	constexpr float HeadShare = 0.5f;

	// How far one eye-look control at 1 turns the MetaHuman's eyes.
	constexpr float EyeControlYaw = 40.f;
	constexpr float EyeControlUp = 30.f;
	constexpr float EyeControlDown = 40.f;

	const FName EyeLookLeft[] = { TEXT("CTRL_expressions_eyeLookLeftL"), TEXT("CTRL_expressions_eyeLookLeftR") };
	const FName EyeLookRight[] = { TEXT("CTRL_expressions_eyeLookRightL"), TEXT("CTRL_expressions_eyeLookRightR") };
	const FName EyeLookUp[] = { TEXT("CTRL_expressions_eyeLookUpL"), TEXT("CTRL_expressions_eyeLookUpR") };
	const FName EyeLookDown[] = { TEXT("CTRL_expressions_eyeLookDownL"), TEXT("CTRL_expressions_eyeLookDownR") };

	FStationGazeAngles Clamp(const FStationGazeAngles& Angles, float MaxYaw, float MaxUp, float MaxDown)
	{
		return { FMath::Clamp(Angles.Yaw, -MaxYaw, MaxYaw), FMath::Clamp(Angles.Pitch, -MaxDown, MaxUp) };
	}

	/** Eases `Current` toward `Target`, never faster than `MaxSpeed` degrees per second. */
	FStationGazeAngles Ease(const FStationGazeAngles& Current, const FStationGazeAngles& Target,
		float TimeConstant, float MaxSpeed, float DeltaSeconds)
	{
		const float Alpha = 1.f - FMath::Exp(-DeltaSeconds / TimeConstant);
		FVector2D Step(Target.Yaw - Current.Yaw, Target.Pitch - Current.Pitch);
		Step *= Alpha;
		const float MaxStep = MaxSpeed * DeltaSeconds;
		if (Step.Size() > MaxStep)
		{
			Step = Step.GetSafeNormal() * MaxStep;
		}
		return { Current.Yaw + float(Step.X), Current.Pitch + float(Step.Y) };
	}

	float Draw(FRandomStream& Random, StationGaze::FSeconds Range)
	{
		return Random.FRandRange(Range.Min, Range.Max);
	}
}

StationGaze::FSeconds StationGaze::ContactSeconds(EStationGazeMode Mode)
{
	// People hold a speaker's eyes longer than a listener's; at rest, a look is brief.
	switch (Mode)
	{
	case EStationGazeMode::Listening:
		return { 3.f, 8.f };
	case EStationGazeMode::Answering:
		return { 2.f, 5.f };
	case EStationGazeMode::Resting:
		return { 0.8f, 2.f };
	default:
		return { 1.f, 1.f };
	}
}

StationGaze::FSeconds StationGaze::AwaySeconds(EStationGazeMode Mode)
{
	switch (Mode)
	{
	case EStationGazeMode::Listening:
		return { 0.4f, 1.2f };
	case EStationGazeMode::Answering:
		return { 0.7f, 1.8f };
	case EStationGazeMode::Resting:
		return { 4.f, 10.f };
	default:
		return { 1.f, 1.f };
	}
}

FVector StationGaze::Direction(const FVector& Forward, const FVector& Left, const FVector& Up, const FStationGazeAngles& Angles)
{
	const float Yaw = FMath::DegreesToRadians(Angles.Yaw);
	const float Pitch = FMath::DegreesToRadians(Angles.Pitch);
	return Forward * FMath::Cos(Pitch) * FMath::Cos(Yaw) + Left * FMath::Cos(Pitch) * FMath::Sin(Yaw) + Up * FMath::Sin(Pitch);
}

FStationGazeAngles StationGaze::AnglesOf(const FVector& Forward, const FVector& Left, const FVector& Up, const FVector& Direction)
{
	const FVector Unit = Direction.GetSafeNormal();
	const float Ahead = FVector::DotProduct(Unit, Forward);
	const float Side = FVector::DotProduct(Unit, Left);
	const float Above = FVector::DotProduct(Unit, Up);
	return { FMath::RadiansToDegrees(FMath::Atan2(Side, Ahead)),
		FMath::RadiansToDegrees(FMath::Atan2(Above, FMath::Sqrt(Ahead * Ahead + Side * Side))) };
}

void StationGaze::EyeControls(const FStationGazeAngles& Eyes, TMap<FName, float>& OutControls)
{
	const float Left = FMath::Clamp(Eyes.Yaw / EyeControlYaw, 0.f, 1.f);
	const float Right = FMath::Clamp(-Eyes.Yaw / EyeControlYaw, 0.f, 1.f);
	const float Up = FMath::Clamp(Eyes.Pitch / EyeControlUp, 0.f, 1.f);
	const float Down = FMath::Clamp(-Eyes.Pitch / EyeControlDown, 0.f, 1.f);
	OutControls.Reset();
	for (int32 Eye = 0; Eye < 2; ++Eye)
	{
		OutControls.Add(EyeLookLeft[Eye], Left);
		OutControls.Add(EyeLookRight[Eye], Right);
		OutControls.Add(EyeLookUp[Eye], Up);
		OutControls.Add(EyeLookDown[Eye], Down);
	}
}

bool StationGaze::IsEyeLookControl(FName RawControl)
{
	for (int32 Eye = 0; Eye < 2; ++Eye)
	{
		if (RawControl == EyeLookLeft[Eye] || RawControl == EyeLookRight[Eye] || RawControl == EyeLookUp[Eye] || RawControl == EyeLookDown[Eye])
		{
			return true;
		}
	}
	return false;
}

FQuat StationGaze::TurnLocal(const FQuat& ParentComponent, const FQuat& Local, const FQuat& Turn)
{
	return ParentComponent.Inverse() * Turn * ParentComponent * Local;
}

FStationGazeModel::FStationGazeModel(int32 Seed)
	: Random(Seed)
{
}

void FStationGazeModel::Tick(float DeltaSeconds, EStationGazeMode InMode, const FStationGazeAngles& ToLearner)
{
	const float Delta = FMath::Max(DeltaSeconds, 0.f);
	const bool bWasExchange = Mode == EStationGazeMode::Listening || Mode == EStationGazeMode::Answering;
	const bool bExchange = InMode == EStationGazeMode::Listening || InMode == EStationGazeMode::Answering;
	if (InMode != Mode)
	{
		Mode = InMode;
		if (bExchange && !bWasExchange)
		{
			// Someone started to speak: look at the learner at once.
			PhaseLeft = 0.f;
			BeginPhase(EStationGazePhase::Contact);
		}
		else if (!bExchange && Phase != EStationGazePhase::Rest)
		{
			PhaseLeft = 0.f;
			BeginPhase(EStationGazePhase::Rest);
		}
	}

	PhaseLeft -= Delta;
	while (PhaseLeft <= 0.f && Mode != EStationGazeMode::Off)
	{
		if (bExchange)
		{
			BeginPhase(Phase == EStationGazePhase::Contact ? EStationGazePhase::Away : EStationGazePhase::Contact);
		}
		else
		{
			BeginPhase(Phase == EStationGazePhase::Rest ? EStationGazePhase::Contact : EStationGazePhase::Rest);
		}
	}

	if (Phase == EStationGazePhase::Contact)
	{
		Aim = ToLearner;
	}
	else if (Phase == EStationGazePhase::Away)
	{
		Aim = { ToLearner.Yaw + Glance.Yaw, ToLearner.Pitch + Glance.Pitch };
	}
	// At rest the head and eyes hold their last aim while the idle loops take over.

	const float TargetWeight = Phase == EStationGazePhase::Rest ? 0.f : 1.f;
	Weight = FMath::Clamp(Weight + (TargetWeight - Weight) * (1.f - FMath::Exp(-Delta / WeightSeconds)), 0.f, 1.f);

	const FStationGazeAngles HeadAim = Clamp({ Aim.Yaw * HeadShare, Aim.Pitch * HeadShare },
		StationGaze::HeadMaxYaw, StationGaze::HeadMaxUp, StationGaze::HeadMaxDown);
	Head = Ease(Head, HeadAim, HeadSeconds, StationGaze::HeadMaxSpeed, Delta);
	// The eyes lead and the head follows: they aim at what the head has not turned yet.
	const FStationGazeAngles EyeAim = Clamp({ Aim.Yaw - Head.Yaw, Aim.Pitch - Head.Pitch },
		StationGaze::EyeMaxYaw, StationGaze::EyeMaxUp, StationGaze::EyeMaxDown);
	Eyes = Ease(Eyes, EyeAim, EyeSeconds, StationGaze::EyeMaxSpeed, Delta);
}

void FStationGazeModel::BeginPhase(EStationGazePhase NewPhase)
{
	Phase = NewPhase;
	switch (Phase)
	{
	case EStationGazePhase::Contact:
		PhaseLeft += Draw(Random, StationGaze::ContactSeconds(Mode));
		break;
	case EStationGazePhase::Away:
	{
		PhaseLeft += Draw(Random, StationGaze::AwaySeconds(Mode));
		// Down, as if thinking; aside; or a short look at nothing nearby.
		const float Side = Random.FRand() < 0.5f ? -1.f : 1.f;
		const float Kind = Random.FRand();
		if (Kind < 0.5f)
		{
			Glance = { Side * Random.FRandRange(0.f, 10.f), -Random.FRandRange(8.f, 18.f) };
		}
		else if (Kind < 0.85f)
		{
			Glance = { Side * Random.FRandRange(12.f, 22.f), Random.FRandRange(-4.f, 2.f) };
		}
		else
		{
			Glance = { Side * Random.FRandRange(4.f, 10.f), -Random.FRandRange(2.f, 6.f) };
		}
		break;
	}
	case EStationGazePhase::Rest:
		PhaseLeft = Mode == EStationGazeMode::Resting ? PhaseLeft + Draw(Random, StationGaze::AwaySeconds(Mode)) : 0.f;
		break;
	}
	// Draws add to what the last frame overran, so phases keep their length; a
	// frame longer than a whole phase still leaves the next one a moment.
	PhaseLeft = FMath::Max(PhaseLeft, 0.05f);
}
