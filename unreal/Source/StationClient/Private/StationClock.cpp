#include "StationClock.h"

FStationClock FStationClock::Anchor(const FDateTime& ServerNow, double LocalSeconds)
{
	FStationClock Clock;
	Clock.AnchorServerTime = ServerNow;
	Clock.AnchorLocalSeconds = LocalSeconds;
	Clock.bAnchored = true;
	return Clock;
}

FDateTime FStationClock::ServerTimeAt(double LocalSeconds) const
{
	return AnchorServerTime + FTimespan::FromSeconds(LocalSeconds - AnchorLocalSeconds);
}

FTimespan FStationClock::RemainingAt(const FDateTime& Deadline, double LocalSeconds) const
{
	const FTimespan Remaining = SignedRemainingAt(Deadline, LocalSeconds);
	return Remaining > FTimespan::Zero() ? Remaining : FTimespan::Zero();
}

FTimespan FStationClock::SignedRemainingAt(const FDateTime& Deadline, double LocalSeconds) const
{
	return Deadline - ServerTimeAt(LocalSeconds);
}
