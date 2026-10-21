#include "StationClient.h"

#include "Dom/JsonObject.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "StationHttp.h"
#include "StationJson.h"

namespace
{
	const TCHAR* ActiveStationPath = TEXT("/api/stations/active");
	const TCHAR* SessionsPath = TEXT("/api/stations/active/sessions");

	FStationClientError NoSessionError()
	{
		return StationHttp::ClientError(TEXT("no_session"), TEXT("No station run is in progress."));
	}

	FStationClientError InvalidResponseError(int32 Status)
	{
		return FStationClientError{Status, TEXT("invalid_response"),
			TEXT("Phoenix answered with a body the station client does not understand.")};
	}
}

void UStationClient::PostInitProperties()
{
	Super::PostInitProperties();

	FString FromCommandLine;
	if (FParse::Value(FCommandLine::Get(), TEXT("PhoenixUrl="), FromCommandLine))
	{
		SetPhoenixBaseUrl(FromCommandLine);
	}
}

void UStationClient::SetPhoenixBaseUrl(const FString& InBaseUrl)
{
	PhoenixBaseUrl = InBaseUrl;
	PhoenixBaseUrl.RemoveFromEnd(TEXT("/"));
}

void UStationClient::FetchActiveStation(TStationCallback<FStationSummary> OnDone)
{
	StationHttp::Send(TEXT("GET"), PhoenixBaseUrl + ActiveStationPath, nullptr,
		[OnDone = MoveTemp(OnDone)](const FStationHttpResponse& Response)
		{
			if (Response.Error.IsSet())
			{
				OnDone(MakeError(Response.Error.GetValue()));
				return;
			}
			FStationSummary Summary;
			if (!Response.Json.IsValid() || !StationJson::ParseSummary(*Response.Json, Summary))
			{
				OnDone(MakeError(InvalidResponseError(Response.Status)));
				return;
			}
			OnDone(MakeValue(MoveTemp(Summary)));
		});
}

void UStationClient::StartSession(bool bAudioConsent, TStationCallback<FStationSession> OnDone)
{
	if (Session.IsSet() || bStartInFlight)
	{
		OnDone(MakeError(StationHttp::ClientError(TEXT("session_in_progress"),
			TEXT("Discard the current station run before starting another."))));
		return;
	}

	const TSharedRef<FJsonObject> Body = MakeShared<FJsonObject>();
	Body->SetBoolField(TEXT("audio_consent"), bAudioConsent);

	bStartInFlight = true;
	StationHttp::Send(TEXT("POST"), PhoenixBaseUrl + SessionsPath, Body,
		[WeakThis = TWeakObjectPtr<UStationClient>(this), OnDone = MoveTemp(OnDone)](const FStationHttpResponse& Response)
		{
			UStationClient* Self = WeakThis.Get();
			if (Self)
			{
				Self->bStartInFlight = false;
			}
			if (Response.Error.IsSet())
			{
				OnDone(MakeError(Response.Error.GetValue()));
				return;
			}
			FStationSession NewSession;
			FDateTime ServerNow;
			if (!Response.Json.IsValid() || !StationJson::ParseSession(*Response.Json, NewSession, ServerNow))
			{
				OnDone(MakeError(InvalidResponseError(Response.Status)));
				return;
			}
			if (Self)
			{
				Self->AcceptSession(NewSession, ServerNow);
			}
			OnDone(MakeValue(MoveTemp(NewSession)));
		});
}

void UStationClient::RefreshSession(TStationCallback<FStationSession> OnDone)
{
	if (!Session.IsSet())
	{
		OnDone(MakeError(NoSessionError()));
		return;
	}

	const FString SessionId = Session->SessionId;
	StationHttp::Send(TEXT("GET"), PhoenixBaseUrl + SessionsPath + TEXT("/") + SessionId, nullptr,
		[WeakThis = TWeakObjectPtr<UStationClient>(this), SessionId, OnDone = MoveTemp(OnDone)](const FStationHttpResponse& Response)
		{
			if (Response.Error.IsSet())
			{
				OnDone(MakeError(Response.Error.GetValue()));
				return;
			}
			FStationSession Refreshed;
			FDateTime ServerNow;
			if (!Response.Json.IsValid() || !StationJson::ParseSession(*Response.Json, Refreshed, ServerNow))
			{
				OnDone(MakeError(InvalidResponseError(Response.Status)));
				return;
			}
			// A discard or a new run may have replaced the session while the request was in flight.
			UStationClient* Self = WeakThis.Get();
			if (Self && Self->Session.IsSet() && Self->Session->SessionId == SessionId)
			{
				Self->AcceptSession(Refreshed, ServerNow);
			}
			OnDone(MakeValue(MoveTemp(Refreshed)));
		});
}

void UStationClient::DiscardSession(TStationCallback<FStationNone> OnDone)
{
	if (!Session.IsSet())
	{
		OnDone(MakeError(NoSessionError()));
		return;
	}

	const FString SessionId = Session->SessionId;
	StationHttp::Send(TEXT("POST"), PhoenixBaseUrl + SessionsPath + TEXT("/") + SessionId + TEXT("/discard"), nullptr,
		[WeakThis = TWeakObjectPtr<UStationClient>(this), SessionId, OnDone = MoveTemp(OnDone)](const FStationHttpResponse& Response)
		{
			if (Response.Error.IsSet())
			{
				OnDone(MakeError(Response.Error.GetValue()));
				return;
			}
			UStationClient* Self = WeakThis.Get();
			if (Self && Self->Session.IsSet() && Self->Session->SessionId == SessionId)
			{
				Self->Session.Reset();
				Self->Clock = FStationClock();
			}
			OnDone(MakeValue(FStationNone()));
		});
}

FTimespan UStationClient::GetRemainingTime() const
{
	return GetRemainingTimeAt(FPlatformTime::Seconds());
}

FTimespan UStationClient::GetRemainingTimeAt(double LocalSeconds) const
{
	if (!Session.IsSet() || !Clock.IsAnchored())
	{
		return FTimespan::Zero();
	}
	return Clock.RemainingAt(Session->DeadlineAt, LocalSeconds);
}

void UStationClient::AcceptSession(const FStationSession& InSession, const FDateTime& ServerNow)
{
	Session = InSession;
	Clock = FStationClock::Anchor(ServerNow, FPlatformTime::Seconds());
}
