// What the learner gets when Phoenix refuses to start a station because the daily
// quota is used up or the account has no subscription (#467), through the run flow
// against a fake Phoenix served in-process, which can refuse on demand. Like the
// other fake Phoenix specs it starts the editor's HTTP listeners, so an editor
// already open on the same machine makes it fail to bind. What the two screens show
// needs nothing else; their look is judged on the images of StationQuotaSnapshotSpec.cpp.

#include "Blueprint/WidgetTree.h"
#include "Components/Button.h"
#include "Components/TextBlock.h"
#include "Engine/Engine.h"
#include "HttpPath.h"
#include "HttpRouteHandle.h"
#include "HttpServerModule.h"
#include "HttpServerResponse.h"
#include "IHttpRouter.h"
#include "Misc/AutomationTest.h"
#include "Station/StationPlayerController.h"
#include "Station/StationQuotaScreens.h"
#include "Station/StationRunFlow.h"
#include "Station/StationScreens.h"
#include "StationClient.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace StationQuotaFake
{
	constexpr uint32 Port = 18767;
	const TCHAR* ActiveStationPath = TEXT("/api/stations/active");
	const TCHAR* SessionsPath = TEXT("/api/stations/active/sessions");

	const TCHAR* StationBody = TEXT(R"({
		"station_id": "s", "version": "1", "language": "pt-BR", "display_title": "Estação",
		"candidate_brief": {"scenario": "Cenário.", "tasks": ["Tarefa."]}, "voice_mode": "realtime"
	})");

	const TCHAR* SessionBody = TEXT(R"({
		"session_id": "stub-session", "station_id": "s", "station_version": "1", "audio_consent": false,
		"started_at": "2026-10-27T12:00:00Z", "expires_at": "2026-10-27T12:30:00Z",
		"deadline_at": "2026-10-27T12:10:00Z", "server_now": "2026-10-27T12:00:00Z"
	})");

	const TCHAR* SubscriptionBody = TEXT(R"({"error": "subscription_required", "message": "Assine um plano para usar o simulador."})");

	FString QuotaBody(const FDateTime& ResetsAt)
	{
		return FString::Printf(TEXT(R"({
			"error": "daily_quota_exhausted",
			"message": "Você usou todas as simulações de hoje. A cota renova à meia-noite (horário de Brasília).",
			"daily_quota": 10,
			"resets_at": "%s"
		})"), *ResetsAt.ToIso8601());
	}

	/** Answers each route with a fixed status and body; a later `Route` of a path replaces the answer. */
	class FServer
	{
	public:
		void Start()
		{
			Router = FHttpServerModule::Get().GetHttpRouter(Port, /*bFailOnBindFailure*/ true);
			FHttpServerModule::Get().StartAllListeners();
		}

		bool IsListening() const { return Router.IsValid(); }

		void Route(const FString& Path, EHttpServerRequestVerbs Verb, EHttpServerResponseCodes Code, const FString& Body)
		{
			if (const FHttpRouteHandle* Bound = Handles.Find(Path))
			{
				Router->UnbindRoute(*Bound);
			}
			Handles.Add(Path, Router->BindRoute(FHttpPath(Path), Verb,
				FHttpRequestHandler::CreateLambda([Code, Body](const FHttpServerRequest&, const FHttpResultCallback& OnComplete)
				{
					TUniquePtr<FHttpServerResponse> Response = FHttpServerResponse::Create(Body, TEXT("application/json"));
					Response->Code = Code;
					OnComplete(MoveTemp(Response));
					return true;
				})));
		}

		void Stop()
		{
			if (Router.IsValid())
			{
				for (const TPair<FString, FHttpRouteHandle>& Bound : Handles)
				{
					Router->UnbindRoute(Bound.Value);
				}
			}
			Handles.Reset();
			Router.Reset();
		}

	private:
		TSharedPtr<IHttpRouter> Router;
		TMap<FString, FHttpRouteHandle> Handles;
	};

	/** Calls `Then` once, the first time `Condition` holds after a flow change (or right away). */
	void WhenFlowIs(UStationRunFlow* Flow, TFunction<bool()> Condition, TFunction<void()> Then)
	{
		if (Condition())
		{
			Then();
			return;
		}
		TSharedRef<FDelegateHandle> Handle = MakeShared<FDelegateHandle>();
		*Handle = Flow->OnChanged.AddLambda([Flow, Condition, Then, Handle]()
		{
			if (Condition())
			{
				const TFunction<void()> ThenCopy = Then;
				Flow->OnChanged.Remove(*Handle);
				ThenCopy();
			}
		});
	}

	FStationMicrophoneSetup GrantedMicrophone()
	{
		FStationMicrophoneSetup Setup;
		Setup.GetPermission = []() { return EStationMicPermission::Granted; };
		Setup.RequestPermission = [](TFunction<void(EStationMicPermission)> OnDone) { OnDone(EStationMicPermission::Granted); };
		Setup.WasDisclosureShown = []() { return true; };
		Setup.RememberDisclosureShown = []() {};
		return Setup;
	}
}

