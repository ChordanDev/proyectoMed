// Maps the local monotonic clock onto Phoenix's clock, so the Station Timer
// counts down to the server-owned deadline whatever the machine clock says.

#pragma once

#include "CoreMinimal.h"

struct STATIONCLIENT_API FStationClock
{
	/** Pairs Phoenix's `server_now` with the local time (`FPlatformTime::Seconds`) the response arrived. */
	static FStationClock Anchor(const FDateTime& ServerNow, double LocalSeconds);

	/** Phoenix's time at a local monotonic instant. */
	FDateTime ServerTimeAt(double LocalSeconds) const;

	/** Time left until `Deadline` at a local monotonic instant, never negative. */
	FTimespan RemainingAt(const FDateTime& Deadline, double LocalSeconds) const;

	/** `RemainingAt`, negative by how far past `Deadline` the instant is. */
	FTimespan SignedRemainingAt(const FDateTime& Deadline, double LocalSeconds) const;

	bool IsAnchored() const { return bAnchored; }

private:
	FDateTime AnchorServerTime;
	double AnchorLocalSeconds = 0.0;
	bool bAnchored = false;
};
