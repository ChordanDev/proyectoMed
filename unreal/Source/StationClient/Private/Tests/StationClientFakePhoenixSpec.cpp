// Station client tests against a fake Phoenix served in-process, for behaviour a
// real Phoenix cannot be made to show on demand: slow responses and responses
// that arrive out of order.

#include "Containers/Ticker.h"
#include "HttpPath.h"
#include "HttpRouteHandle.h"
#include "HttpServerModule.h"
#include "HttpServerResponse.h"
#include "IHttpRouter.h"
#include "Misc/AutomationTest.h"
#include "StationClient.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace StationFakePhoenix
{
	constexpr uint32 Port = 18765;
	const TCHAR* SessionPath = TEXT("/api/stations/active/sessions/stub-session");

	const TCHAR* SessionBody = TEXT(R"({
		"session_id": "stub-session", "station_id": "s", "station_version": "1", "audio_consent": false,
		"started_at": "2026-10-21T12:00:00Z", "expires_at": "2026-10-21T12:30:00Z",
		"deadline_at": "2026-10-21T12:10:00Z", "server_now": "2026-10-21T12:00:00Z"
	})");

	FString ShowBody(const TCHAR* Status)
	{
		return FString::Printf(TEXT(R"({
			"session_id": "stub-session", "station_id": "s", "station_version": "1", "audio_consent": false,
			"started_at": "2026-10-21T12:00:00Z", "expires_at": "2026-10-21T12:30:00Z",
			"deadline_at": "2026-10-21T12:10:00Z", "status": "%s", "completion_reason": %s,
			"messages": [], "server_now": "2026-10-21T12:01:00Z"
		})"), Status, FCString::Strcmp(Status, TEXT("completed")) == 0 ? TEXT("\"user\"") : TEXT("null"));
	}

	const TCHAR* FinishBody = TEXT(R"({
		"session_id": "stub-session", "status": "completed", "completed_at": "2026-10-21T12:05:00Z",
		"completion_reason": "user", "deadline_at": "2026-10-21T12:10:00Z", "server_now": "2026-10-21T12:05:00Z"
	})");

	const TCHAR* ResultBody = TEXT(R"({
		"schema_version": "2", "session_id": "stub-session", "status": "completed", "placeholder": false,
		"criteria": [], "coverage": {"assessed": 0, "uncertain": 0, "not_observable": 0, "not_applicable": 0},
		"estimates": {"total": null, "scored_subtotal": "0", "scored_max": "0", "eligible_max": "0", "unresolved": []}
	})");

	/** Routes on a local port that answer with a fixed status after a delay. */
	class FServer
	{
	public:
		void Start()
		{
			Router = FHttpServerModule::Get().GetHttpRouter(Port, /*bFailOnBindFailure*/ true);
			FHttpServerModule::Get().StartAllListeners();
		}

		bool IsListening() const { return Router.IsValid(); }

		void Route(const FString& Path, EHttpServerRequestVerbs Verb, float DelaySeconds, TFunction<FString()> Body)
		{
			Handles.Add(Router->BindRoute(FHttpPath(Path), Verb,
				FHttpRequestHandler::CreateLambda([DelaySeconds, Body](const FHttpServerRequest&, const FHttpResultCallback& OnComplete)
				{
					const FHttpResultCallback Complete = OnComplete;
					auto Respond = [Complete, Body]()
					{
						TUniquePtr<FHttpServerResponse> Response = FHttpServerResponse::Create(Body(), TEXT("application/json"));
						Response->Code = EHttpServerResponseCodes::Ok;
						Complete(MoveTemp(Response));
					};
					if (DelaySeconds <= 0.f)
					{
						Respond();
					}
					else
					{
						FTSTicker::GetCoreTicker().AddTicker(
							FTickerDelegate::CreateLambda([Respond](float) { Respond(); return false; }), DelaySeconds);
					}
					return true;
				})));
		}

		void Stop()
		{
			if (Router.IsValid())
			{
				for (const FHttpRouteHandle& Handle : Handles)
				{
					Router->UnbindRoute(Handle);
				}
			}
			Handles.Reset();
			Router.Reset();
		}

	private:
		TSharedPtr<IHttpRouter> Router;
		TArray<FHttpRouteHandle> Handles;
	};
}

