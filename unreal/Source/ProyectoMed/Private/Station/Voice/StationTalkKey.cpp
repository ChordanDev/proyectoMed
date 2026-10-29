#include "Station/StationTalkKey.h"

bool FStationTalkKey::Press(double Now, bool bPatientAnswering)
{
	if (bDown)
	{
		return false; // the key repeats while held
	}
	bDown = true;
	bOpened = !bPatientAnswering || Now - TapReleasedAt <= DoubleTapSeconds;
	if (bOpened)
	{
		TapReleasedAt = -1.0e9;
	}
	return bOpened;
}

void FStationTalkKey::Release(double Now)
{
	if (!bDown)
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
