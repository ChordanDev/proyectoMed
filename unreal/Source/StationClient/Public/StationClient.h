// The station client: the one object in the Unreal client that talks to
// Phoenix. It holds the current ephemeral session and the clock that anchors the
// Station Timer to Phoenix. Its contract is documented in
// docs/unreal-station-client.md; change it only with both Unreal tracks' agreement.

#pragma once

#include "CoreMinimal.h"
#include "StationClientTypes.h"
#include "StationClock.h"
#include "UObject/Object.h"

#include "StationClient.generated.h"

UCLASS(Config = Game)
class STATIONCLIENT_API UStationClient : public UObject
{
	GENERATED_BODY()

public:
	virtual void PostInitProperties() override;

	/** Points the client at another Phoenix, for example a test server. */
	void SetPhoenixBaseUrl(const FString& InBaseUrl);
	const FString& GetPhoenixBaseUrl() const { return PhoenixBaseUrl; }

	/** `GET /api/stations/active`: the station a run would start, before any session exists. */
	void FetchActiveStation(TStationCallback<FStationSummary> OnDone);

	/**
	 * `POST /api/stations/active/sessions`: starts a run, and with it the Station
	 * Timer. Fails with `session_in_progress` while this client holds a session
	 * or is already starting one.
	 */
	void StartSession(bool bAudioConsent, TStationCallback<FStationSession> OnDone);

	/** `GET .../sessions/:id`: reloads the current session and re-anchors the timer. */
	void RefreshSession(TStationCallback<FStationSession> OnDone);

	/**
	 * `POST .../sessions/:id/discard`: asks Phoenix to forget the run. The local
	 * session is cleared only once Phoenix confirms, so a new run cannot start first.
	 */
	void DiscardSession(TStationCallback<FStationNone> OnDone);

	/** The current session, or null before a run starts and after it is discarded. */
	const FStationSession* GetSession() const { return Session.GetPtrOrNull(); }

	/** Station Timer: time left until the session deadline, by Phoenix's clock. Zero without a session. */
	FTimespan GetRemainingTime() const;
	FTimespan GetRemainingTimeAt(double LocalSeconds) const;

private:
	void AcceptSession(const FStationSession& InSession, const FDateTime& ServerNow);

	/** Phoenix origin, without a trailing slash. `-PhoenixUrl=` on the command line overrides it. */
	UPROPERTY(Config)
	FString PhoenixBaseUrl = TEXT("http://127.0.0.1:4000");

	TOptional<FStationSession> Session;
	FStationClock Clock;
	bool bStartInFlight = false;
};
