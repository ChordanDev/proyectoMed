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

	/** `POST .../voice`. */
	bool ParseVoiceCredential(const FJsonObject& Json, FStationVoiceCredential& Out);

	/** `POST .../messages`. A body without `outcome` is a patient reply (older Phoenix). */
	bool ParseTurnReply(const FJsonObject& Json, FStationTurnReply& Out);

	/** `POST .../impressos/request`. */
	bool ParseImpressoReply(const FJsonObject& Json, FStationImpressoReply& Out);

	/** `GET .../impressos`. */
	bool ParseImpressoList(const FJsonObject& Json, TArray<FStationImpresso>& Out);

	/** `released`, `already_released` or `unavailable`. */
	bool ParseImpressoDecision(const FString& Text, EStationImpressoDecision& Out);

	/** `POST .../exam-mode`: only an armed mode. */
	bool ParseExamMode(const FJsonObject& Json, FStationExamMode& Out);

	/** `POST .../finish`: updates the status, reason and completion time of `InOut`. */
	bool ParseFinish(const FJsonObject& Json, FStationSession& InOut);

	/** `GET /api/v2/.../result`. */
	bool ParseResult(const FJsonObject& Json, FStationResult& Out);

	/** An ISO 8601 UTC timestamp field. */
	bool ParseDate(const FJsonObject& Json, const TCHAR* Field, FDateTime& Out);
}