BEGIN_DEFINE_SPEC(FStationQuotaUnitSpec, "ProyectoMed.StationRun.Unit.Quota",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	UStationClient* Client = nullptr;
	UStationRunFlow* Flow = nullptr;
	StationQuotaFake::FServer Server;

	/** Phoenix answers the next start with `Code` and `Body`. */
	void RefuseStart(EHttpServerResponseCodes Code, const FString& Body)
	{
		Server.Route(StationQuotaFake::SessionsPath, EHttpServerRequestVerbs::VERB_POST, Code, Body);
	}

	/** From the menu to `Then`, called once Phoenix answered the start of a text training. */
	void EnterTraining(TFunction<void()> Then)
	{
		Flow->ChooseMode(EStationSessionMode::Training);
		Flow->AcknowledgeNotice();
		Flow->Enter(EStationTrainingMode::Text);
		StationQuotaFake::WhenFlowIs(Flow, [this]() { return Flow->GetStep() != EStationRunStep::Starting; }, MoveTemp(Then));
	}
END_DEFINE_SPEC(FStationQuotaUnitSpec)

void FStationQuotaUnitSpec::Define()
{
	using namespace StationQuotaFake;

	const FTimespan Timeout = FTimespan::FromSeconds(20);

	BeforeEach([this]()
	{
		Server.Start();
		TestTrue("fake Phoenix listening", Server.IsListening());
		Server.Route(ActiveStationPath, EHttpServerRequestVerbs::VERB_GET, EHttpServerResponseCodes::Ok, StationBody);
		Client = NewObject<UStationClient>();
		Client->AddToRoot();
		Client->SetPhoenixBaseUrl(FString::Printf(TEXT("http://127.0.0.1:%u"), Port));
		Flow = NewObject<UStationRunFlow>();
		Flow->AddToRoot();
	});

	LatentBeforeEach(Timeout, [this](const FDoneDelegate& Done)
	{
		Flow->Begin(Client, GrantedMicrophone());
		WhenFlowIs(Flow, [this]() { return !Flow->IsStationLoading(); }, [this, Done]()
		{
			TestNotNull("the station loaded", Flow->GetStation());
			Done.Execute();
		});
	});

	AfterEach([this]()
	{
		Flow->RemoveFromRoot();
		Client->RemoveFromRoot();
		Server.Stop();
	});

	LatentIt("carries daily_quota and resets_at of a refused start in the client's error", Timeout, [this](const FDoneDelegate& Done)
	{
		RefuseStart(EHttpServerResponseCodes::TooManyRequests, QuotaBody(FDateTime(2026, 10, 26, 3)));
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (TestTrue("refused", Started.HasError()))
			{
				const FStationClientError& Error = Started.GetError();
				TestEqual("status", Error.HttpStatus, 429);
				TestEqual("code", Error.Code, FString(TEXT("daily_quota_exhausted")));
				TestEqual("daily quota", Error.DailyQuota, 10);
				TestTrue("resets at", Error.ResetsAt == FDateTime(2026, 10, 26, 3));
			}
			Done.Execute();
		});
	});

	LatentIt("leaves both fields unset on any other refusal", Timeout, [this](const FDoneDelegate& Done)
	{
		RefuseStart(EHttpServerResponseCodes::PaymentReq, SubscriptionBody);
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (TestTrue("refused", Started.HasError()))
			{
				TestEqual("no daily quota", Started.GetError().DailyQuota, 0);
				TestTrue("no reset", Started.GetError().ResetsAt == FDateTime());
			}
			Done.Execute();
		});
	});

	LatentIt("shows the quota screen, not an error, when today's simulations are used up", Timeout, [this](const FDoneDelegate& Done)
	{
		const FDateTime ResetsAt = FDateTime::UtcNow() + FTimespan::FromHours(5);
		RefuseStart(EHttpServerResponseCodes::TooManyRequests, QuotaBody(ResetsAt));
		EnterTraining([this, Done]()
		{
			TestEqual("the quota step", Flow->GetStep(), EStationRunStep::DailyQuota);
			TestTrue("no raw error", Flow->GetErrorText().IsEmpty());
			const double Hours = Flow->GetDailyQuotaTimeLeft().GetTotalHours();
			TestTrue("the time left until resets_at", Hours > 4.9 && Hours <= 5.0);
			Done.Execute();
		});
	});

	LatentIt("shows the quota screen after a simulated exam is refused too", Timeout, [this](const FDoneDelegate& Done)
	{
		RefuseStart(EHttpServerResponseCodes::TooManyRequests, QuotaBody(FDateTime::UtcNow() + FTimespan::FromHours(5)));
		Flow->ChooseMode(EStationSessionMode::SimulatedExam);
		Flow->AcknowledgeNotice();
		Flow->EnterSimulatedExam();
		WhenFlowIs(Flow, [this]() { return Flow->GetStep() != EStationRunStep::Starting; }, [this, Done]()
		{
			TestEqual("the quota step", Flow->GetStep(), EStationRunStep::DailyQuota);
			Done.Execute();
		});
	});

	LatentIt("shows the subscription screen, not an error, when the account has no subscription", Timeout, [this](const FDoneDelegate& Done)
	{
		RefuseStart(EHttpServerResponseCodes::PaymentReq, SubscriptionBody);
		EnterTraining([this, Done]()
		{
			TestEqual("the subscription step", Flow->GetStep(), EStationRunStep::Subscription);
			TestTrue("no raw error", Flow->GetErrorText().IsEmpty());
			Done.Execute();
		});
	});

	LatentIt("counts the time left on this machine's clock, whatever Phoenix's clock said", Timeout, [this](const FDoneDelegate& Done)
	{
		// The fake session's `server_now` is days behind this machine, so an anchored clock would read days more.
		RefuseStart(EHttpServerResponseCodes::Ok, SessionBody);
		EnterTraining([this, Done]()
		{
			TestEqual("the run", Flow->GetStep(), EStationRunStep::Running);
			Flow->DailyQuotaResetsAt = FDateTime::UtcNow() + FTimespan::FromHours(5);
			const double Hours = Flow->GetDailyQuotaTimeLeft().GetTotalHours();
			TestTrue("five hours by this machine", Hours > 4.9 && Hours <= 5.0);
			Done.Execute();
		});
	});

	LatentIt("still shows the quota screen when Phoenix sends no readable resets_at", Timeout, [this](const FDoneDelegate& Done)
	{
		RefuseStart(EHttpServerResponseCodes::TooManyRequests,
			TEXT(R"({"error": "daily_quota_exhausted", "message": "Sem cota.", "resets_at": "amanhã"})"));
		EnterTraining([this, Done]()
		{
			TestEqual("the quota step", Flow->GetStep(), EStationRunStep::DailyQuota);
			TestTrue("no time left to show", Flow->GetDailyQuotaTimeLeft() == FTimespan::Zero());
			Done.Execute();
		});
	});

	LatentIt("keeps showing any other failed start on the brief", Timeout, [this](const FDoneDelegate& Done)
	{
		RefuseStart(EHttpServerResponseCodes::ServiceUnavail,
			TEXT(R"({"error": "station_unavailable", "message": "A estação não está disponível."})"));
		EnterTraining([this, Done]()
		{
			TestEqual("back on the brief", Flow->GetStep(), EStationRunStep::Brief);
			TestEqual("Phoenix's message", Flow->GetErrorText().ToString(), FString(TEXT("A estação não está disponível.")));
			Done.Execute();
		});
	});

	LatentIt("keeps a 429 that is not the quota on the brief: the code decides, not the status", Timeout, [this](const FDoneDelegate& Done)
	{
		RefuseStart(EHttpServerResponseCodes::TooManyRequests,
			TEXT(R"({"error": "rate_limited", "message": "Muitas tentativas."})"));
		EnterTraining([this, Done]()
		{
			TestEqual("back on the brief", Flow->GetStep(), EStationRunStep::Brief);
			TestEqual("Phoenix's message", Flow->GetErrorText().ToString(), FString(TEXT("Muitas tentativas.")));
			Done.Execute();
		});
	});

	LatentIt("goes back to the menu from the quota screen, and Phoenix decides the next start", Timeout, [this](const FDoneDelegate& Done)
	{
		RefuseStart(EHttpServerResponseCodes::TooManyRequests, QuotaBody(FDateTime::UtcNow() + FTimespan::FromHours(5)));
		EnterTraining([this, Done]()
		{
			Flow->BackToMenu();
			TestEqual("the menu", Flow->GetStep(), EStationRunStep::Menu);

			// The client does not hold the quota back: the same learner starts as soon as Phoenix allows it.
			RefuseStart(EHttpServerResponseCodes::Ok, SessionBody);
			EnterTraining([this, Done]()
			{
				TestEqual("the run", Flow->GetStep(), EStationRunStep::Running);
				Done.Execute();
			});
		});
	});

	LatentIt("goes back to the menu from the subscription screen", Timeout, [this](const FDoneDelegate& Done)
	{
		RefuseStart(EHttpServerResponseCodes::PaymentReq, SubscriptionBody);
		EnterTraining([this, Done]()
		{
			Flow->BackToMenu();
			TestEqual("the menu", Flow->GetStep(), EStationRunStep::Menu);
			Done.Execute();
		});
	});
}

