// Station client tests. `ProyectoMed.StationClient.Unit` needs nothing else;
// `ProyectoMed.StationClient.Phoenix` needs a locally running Phoenix at
// $STATION_PHOENIX_URL (default http://127.0.0.1:4000). See
// docs/unreal-station-client.md for how to run them.

#include "Dom/JsonObject.h"
#include "Misc/AutomationTest.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "StationClient.h"
#include "StationClock.h"
#include "StationHttp.h"
#include "StationJson.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace StationClientTests
{
	TSharedRef<FJsonObject> ParseObject(const FString& Text)
	{
		TSharedPtr<FJsonObject> Object;
		FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Object);
		return Object.IsValid() ? Object.ToSharedRef() : MakeShared<FJsonObject>();
	}

	FString PhoenixUrl()
	{
		const FString FromEnv = FPlatformMisc::GetEnvironmentVariable(TEXT("STATION_PHOENIX_URL"));
		return FromEnv.IsEmpty() ? TEXT("http://127.0.0.1:4000") : FromEnv;
	}

	// A session body as Phoenix's create_session serializes it (microsecond precision).
	const TCHAR* SessionJson = TEXT(R"({
		"session_id": "abc123",
		"station_id": "chest-pain-initial-assessment",
		"station_version": "1.0.0",
		"audio_consent": true,
		"started_at": "2026-10-21T12:00:00.123456Z",
		"expires_at": "2026-10-21T12:30:00.123456Z",
		"deadline_at": "2026-10-21T12:10:00.123456Z",
		"server_now": "2026-10-21T12:00:00.200000Z"
	})");
}

