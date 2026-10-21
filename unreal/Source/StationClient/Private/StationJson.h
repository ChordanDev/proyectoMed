// Phoenix JSON bodies to station client value types. Each parser returns false
// when a field the contract requires is missing or malformed.

#pragma once

#include "CoreMinimal.h"
#include "StationClientTypes.h"

class FJsonObject;

namespace StationJson
{
	/** `GET /api/stations/active`. */
	bool ParseSummary(const FJsonObject& Json, FStationSummary& Out);

	/** Create and show session bodies; `OutServerNow` is the response's `server_now`. */
	bool ParseSession(const FJsonObject& Json, FStationSession& Out, FDateTime& OutServerNow);

	/** An ISO 8601 UTC timestamp field. */
	bool ParseDate(const FJsonObject& Json, const TCHAR* Field, FDateTime& Out);
}
