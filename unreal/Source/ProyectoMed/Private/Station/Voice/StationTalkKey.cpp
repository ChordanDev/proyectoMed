#include "Station/StationTalkKey.h"

bool FStationTalkKey::Press(double Now, bool bPatientAnswering, EStationTalkInput Input)
{
	if (bDown)
	{
		return false; // the key repeats while held, or another input holds it
	}
	bDown = true;
	DownInput = Input;
	bOpened = !bPatientAnswering || Now - TapReleasedAt <= DoubleTapSeconds;
	if (bOpened)
	{
		TapReleasedAt = -1.0e9;
	}
	return bOpened;
}

void FStationTalkKey::Release(double Now, EStationTalkInput Input)
{
	if (!bDown || Input != DownInput)
	{
		return;
	}
	bDown = false;
	if (bOpened)
	{
		OpenReleasedAt = Now;
		bOpened = false;
	}
	else
	{
		TapReleasedAt = Now;
	}
}

bool FStationTalkKey::IsOpen(double Now) const
{
	return IsHeld() || Now - OpenReleasedAt < TailSeconds;
}