BEGIN_DEFINE_SPEC(FStationClientUnitSpec, "ProyectoMed.StationClient.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
END_DEFINE_SPEC(FStationClientUnitSpec)

void FStationClientUnitSpec::Define()
{
	using namespace StationClientTests;

	Describe("FStationClock", [this]()
	{
		const FDateTime ServerNow(2026, 10, 21, 12, 0, 0);
		const FDateTime Deadline(2026, 10, 21, 12, 10, 0);

		It("counts down from the server deadline by local elapsed time", [this, ServerNow, Deadline]()
		{
			const FStationClock Clock = FStationClock::Anchor(ServerNow, 100.0);
			TestEqual("at the anchor", Clock.RemainingAt(Deadline, 100.0), FTimespan::FromMinutes(10));
			TestEqual("one minute later", Clock.RemainingAt(Deadline, 160.0), FTimespan::FromMinutes(9));
			TestEqual("server time", Clock.ServerTimeAt(130.5), ServerNow + FTimespan::FromSeconds(30.5));
		});

		It("never goes below zero after the deadline", [this, ServerNow, Deadline]()
		{
			const FStationClock Clock = FStationClock::Anchor(ServerNow, 0.0);
			TestEqual("past the deadline", Clock.RemainingAt(Deadline, 3600.0), FTimespan::Zero());
		});

		It("is not anchored until a server time is given", [this]()
		{
			TestFalse("default clock", FStationClock().IsAnchored());
		});
	});

	Describe("StationJson", [this]()
	{
		It("parses the active station", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(R"({
				"station_id": "chest-pain-initial-assessment",
				"version": "1.0.0",
				"language": "pt-BR",
				"display_title": "Dor torácica",
				"candidate_brief": {"scenario": "Você é o médico de plantão.", "tasks": ["Anamnese", "Exame físico"]},
				"voice_mode": "realtime"
			})"));

			FStationSummary Summary;
			TestTrue("parsed", StationJson::ParseSummary(*Json, Summary));
			TestEqual("id", Summary.StationId, TEXT("chest-pain-initial-assessment"));
			TestEqual("version", Summary.Version, TEXT("1.0.0"));
			TestEqual("language", Summary.Language, TEXT("pt-BR"));
			TestEqual("title", Summary.DisplayTitle, TEXT("Dor torácica"));
			TestEqual("scenario", Summary.Scenario, TEXT("Você é o médico de plantão."));
			TestEqual("task count", Summary.Tasks.Num(), 2);
			if (Summary.Tasks.Num() == 2)
			{
				TestEqual("task order", Summary.Tasks[1], TEXT("Exame físico"));
			}
			TestEqual("voice mode", Summary.VoiceMode, EStationVoiceMode::Realtime);
		});

		It("maps every voice mode", [this]()
		{
			const TPair<const TCHAR*, EStationVoiceMode> Cases[] = {
				{TEXT("realtime"), EStationVoiceMode::Realtime},
				{TEXT("turn"), EStationVoiceMode::Turn},
				{TEXT("off"), EStationVoiceMode::Off},
			};
			for (const TPair<const TCHAR*, EStationVoiceMode>& Case : Cases)
			{
				const TSharedRef<FJsonObject> Json = ParseObject(FString::Printf(TEXT(
					R"({"station_id":"s","version":"1","language":"pt-BR","display_title":"t","candidate_brief":{"scenario":"x","tasks":[]},"voice_mode":"%s"})"),
					Case.Key));
				FStationSummary Summary;
				TestTrue(FString::Printf(TEXT("parsed %s"), Case.Key), StationJson::ParseSummary(*Json, Summary));
				TestEqual(FString::Printf(TEXT("mode %s"), Case.Key), Summary.VoiceMode, Case.Value);
			}
		});

		It("rejects an active station without a candidate brief", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(
				R"({"station_id":"s","version":"1","language":"pt-BR","display_title":"t","voice_mode":"off"})"));
			FStationSummary Summary;
			TestFalse("parsed", StationJson::ParseSummary(*Json, Summary));
		});

		It("parses a session with microsecond timestamps", [this]()
		{
			FStationSession Session;
			FDateTime ServerNow;
			TestTrue("parsed", StationJson::ParseSession(*ParseObject(SessionJson), Session, ServerNow));
			TestEqual("id", Session.SessionId, TEXT("abc123"));
			TestEqual("station", Session.StationId, TEXT("chest-pain-initial-assessment"));
			TestEqual("version", Session.StationVersion, TEXT("1.0.0"));
			TestTrue("consent", Session.bAudioConsent);
			TestEqual("status defaults to active", Session.Status, EStationSessionStatus::Active);
			TestEqual("started", Session.StartedAt, FDateTime(2026, 10, 21, 12, 0, 0, 123));
			TestEqual("deadline", Session.DeadlineAt, FDateTime(2026, 10, 21, 12, 10, 0, 123));
			TestEqual("expires", Session.ExpiresAt, FDateTime(2026, 10, 21, 12, 30, 0, 123));
			TestEqual("server now", ServerNow, FDateTime(2026, 10, 21, 12, 0, 0, 200));
		});

		It("reads the status and completion reason of a shown session", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
			Json->SetStringField(TEXT("status"), TEXT("completed"));
			Json->SetStringField(TEXT("completion_reason"), TEXT("timer"));
			FStationSession Session;
			FDateTime ServerNow;
			TestTrue("parsed", StationJson::ParseSession(*Json, Session, ServerNow));
			TestEqual("status", Session.Status, EStationSessionStatus::Completed);
			TestEqual("reason", Session.CompletionReason, TEXT("timer"));
		});

		It("rejects a session without an id", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
			Json->RemoveField(TEXT("session_id"));
			FStationSession Session;
			FDateTime ServerNow;
			TestFalse("parsed", StationJson::ParseSession(*Json, Session, ServerNow));
		});

		It("rejects a session with a malformed deadline", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
			Json->SetStringField(TEXT("deadline_at"), TEXT("soon"));
			FStationSession Session;
			FDateTime ServerNow;
			TestFalse("parsed", StationJson::ParseSession(*Json, Session, ServerNow));
		});
	});

	Describe("UStationClient without a session", [this]()
	{
		It("reports no remaining time", [this]()
		{
			UStationClient* Client = NewObject<UStationClient>();
			TestNull("session", Client->GetSession());
			TestEqual("remaining", Client->GetRemainingTime(), FTimespan::Zero());
		});

		It("refuses to refresh or discard with no_session", [this]()
		{
			UStationClient* Client = NewObject<UStationClient>();
			FString RefreshCode;
			FString DiscardCode;
			Client->RefreshSession([&RefreshCode](const TStationResult<FStationSession>& Result)
			{
				RefreshCode = Result.HasError() ? Result.GetError().Code : TEXT("ok");
			});
			Client->DiscardSession([&DiscardCode](const TStationResult<FStationNone>& Result)
			{
				DiscardCode = Result.HasError() ? Result.GetError().Code : TEXT("ok");
			});
			TestEqual("refresh", RefreshCode, TEXT("no_session"));
			TestEqual("discard", DiscardCode, TEXT("no_session"));
		});
	});
}