BEGIN_DEFINE_SPEC(FStationClientFakePhoenixSpec, "ProyectoMed.StationClient.FakePhoenix",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	UStationClient* Client = nullptr;
	StationFakePhoenix::FServer Server;
END_DEFINE_SPEC(FStationClientFakePhoenixSpec)

void FStationClientFakePhoenixSpec::Define()
{
	using namespace StationFakePhoenix;

	BeforeEach([this]()
	{
		Server.Start();
		TestTrue("fake Phoenix listening", Server.IsListening());
		Server.Route(TEXT("/api/stations/active/sessions"), EHttpServerRequestVerbs::VERB_POST, 0.f,
			[]() { return FString(SessionBody); });

		Client = NewObject<UStationClient>();
		Client->AddToRoot();
		Client->SetPhoenixBaseUrl(FString::Printf(TEXT("http://127.0.0.1:%u"), Port));
	});

	AfterEach([this]()
	{
		Client->RemoveFromRoot();
		Server.Stop();
	});

	// Phoenix may take up to about 95 s to assess a run the first time (backend/config/runtime.exs).
	LatentIt("waits for an educational result that takes longer than the default timeout", FTimespan::FromSeconds(40),
		[this](const FDoneDelegate& Done)
		{
			Server.Route(TEXT("/api/v2/stations/active/sessions/stub-session/result"), EHttpServerRequestVerbs::VERB_GET, 17.f,
				[]() { return FString(ResultBody); });
			Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
			{
				if (!TestFalse("start", Started.HasError()))
				{
					Done.Execute();
					return;
				}
				Client->FetchResult([this, Done](const TStationResult<FStationResult>& Result)
				{
					TestFalse(Result.HasError() ? *FString::Printf(TEXT("error %s"), *Result.GetError().Code) : TEXT("result"),
						Result.HasError());
					Done.Execute();
				});
			});
		});

	LatentIt("keeps a finished run's completion time when it is refreshed", FTimespan::FromSeconds(20),
		[this](const FDoneDelegate& Done)
		{
			Server.Route(FString(SessionPath) + TEXT("/finish"), EHttpServerRequestVerbs::VERB_POST, 0.f,
				[]() { return FString(FinishBody); });
			Server.Route(SessionPath, EHttpServerRequestVerbs::VERB_GET, 0.f, []() { return ShowBody(TEXT("completed")); });
			Client->StartSession(false, [this, Done](const TStationResult<FStationSession>&)
			{
				Client->FinishSession(EStationFinishReason::User, [this, Done](const TStationResult<FStationSession>& Finished)
				{
					TestFalse("finish", Finished.HasError());
					Client->RefreshSession([this, Done](const TStationResult<FStationSession>& Refreshed)
					{
						TestFalse("refresh", Refreshed.HasError());
						if (TestNotNull("session", Client->GetSession()))
						{
							TestEqual("status", Client->GetSession()->Status, EStationSessionStatus::Completed);
							TestEqual("completed at", Client->GetSession()->CompletedAt, FDateTime(2026, 10, 21, 12, 5, 0));
						}
						Done.Execute();
					});
				});
			});
		});

	LatentIt("does not reopen a finished run when an older refresh answers late", FTimespan::FromSeconds(20),
		[this](const FDoneDelegate& Done)
		{
			Server.Route(FString(SessionPath) + TEXT("/finish"), EHttpServerRequestVerbs::VERB_POST, 0.f,
				[]() { return FString(FinishBody); });
			// The show answer was read while the run was still active and arrives after the finish.
			Server.Route(SessionPath, EHttpServerRequestVerbs::VERB_GET, 1.5f, []() { return ShowBody(TEXT("active")); });
			Client->StartSession(false, [this, Done](const TStationResult<FStationSession>&)
			{
				TSharedRef<int32> Pending = MakeShared<int32>(2);
				auto Check = [this, Done, Pending]()
				{
					if (--(*Pending) > 0)
					{
						return;
					}
					if (TestNotNull("session", Client->GetSession()))
					{
						TestEqual("still completed", Client->GetSession()->Status, EStationSessionStatus::Completed);
						TestEqual("completed at", Client->GetSession()->CompletedAt, FDateTime(2026, 10, 21, 12, 5, 0));
						TestEqual("reason", Client->GetSession()->CompletionReason, TEXT("user"));
					}
					TestEqual("timer stopped", Client->GetRemainingTime(), FTimespan::Zero());
					Done.Execute();
				};
				Client->RefreshSession([this, Check](const TStationResult<FStationSession>& Refreshed)
				{
					if (TestFalse("refresh", Refreshed.HasError()))
					{
						TestEqual("refresh reports the finished run", Refreshed.GetValue().Status, EStationSessionStatus::Completed);
					}
					Check();
				});
				Client->FinishSession(EStationFinishReason::User, [this, Check](const TStationResult<FStationSession>& Finished)
				{
					TestFalse("finish", Finished.HasError());
					Check();
				});
			});
		});
}

#endif // WITH_DEV_AUTOMATION_TESTS
