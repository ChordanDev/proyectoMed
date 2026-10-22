#include "Station/Voice/StationFaceBlend.h"

namespace
{
	constexpr float AttackSeconds = 0.08f;
	constexpr float ReleaseSeconds = 0.3f;
}

bool StationFaceBlend::IsMouthControl(FName RawControl)
{
	// Raw controls read like CTRL_expressions_jawOpen or CTRL_expressions_mouthCornerPullL.
	const FString Name = RawControl.ToString();
	for (const TCHAR* Part : { TEXT("jaw"), TEXT("mouth"), TEXT("lip"), TEXT("tongue"), TEXT("teeth") })
	{
		if (Name.Contains(Part, ESearchCase::IgnoreCase))
		{
			return true;
		}
	}
	return false;
}

float StationFaceBlend::StepSpeechWeight(float Weight, bool bSpeaking, float DeltaSeconds)
{
	const float Target = bSpeaking ? 1.f : 0.f;
	const float Seconds = bSpeaking ? AttackSeconds : ReleaseSeconds;
	const float Alpha = 1.f - FMath::Exp(-FMath::Max(DeltaSeconds, 0.f) / Seconds);
	return FMath::Clamp(Weight + (Target - Weight) * Alpha, 0.f, 1.f);
}