BEGIN_DEFINE_SPEC(FStationQuotaScreensSpec, "ProyectoMed.StationCards.Unit.Quota",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	/** Keeps the screens' Slate widgets, as the viewport does. */
	TArray<TSharedRef<SWidget>> Held;

	UStationQuotaWidget* MakeQuota(const FTimespan& Left);
	UStationSubscriptionWidget* MakeSubscription();
	/** Every text of `Screen`, in tree order. */
	static TArray<FString> Texts(UUserWidget& Screen);
END_DEFINE_SPEC(FStationQuotaScreensSpec)

UStationQuotaWidget* FStationQuotaScreensSpec::MakeQuota(const FTimespan& Left)
{
	UStationRunFlow* Flow = NewObject<UStationRunFlow>();
	Flow->Step = EStationRunStep::DailyQuota;
	Flow->DailyQuotaResetsAt = FDateTime::UtcNow() + Left;
	UStationQuotaWidget* Quota = CreateWidget<UStationQuotaWidget>(GEngine->GetWorldContexts()[0].World());
	Held.Add(Quota->TakeWidget());
	Quota->SetFlow(Flow);
	Quota->Refresh();
	return Quota;
}

UStationSubscriptionWidget* FStationQuotaScreensSpec::MakeSubscription()
{
	UStationSubscriptionWidget* Subscription = CreateWidget<UStationSubscriptionWidget>(GEngine->GetWorldContexts()[0].World());
	Held.Add(Subscription->TakeWidget());
	return Subscription;
}

TArray<FString> FStationQuotaScreensSpec::Texts(UUserWidget& Screen)
{
	TArray<FString> Found;
	Screen.WidgetTree->ForEachWidget([&Found](UWidget* Widget)
	{
		if (const UTextBlock* Text = Cast<UTextBlock>(Widget))
		{
			Found.Add(Text->GetText().ToString());
		}
	});
	return Found;
}

void FStationQuotaScreensSpec::Define()
{
	AfterEach([this]()
	{
		Held.Reset();
	});

	It("formats the time left as the mockup does, rounding up to the minute", [this]()
	{
		TestEqual("hours and minutes", FormatDailyQuotaTimeLeft(FTimespan(5, 11, 30)).ToString(), FString(TEXT("5 h 12 min")));
		TestEqual("whole hours", FormatDailyQuotaTimeLeft(FTimespan(2, 0, 0)).ToString(), FString(TEXT("2 h 0 min")));
		TestEqual("the last minute of an hour", FormatDailyQuotaTimeLeft(FTimespan(0, 59, 30)).ToString(), FString(TEXT("1 h 0 min")));
		TestEqual("under an hour", FormatDailyQuotaTimeLeft(FTimespan(0, 42, 0)).ToString(), FString(TEXT("42 min")));
		TestEqual("seconds still read a minute", FormatDailyQuotaTimeLeft(FTimespan(0, 0, 1)).ToString(), FString(TEXT("1 min")));
	});

	It("says the quota is used up, when it renews and how long is left", [this]()
	{
		UStationQuotaWidget* Quota = MakeQuota(FTimespan(5, 11, 30));
		const TArray<FString> Shown = Texts(*Quota);
		TestTrue("the title", Shown.Contains(TEXT("Você usou todas as simulações de hoje.")));
		TestTrue("the renewal", Shown.Contains(TEXT("A cota renova à meia-noite (horário de Brasília).")));
		TestTrue("the time left", Shown.Contains(TEXT("5 h 12 min")));
		TestTrue("what it counts down to", Shown.Contains(TEXT("para renovar")));
		TestEqual("in view", Quota->Countdown->GetVisibility(), ESlateVisibility::Visible);
	});

	It("counts down as time passes", [this]()
	{
		UStationQuotaWidget* Quota = MakeQuota(FTimespan(5, 11, 30));
		Quota->Flow->DailyQuotaResetsAt -= FTimespan::FromMinutes(12.0);
		Quota->NativeTick(FGeometry(), 0.016f);
		TestEqual("twelve minutes later", Quota->TimeLeftText->GetText().ToString(), FString(TEXT("5 h 0 min")));
	});

	It("drops the countdown once there is no time left to show", [this]()
	{
		TestEqual("past the reset", MakeQuota(-FTimespan::FromMinutes(1.0))->Countdown->GetVisibility(), ESlateVisibility::Collapsed);
	});

	It("offers the history, not yet there (#465), and the way back to the menu", [this]()
	{
		UStationQuotaWidget* Quota = MakeQuota(FTimespan(5, 11, 30));
		const TArray<FString> Shown = Texts(*Quota);
		TestTrue("the history", Shown.Contains(TEXT("Revisar o histórico")));
		TestFalse("disabled until it exists", Quota->HistoryButton->GetIsEnabled());
		TestTrue("the menu", Shown.Contains(TEXT("Voltar ao menu")));

		int32 Backs = 0;
		Quota->OnBackToMenu.BindLambda([&Backs]() { ++Backs; });
		Quota->MenuButton->OnClicked.Broadcast();
		TestEqual("the menu button goes back", Backs, 1);
	});

	It("asks for a subscription, and shows no price or plan", [this]()
	{
		UStationSubscriptionWidget* Subscription = MakeSubscription();
		TArray<FString> Shown = Texts(*Subscription);
		TestTrue("the title", Shown.Contains(TEXT("Assine para fazer estações")));
		TestTrue("the plans button", Shown.Contains(TEXT("Ver planos no site")));
		TestTrue("the menu", Shown.Contains(TEXT("Voltar ao menu")));
		for (const FString& Text : Shown)
		{
			TestFalse(*FString::Printf(TEXT("no price in '%s'"), *Text), Text.Contains(TEXT("R$")));
			TestFalse(*FString::Printf(TEXT("no figure in '%s'"), *Text), Text.Contains(TEXT("/mês")));
		}
	});

	It("shows each screen on its own step, in place of the brief", [this]()
	{
		UWorld* World = GEngine->GetWorldContexts()[0].World();
		UStationRunFlow* Flow = NewObject<UStationRunFlow>();
		Flow->Step = EStationRunStep::DailyQuota;
		AStationPlayerController* Controller = World->SpawnActor<AStationPlayerController>();
		Controller->Flow = Flow;
		Controller->Menu = CreateWidget<UStationMenuWidget>(World);
		Controller->Notice = CreateWidget<UStationNoticeWidget>(World);
		Controller->Brief = CreateWidget<UStationBriefWidget>(World);
		Controller->Hud = CreateWidget<UStationHudWidget>(World);
		Controller->Feedback = CreateWidget<UStationFeedbackWidget>(World);
		Controller->Invalidated = CreateWidget<UStationInvalidatedWidget>(World);
		Controller->MicrophoneScreen = CreateWidget<UStationMicrophoneWidget>(World);
		Controller->Quota = CreateWidget<UStationQuotaWidget>(World);
		Controller->Subscription = CreateWidget<UStationSubscriptionWidget>(World);
		for (UUserWidget* Screen : TArray<UUserWidget*>{Controller->Menu, Controller->Notice, Controller->Brief, Controller->Hud,
				 Controller->Feedback, Controller->Invalidated, Controller->MicrophoneScreen, Controller->Quota, Controller->Subscription})
		{
			Held.Add(Screen->TakeWidget());
		}
		Controller->Quota->SetFlow(Flow);
		Controller->MicrophoneUpdate = []() {};

		Controller->Render();
		TestEqual("the quota screen", Controller->Quota->GetVisibility(), ESlateVisibility::Visible);
		TestEqual("not the subscription screen", Controller->Subscription->GetVisibility(), ESlateVisibility::Collapsed);
		TestEqual("not the brief", Controller->Brief->GetVisibility(), ESlateVisibility::Collapsed);

		Flow->Step = EStationRunStep::Subscription;
		Controller->Render();
		TestEqual("the subscription screen", Controller->Subscription->GetVisibility(), ESlateVisibility::Visible);
		TestEqual("not the quota screen", Controller->Quota->GetVisibility(), ESlateVisibility::Collapsed);

		Flow->Step = EStationRunStep::Menu;
		Controller->Render();
		TestEqual("neither on the menu", Controller->Subscription->GetVisibility(), ESlateVisibility::Collapsed);
		TestEqual("the menu", Controller->Menu->GetVisibility(), ESlateVisibility::Visible);
		Controller->Destroy();
	});

	It("opens the plans page of the website, or goes back to the menu", [this]()
	{
		UStationSubscriptionWidget* Subscription = MakeSubscription();
		int32 Plans = 0;
		int32 Backs = 0;
		Subscription->OnOpenPlans.BindLambda([&Plans]() { ++Plans; });
		Subscription->OnBackToMenu.BindLambda([&Backs]() { ++Backs; });
		Subscription->PlansButton->OnClicked.Broadcast();
		TestEqual("the plans button", Plans, 1);
		TestEqual("not the menu", Backs, 0);
		Subscription->MenuButton->OnClicked.Broadcast();
		TestEqual("the menu button", Backs, 1);
		TestEqual("the website is Phoenix's", StationPlansUrl(TEXT("https://proyectomed.fly.dev")),
			FString(TEXT("https://proyectomed.fly.dev/planos")));
	});
}

#endif
