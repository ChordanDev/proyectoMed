#include "Station/Voice/StationPatientFaceAnim.h"

#include "Animation/AnimSequence.h"
#include "Animation/AnimationPoseData.h"
#include "Station/Voice/StationFaceBlend.h"

void FStationMouthState::PushControls(TMap<FName, float>&& RawControls)
{
	TMap<FName, float> Mouth;
	for (const TPair<FName, float>& Control : RawControls)
	{
		if (StationFaceBlend::IsMouthControl(Control.Key))
		{
			Mouth.Add(Control.Key, Control.Value);
		}
	}
	FScopeLock Guard(&Lock);
	if (!bResting)
	{
		Controls = MoveTemp(Mouth);
	}
}

void FStationMouthState::NoteSpeech()
{
	FScopeLock Guard(&Lock);
	LastSpeechSeconds = FPlatformTime::Seconds();
	bResting = false;
}

void FStationMouthState::Rest()
{
	FScopeLock Guard(&Lock);
	Controls.Reset();
	LastSpeechSeconds = -1.0;
	bResting = true;
}

bool FStationMouthState::Read(TMap<FName, float>& OutControls) const
{
	FScopeLock Guard(&Lock);
	OutControls = Controls;
	return LastSpeechSeconds >= 0.0 && FPlatformTime::Seconds() - LastSpeechSeconds < StationFaceBlend::SpeechHoldSeconds;
}

FAnimInstanceProxy* UStationPatientFaceAnim::CreateAnimInstanceProxy()
{
	return new FStationPatientFaceProxy(this);
}

void UStationPatientFaceAnim::DestroyAnimInstanceProxy(FAnimInstanceProxy* InProxy)
{
	delete static_cast<FStationPatientFaceProxy*>(InProxy);
}

void FStationPatientFaceProxy::PreUpdate(UAnimInstance* InAnimInstance, float DeltaSeconds)
{
	FAnimInstanceProxy::PreUpdate(InAnimInstance, DeltaSeconds);

	UStationPatientFaceAnim* Face = CastChecked<UStationPatientFaceAnim>(InAnimInstance);
	Idle = Face->Idle;
	if (Idle && Idle->GetPlayLength() > 0.f)
	{
		IdleTime = FMath::Fmod(IdleTime + DeltaSeconds, double(Idle->GetPlayLength()));
	}

	const bool bSpeaking = Face->Mouth && Face->Mouth->Read(MouthControls);
	SpeechWeight = StationFaceBlend::StepSpeechWeight(SpeechWeight, bSpeaking, DeltaSeconds);

	EyeGazeWeight = Face->EyeGazeWeight;
	StationGaze::EyeControls(Face->EyeGaze, EyeControls);
}

bool FStationPatientFaceProxy::Evaluate(FPoseContext& Output)
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

	if (EyeGazeWeight > 0.f)
	{
		for (const TPair<FName, float>& Control : EyeControls)
		{
			const float IdleValue = Output.Curve.Get(Control.Key);
			Output.Curve.Set(Control.Key, FMath::Lerp(IdleValue, Control.Value, EyeGazeWeight));
		}
	}

	if (SpeechWeight > 0.f)
	{
		for (const TPair<FName, float>& Control : MouthControls)
		{
			const float IdleValue = Output.Curve.Get(Control.Key);
			Output.Curve.Set(Control.Key, FMath::Lerp(IdleValue, Control.Value, SpeechWeight));
		}
	}
	return true;
}
