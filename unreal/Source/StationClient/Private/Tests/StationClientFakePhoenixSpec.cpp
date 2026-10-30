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

	// A simulated exam's result adds its score (#426).
	const TCHAR* ExamResultBody = TEXT(R"({
		"schema_version": "2", "session_id": "stub-session", "status": "completed", "placeholder": false,
		"criteria": [], "coverage": {"assessed": 1, "uncertain": 1, "not_observable": 0, "not_applicable": 0},
		"estimates": {"total": null, "scored_subtotal": "6", "scored_max": "8", "eligible_max": "10",
			"unresolved": [{"id": "c2", "status": "uncertain"}]},
		"scaled_total": "7.5", "certainty_level": 4, "incomplete": true
	})");

	// A simulated exam is voice only (#422): Phoenix refuses its typed input.
	const TCHAR* TypedTurnRefusedBody = TEXT(R"({
		"error": "typed_input_not_allowed",
		"message": "A prova simulada é feita só por voz: o texto digitado não é aceito."
	})");

	const TCHAR* TypedImpressoRefusedBody = TEXT(R"({
		"error": "typed_input_not_allowed",
		"message": "Na prova simulada os impressos são pedidos por voz, pelo botão Exames."
	})");

	// A simulated exam ended at its deadline (#424): Phoenix answers the timer
	// finish only when its evidence window closes, and the transcript keeps the
	// learner's late utterance only when it started before the deadline.
	const TCHAR* ExamFinishBody = TEXT(R"({
		"session_id": "stub-session", "status": "completed", "completed_at": "2026-10-21T12:10:03Z",
		"completion_reason": "timer", "mode": "simulated_exam", "deadline_at": "2026-10-21T12:10:00Z",
		"cap_at": "2026-10-21T12:10:00Z", "server_now": "2026-10-21T12:10:03Z"
	})");

	FString ExamShowBody(const TCHAR* Messages)
	{
		return FString::Printf(TEXT(R"({
			"session_id": "stub-session", "station_id": "s", "station_version": "1", "audio_consent": true,
			"mode": "simulated_exam", "started_at": "2026-10-21T12:00:00Z", "expires_at": "2026-10-21T12:30:00Z",
			"deadline_at": "2026-10-21T12:10:00Z", "status": "completed", "completion_reason": "timer",
			"messages": [%s], "server_now": "2026-10-21T12:10:04Z"
		})"), Messages);
	}

	/** Seconds Phoenix's evidence window lasts by default (Backend.Stations.Conversation). */
	constexpr float EvidenceWindowSeconds = 5.f;

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

		void Route(const FString& Path, EHttpServerRequestVerbs Verb, float DelaySeconds, TFunction<FString()> Body,
			EHttpServerResponseCodes Status = EHttpServerResponseCodes::Ok)
		{
			Handles.Add(Router->BindRoute(FHttpPath(Path), Verb,
				FHttpRequestHandler::CreateLambda([DelaySeconds, Body, Status](const FHttpServerRequest&, const FHttpResultCallback& OnComplete)
				{
					const FHttpResultCallback Complete = OnComplete;
					auto Respond = [Complete, Body, Status]()
					{
						TUniquePtr<FHttpServerResponse> Response = FHttpServerResponse::Create(Body(), TEXT("application/json"));
						Response->Code = Status;
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

	LatentIt("hands a simulated exam's score to the caller", FTimespan::FromSeconds(20),
		[this](const FDoneDelegate& Done)
		{
			Server.Route(TEXT("/api/v2/stations/active/sessions/stub-session/result"), EHttpServerRequestVerbs::VERB_GET, 0.f,
				[]() { return FString(ExamResultBody); });
			Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
			{
				if (!TestFalse("start", Started.HasError()))
				{
					Done.Execute();
					return;
				}
				Client->FetchResult([this, Done](const TStationResult<FStationResult>& Result)
				{
					if (TestFalse("result", Result.HasError()))
					{
						TestEqual("scaled total", Result.GetValue().ScaledTotal, TEXT("7.5"));
						TestEqual("level", Result.GetValue().CertaintyLevel, 4);
						TestTrue("incomplete", Result.GetValue().bIncomplete);
					}
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

	LatentIt("hands Phoenix's refusal of typed input in a simulated exam to the caller", FTimespan::FromSeconds(20),
		[this](const FDoneDelegate& Done)
		{
			Server.Route(FString(SessionPath) + TEXT("/messages"), EHttpServerRequestVerbs::VERB_POST, 0.f,
				[]() { return FString(TypedTurnRefusedBody); }, EHttpServerResponseCodes::Forbidden);
			Server.Route(FString(SessionPath) + TEXT("/impressos/request"), EHttpServerRequestVerbs::VERB_POST, 0.f,
				[]() { return FString(TypedImpressoRefusedBody); }, EHttpServerResponseCodes::Forbidden);
			Client->StartSession(false, [this, Done](const TStationResult<FStationSession>&)
			{
				Client->SendTurn(TEXT("Bom dia"), EStationTurnModality::Text, [this, Done](const TStationResult<FStationTurnReply>& Turn)
				{
					if (TestTrue("turn refused", Turn.HasError()))
					{
						TestEqual("turn status", Turn.GetError().HttpStatus, 403);
						TestEqual("turn code", Turn.GetError().Code, TEXT("typed_input_not_allowed"));
						TestEqual("turn message", Turn.GetError().Message,
							TEXT("A prova simulada é feita só por voz: o texto digitado não é aceito."));
					}
					Client->RequestImpresso(TEXT("Solicito hemograma"), TEXT("typed-1"), [this, Done](const TStationResult<FStationImpressoReply>& Exam)
					{
						if (TestTrue("impresso refused", Exam.HasError()))
						{
							TestEqual("impresso status", Exam.GetError().HttpStatus, 403);
							TestEqual("impresso code", Exam.GetError().Code, TEXT("typed_input_not_allowed"));
							TestEqual("impresso message", Exam.GetError().Message,
								TEXT("Na prova simulada os impressos são pedidos por voz, pelo botão Exames."));
						}
						Done.Execute();
					});
				});
			});
		});

	// #424: the timer finish of a simulated exam waits for Phoenix's evidence
	// window, inside the client's request timeout. An utterance that started
	// before the deadline is in the transcript with no patient reply; one that
	// started after it is not. Phoenix applies the 500 ms tolerance, so the
	// client sees a boundary utterance as one of these two cases; the boundary
	// itself is tested at the Phoenix HTTP API.
	for (const bool bStartedBefore : {true, false})
	{
		LatentIt(bStartedBefore
				? TEXT("finishes a simulated exam at its deadline keeping the utterance that started before it")
				: TEXT("finishes a simulated exam at its deadline without the utterance that started after it"),
			FTimespan::FromSeconds(30),
			[this, bStartedBefore](const FDoneDelegate& Done)
			{
				Server.Route(FString(SessionPath) + TEXT("/finish"), EHttpServerRequestVerbs::VERB_POST, EvidenceWindowSeconds + 0.5f,
					[]() { return FString(ExamFinishBody); });
				const FString Messages = bStartedBefore
					? TEXT(R"({"role": "learner", "modality": "voice", "text": "Vou pedir um eletrocardiograma", "at": "2026-10-21T12:10:01Z"})")
					: TEXT("");
				Server.Route(SessionPath, EHttpServerRequestVerbs::VERB_GET, 0.f, [Messages]() { return ExamShowBody(*Messages); });
				Client->StartSession(true, [this, Done, bStartedBefore](const TStationResult<FStationSession>&)
				{
					Client->FinishSession(EStationFinishReason::Timer, [this, Done, bStartedBefore](const TStationResult<FStationSession>& Finished)
					{
						if (!TestFalse(Finished.HasError() ? *FString::Printf(TEXT("finish error %s"), *Finished.GetError().Code) : TEXT("finish"),
							Finished.HasError()))
						{
							Done.Execute();
							return;
						}
						TestEqual("reason", Finished.GetValue().CompletionReason, TEXT("timer"));
						Client->RefreshSession([this, Done, bStartedBefore](const TStationResult<FStationSession>& Refreshed)
						{
							if (TestFalse("refresh", Refreshed.HasError()))
							{
								const TArray<FStationMessage>& Messages = Refreshed.GetValue().Messages;
								TestNull("no patient reply after the deadline", Messages.FindByPredicate(
									[](const FStationMessage& Message) { return Message.Speaker == EStationSpeaker::Patient; }));
								TestEqual("late utterances kept", Messages.Num(), bStartedBefore ? 1 : 0);
								if (bStartedBefore && Messages.Num() == 1)
								{
									TestEqual("kept utterance", Messages[0].Text, TEXT("Vou pedir um eletrocardiograma"));
								}
							}
							Done.Execute();
						});
					});
				});
			});
	}

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