BEGIN_DEFINE_SPEC(FStationClientPhoenixSpec, "ProyectoMed.StationClient.Phoenix",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	UStationClient* Client = nullptr;
END_DEFINE_SPEC(FStationClientPhoenixSpec)

void FStationClientPhoenixSpec::Define()
{
	using namespace StationClientTests;

	const FTimespan Timeout = FTimespan::FromSeconds(20);

	BeforeEach([this]()
	{
		Client = NewObject<UStationClient>();
		Client->AddToRoot();
		Client->SetPhoenixBaseUrl(PhoenixUrl());
	});

	// Leave no session behind in Phoenix, whatever the test did.
	LatentAfterEach(Timeout, [this](const FDoneDelegate& Done)
	{
		if (!Client->GetSession())
		{
			Client->RemoveFromRoot();
			Done.Execute();
			return;
		}
		Client->DiscardSession([this, Done](const TStationResult<FStationNone>&)
		{
			Client->RemoveFromRoot();
			Done.Execute();
		});
	});

	LatentIt("fetches the active station Phoenix serves", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->FetchActiveStation([this, Done](const TStationResult<FStationSummary>& Result)
		{
			if (TestFalse(TEXT("error (is Phoenix running at $STATION_PHOENIX_URL?)"), Result.HasError()))
			{
				const FStationSummary& Summary = Result.GetValue();
				TestFalse("station id", Summary.StationId.IsEmpty());
				TestFalse("title", Summary.DisplayTitle.IsEmpty());
				TestFalse("scenario", Summary.Scenario.IsEmpty());
				TestTrue("tasks", Summary.Tasks.Num() > 0);
			}
			Done.Execute();
		});
	});

	LatentIt("starts an ephemeral session with a ten-minute server-owned timer", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(true, [this, Done](const TStationResult<FStationSession>& Result)
		{
			if (TestFalse("error", Result.HasError()))
			{
				const FStationSession& Session = Result.GetValue();
				TestFalse("session id", Session.SessionId.IsEmpty());
				TestTrue("consent echoed", Session.bAudioConsent);
				TestEqual("status", Session.Status, EStationSessionStatus::Active);
				TestEqual("timer length", Session.DeadlineAt - Session.StartedAt, FTimespan::FromMinutes(10));
				TestEqual("held by the client", Client->GetSession() ? Client->GetSession()->SessionId : FString(), Session.SessionId);

				const FTimespan Remaining = Client->GetRemainingTime();
				TestTrue("timer started", Remaining <= FTimespan::FromMinutes(10) && Remaining > FTimespan::FromMinutes(9.5));
			}
			Done.Execute();
		});
	});

	LatentIt("refuses a second run while one is in progress", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& First)
		{
			if (!TestFalse("first start", First.HasError()))
			{
				Done.Execute();
				return;
			}
			const FString FirstId = First.GetValue().SessionId;
			Client->StartSession(false, [this, Done, FirstId](const TStationResult<FStationSession>& Second)
			{
				TestTrue("second start fails", Second.HasError());
				if (Second.HasError())
				{
					TestEqual("code", Second.GetError().Code, TEXT("session_in_progress"));
				}
				TestEqual("first run kept", Client->GetSession() ? Client->GetSession()->SessionId : FString(), FirstId);
				Done.Execute();
			});
		});
	});

	LatentIt("refuses a second start while the first is still in flight", Timeout, [this](const FDoneDelegate& Done)
	{
		TSharedRef<FString> SecondCode = MakeShared<FString>();
		Client->StartSession(false, [this, Done, SecondCode](const TStationResult<FStationSession>& First)
		{
			TestFalse("first start", First.HasError());
			TestEqual("second start", *SecondCode, TEXT("session_in_progress"));
			Done.Execute();
		});
		Client->StartSession(false, [SecondCode](const TStationResult<FStationSession>& Second)
		{
			*SecondCode = Second.HasError() ? Second.GetError().Code : TEXT("ok");
		});
	});

	LatentIt("refreshes the current session from Phoenix", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			const FStationSession StartedSession = Started.GetValue();
			Client->RefreshSession([this, Done, StartedSession](const TStationResult<FStationSession>& Refreshed)
			{
				if (TestFalse("refresh", Refreshed.HasError()))
				{
					TestEqual("same id", Refreshed.GetValue().SessionId, StartedSession.SessionId);
					TestEqual("same deadline", Refreshed.GetValue().DeadlineAt, StartedSession.DeadlineAt);
					TestFalse("consent echoed", Refreshed.GetValue().bAudioConsent);
				}
				Done.Execute();
			});
		});
	});

	LatentIt("discards the run in Phoenix before clearing it locally", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			const FString SessionId = Started.GetValue().SessionId;
			Client->DiscardSession([this, Done, SessionId](const TStationResult<FStationNone>& Discarded)
			{
				TestFalse("discard", Discarded.HasError());
				TestNull("cleared locally", Client->GetSession());

				const FString Url = Client->GetPhoenixBaseUrl() + TEXT("/api/stations/active/sessions/") + SessionId;
				StationHttp::Send(TEXT("GET"), Url, nullptr, [this, Done](const FStationHttpResponse& Response)
				{
					TestEqual("Phoenix forgot it", Response.Status, 404);
					Done.Execute();
				});
			});
		});
	});

	LatentIt("maps a Phoenix error body to the error code", Timeout, [this](const FDoneDelegate& Done)
	{
		const FString Url = Client->GetPhoenixBaseUrl() + TEXT("/api/stations/active/sessions/no-such-session");
		StationHttp::Send(TEXT("GET"), Url, nullptr, [this, Done](const FStationHttpResponse& Response)
		{
			if (TestTrue("error", Response.Error.IsSet()))
			{
				TestEqual("status", Response.Error->HttpStatus, 404);
				TestEqual("code", Response.Error->Code, TEXT("session_not_found"));
				TestFalse("message", Response.Error->Message.IsEmpty());
			}
			Done.Execute();
		});
	});

	LatentIt("reports network_error when Phoenix is unreachable", Timeout, [this](const FDoneDelegate& Done)
	{
		// Port 9 (discard) is closed on a development machine.
		Client->SetPhoenixBaseUrl(TEXT("http://127.0.0.1:9"));
		Client->FetchActiveStation([this, Done](const TStationResult<FStationSummary>& Result)
		{
			if (TestTrue("error", Result.HasError()))
			{
				TestEqual("status", Result.GetError().HttpStatus, 0);
				TestEqual("code", Result.GetError().Code, TEXT("network_error"));
			}
			Done.Execute();
		});
	});
}

#endif // WITH_DEV_AUTOMATION_TESTS
