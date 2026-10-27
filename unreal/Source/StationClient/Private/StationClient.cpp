#include "StationClient.h"

#include "Dom/JsonObject.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/Guid.h"
#include "Misc/Parse.h"
#include "StationHttp.h"
#include "StationJson.h"

namespace
{
	const TCHAR* ActiveStationPath = TEXT("/api/stations/active");
	const TCHAR* SessionsPath = TEXT("/api/stations/active/sessions");
	const TCHAR* ResultSessionsPath = TEXT("/api/v2/stations/active/sessions");

	FStationClientError NoSessionError()
	{
		return StationHttp::ClientError(TEXT("no_session"), TEXT("No station run is in progress."));
	}

	FStationClientError SessionCompletedError()
	{
		return StationHttp::ClientError(TEXT("session_completed"), TEXT("The station run has ended."));
	}

	FStationClientError InvalidResponseError(int32 Status)
	{
		return FStationClientError{Status, TEXT("invalid_response"),
			TEXT("Phoenix answered with a body the station client does not understand.")};
	}
}

void UStationClient::BeginDestroy()
{
	DisconnectVoice();
	Super::BeginDestroy();
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
				Refreshed = Self->MergeRefreshed(Refreshed);
				Self->AcceptSession(Refreshed, ServerNow);
				if (Refreshed.Status == EStationSessionStatus::Completed)
				{
					Self->DisconnectVoice();
				}
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

	// The learner abandons the run here, whatever Phoenix answers.
	DisconnectVoice();
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

void UStationClient::ForgetSession()
{
	DisconnectVoice();
	Session.Reset();
	Clock = FStationClock();
}

TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> UStationClient::ConnectVoice(const FStationVoiceCredential& Credential,
	FStationVoiceHandlers Handlers)
{
	DisconnectVoice();
	if (!Session.IsSet() || Session->Status == EStationSessionStatus::Completed)
	{
		return nullptr;
	}
	Voice = MakeShared<FStationVoiceLink, ESPMode::ThreadSafe>(Credential, Session->SessionId, MoveTemp(Handlers));
	Voice->Connect();
	return Voice;
}

void UStationClient::DisconnectVoice()
{
	if (const TSharedPtr<FStationVoiceLink, ESPMode::ThreadSafe> Closing = MoveTemp(Voice))
	{
		Closing->Disconnect();
	}
}

void UStationClient::RequestVoiceCredential(TStationCallback<FStationVoiceCredential> OnDone)
{
	if (!Session.IsSet())
	{
		OnDone(MakeError(NoSessionError()));
		return;
	}
	SendSessionRequest<FStationVoiceCredential>(TEXT("POST"), SessionUrl(TEXT("/voice")), nullptr,
		&StationJson::ParseVoiceCredential, MoveTemp(OnDone));
}

void UStationClient::SendTurn(const FString& Text, EStationTurnModality Modality, TStationCallback<FStationTurnReply> OnDone)
{
	if (!Session.IsSet())
	{
		OnDone(MakeError(NoSessionError()));
		return;
	}
	if (Session->Status == EStationSessionStatus::Completed)
	{
		OnDone(MakeError(SessionCompletedError()));
		return;
	}

	const TSharedRef<FJsonObject> Body = MakeShared<FJsonObject>();
	Body->SetStringField(TEXT("role"), TEXT("learner"));
	Body->SetStringField(TEXT("modality"), Modality == EStationTurnModality::Voice ? TEXT("voice") : TEXT("text"));
	Body->SetStringField(TEXT("text"), Text);
	SendSessionRequest<FStationTurnReply>(TEXT("POST"), SessionUrl(TEXT("/messages")), Body,
		&StationJson::ParseTurnReply, MoveTemp(OnDone));
}

void UStationClient::RequestImpresso(const FString& Text, const FString& RequestId, TStationCallback<FStationImpressoReply> OnDone)
{
	if (!Session.IsSet())
	{
		OnDone(MakeError(NoSessionError()));
		return;
	}

	const TSharedRef<FJsonObject> Body = MakeShared<FJsonObject>();
	Body->SetStringField(TEXT("text"), Text);
	Body->SetStringField(TEXT("request_id"),
		RequestId.IsEmpty() ? FGuid::NewGuid().ToString(EGuidFormats::DigitsWithHyphensLower) : RequestId);
	SendSessionRequest<FStationImpressoReply>(TEXT("POST"), SessionUrl(TEXT("/impressos/request")), Body,
		&StationJson::ParseImpressoReply, MoveTemp(OnDone));
}

void UStationClient::ListImpressos(TStationCallback<TArray<FStationImpresso>> OnDone)
{
	if (!Session.IsSet())
	{
		OnDone(MakeError(NoSessionError()));
		return;
	}
	SendSessionRequest<TArray<FStationImpresso>>(TEXT("GET"), SessionUrl(TEXT("/impressos")), nullptr,
		&StationJson::ParseImpressoList, MoveTemp(OnDone));
}

void UStationClient::FinishSession(EStationFinishReason Reason, TStationCallback<FStationSession> OnDone)
{
	if (!Session.IsSet())
	{
		OnDone(MakeError(NoSessionError()));
		return;
	}

	const TSharedRef<FJsonObject> Body = MakeShared<FJsonObject>();
	Body->SetStringField(TEXT("reason"), Reason == EStationFinishReason::Timer ? TEXT("timer") : TEXT("user"));
	const FStationSession Current = Session.GetValue();
	StationHttp::Send(TEXT("POST"), SessionUrl(TEXT("/finish")), Body,
		[WeakThis = TWeakObjectPtr<UStationClient>(this), Current, OnDone = MoveTemp(OnDone)](const FStationHttpResponse& Response)
		{
			if (Response.Error.IsSet())
			{
				OnDone(MakeError(Response.Error.GetValue()));
				return;
			}
			FStationSession Finished = Current;
			if (!Response.Json.IsValid() || !StationJson::ParseFinish(*Response.Json, Finished))
			{
				OnDone(MakeError(InvalidResponseError(Response.Status)));
				return;
			}
			// Apply only the closing fields to the live session: a refresh that
			// landed meanwhile may hold a newer transcript than the snapshot.
			UStationClient* Self = WeakThis.Get();
			if (Self && Self->Session.IsSet() && Self->Session->SessionId == Current.SessionId)
			{
				StationJson::ParseFinish(*Response.Json, Self->Session.GetValue());
				Finished = Self->Session.GetValue();
				// The run is over; a refused finish (`deadline_not_reached`) keeps the voice.
				Self->DisconnectVoice();
			}
			OnDone(MakeValue(MoveTemp(Finished)));
		});
}

void UStationClient::FetchResult(TStationCallback<FStationResult> OnDone)
{
	if (!Session.IsSet())
	{
		OnDone(MakeError(NoSessionError()));
		return;
	}
	const FString Url = PhoenixBaseUrl + ResultSessionsPath + TEXT("/") + Session->SessionId + TEXT("/result");
	SendSessionRequest<FStationResult>(TEXT("GET"), Url, nullptr, &StationJson::ParseResult, MoveTemp(OnDone),
		StationHttp::ResultTimeoutSeconds);
}

FTimespan UStationClient::GetRemainingTime() const
{
	return GetRemainingTimeAt(FPlatformTime::Seconds());
}

FTimespan UStationClient::GetRemainingTimeAt(double LocalSeconds) const
{
	if (!Session.IsSet() || Session->Status == EStationSessionStatus::Completed || !Clock.IsAnchored())
	{
		return FTimespan::Zero();
	}
	return Clock.RemainingAt(Session->DeadlineAt, LocalSeconds);
}

FStationSession UStationClient::MergeRefreshed(const FStationSession& Refreshed) const
{
	FStationSession Merged = Refreshed;
	if (Session->Status == EStationSessionStatus::Completed)
	{
		// Phoenix never reopens a run, so an "active" answer is one read before the finish.
		Merged.Status = EStationSessionStatus::Completed;
		Merged.CompletedAt = Session->CompletedAt;
		if (Merged.CompletionReason.IsEmpty())
		{
			Merged.CompletionReason = Session->CompletionReason;
		}
	}
	return Merged;
}

void UStationClient::AcceptSession(const FStationSession& InSession, const FDateTime& ServerNow)
{
	Session = InSession;
	Clock = FStationClock::Anchor(ServerNow, FPlatformTime::Seconds());
}


FString UStationClient::SessionUrl(const TCHAR* Suffix) const
{
	return PhoenixBaseUrl + SessionsPath + TEXT("/") + Session->SessionId + Suffix;
}

template <typename T>
void UStationClient::SendSessionRequest(const FString& Verb, const FString& Url, const TSharedPtr<FJsonObject>& Body,
	TFunction<bool(const FJsonObject&, T&)> Parse, TStationCallback<T> OnDone, float TimeoutSeconds)
{
	StationHttp::Send(Verb, Url, Body,
		[Parse = MoveTemp(Parse), OnDone = MoveTemp(OnDone)](const FStationHttpResponse& Response)
		{
			if (Response.Error.IsSet())
			{
				OnDone(MakeError(Response.Error.GetValue()));
				return;
			}
			T Value;
			if (!Response.Json.IsValid() || !Parse(*Response.Json, Value))
			{
				OnDone(MakeError(InvalidResponseError(Response.Status)));
				return;
			}
			OnDone(MakeValue(MoveTemp(Value)));
		},
		TimeoutSeconds > 0.f ? TimeoutSeconds : StationHttp::RequestTimeoutSeconds);
}
