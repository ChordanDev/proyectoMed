// JSON over HTTP to Phoenix, with Phoenix's `{error, message}` bodies mapped to
// FStationClientError. Private to the station client module.

#pragma once

#include "CoreMinimal.h"
#include "StationClientTypes.h"

class FJsonObject;

struct FStationHttpResponse
{
	/** HTTP status, or 0 when Phoenix was not reached. */
	int32 Status = 0;

	/** The parsed body of a successful response; null for an empty body (204). */
	TSharedPtr<FJsonObject> Json;

	/** Set when the call failed: transport error, non-2xx status, or a body that is not JSON. */
	TOptional<FStationClientError> Error;
};

namespace StationHttp
{
	/** Seconds before an unanswered request fails with `network_error`. */
	constexpr float RequestTimeoutSeconds = 15.f;

	/**
	 * The educational result's first fetch assesses the run before answering;
	 * Phoenix budgets 80 s for it and the web client waits 95 s
	 * (backend/config/runtime.exs, `EDUCATIONAL_RESULT_TIMEOUT_MS`).
	 */
	constexpr float ResultTimeoutSeconds = 95.f;

	/** Sends one request; `OnDone` runs on the game thread. `Body` may be null. */
	void Send(const FString& Verb, const FString& Url, const TSharedPtr<FJsonObject>& Body,
		TFunction<void(const FStationHttpResponse&)> OnDone, float TimeoutSeconds = RequestTimeoutSeconds);

	/** An error the client raises itself, with no Phoenix answer involved. */
	FStationClientError ClientError(const FString& Code, const FString& Message);
}
