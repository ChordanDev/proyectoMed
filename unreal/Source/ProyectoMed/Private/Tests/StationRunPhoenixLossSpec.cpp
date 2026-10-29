// Run flow tests for a training that loses Phoenix (#196), against a fake Phoenix
// served in-process: it can leave a call unanswered (a gateway's 503) while it still
// answers the check that follows, which a real Phoenix cannot be made to do. It also
// holds a typed turn's reply for as long as a test needs, to check when the patient's
// voice of that reply may play (#325).
// `http://127.0.0.1:9` stands for a Phoenix that answers nothing at all.

#include "Containers/Ticker.h"
#include "HttpPath.h"
#include "HttpRouteHandle.h"
#include "HttpServerModule.h"
#include "HttpServerRequest.h"
#include "HttpServerResponse.h"
#include "IHttpRouter.h"
#include "Misc/AutomationTest.h"
#include "Station/StationRunFlow.h"
#include "StationClient.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace StationPhoenixLoss
{
	constexpr uint32 Port = 18766;
	const TCHAR* SessionsPath = TEXT("/api/stations/active/sessions");
	const TCHAR* SessionPath = TEXT("/api/stations/active/sessions/stub-session");
	const TCHAR* Unreachable = TEXT("http://127.0.0.1:9");

	const TCHAR* SessionBody = TEXT(R"({
		"session_id": "stub-session", "station_id": "s", "station_version": "1", "audio_consent": true,
		"started_at": "2026-10-27T12:00:00Z", "expires_at": "2026-10-27T12:30:00Z",
		"deadline_at": "2026-10-27T12:10:00Z", "server_now": "2026-10-27T12:00:00Z"
	})");

	const TCHAR* ShowBody = TEXT(R"({
		"session_id": "stub-session", "station_id": "s", "station_version": "1", "audio_consent": true,
		"started_at": "2026-10-27T12:00:00Z", "expires_at": "2026-10-27T12:30:00Z",
		"deadline_at": "2026-10-27T12:10:00Z", "status": "active", "completion_reason": null,
		"messages": [], "server_now": "2026-10-27T12:01:00Z"
	})");

	const TCHAR* FinishBody = TEXT(R"({
		"session_id": "stub-session", "status": "completed", "completed_at": "2026-10-27T12:05:00Z",
		"completion_reason": "user", "deadline_at": "2026-10-27T12:10:00Z", "server_now": "2026-10-27T12:05:00Z"
	})");

	const TCHAR* TypedReplyBody = TEXT(R"({"outcome": "patient_reply", "reply_text": "Dói aqui.", "reply_audio_url": null})");

	const TCHAR* ResultPath = TEXT("/api/v2/stations/active/sessions/stub-session/result");

	const TCHAR* ResultBody = TEXT(R"({
		"schema_version": "2", "session_id": "stub-session", "status": "completed", "placeholder": false,
		"criteria": [], "coverage": {"assessed": 0, "uncertain": 0, "not_observable": 0, "not_applicable": 0},
		"estimates": {"total": null, "scored_subtotal": "0", "scored_max": "0", "eligible_max": "0", "unresolved": []}
	})");

	/** Routes on a local port that answer with a fixed status and body after a delay. */
	class FServer
	{
	public:
		void Start()
		{
			Router = FHttpServerModule::Get().GetHttpRouter(Port, /*bFailOnBindFailure*/ true);
			FHttpServerModule::Get().StartAllListeners();
		}

		bool IsListening() const { return Router.IsValid(); }

		/** An empty `Body` with 503 is a gateway answering for a Phoenix that did not. */
		void Route(const FString& Path, EHttpServerRequestVerbs Verb, EHttpServerResponseCodes Code, const FString& Body,
			float DelaySeconds = 0.f)
		{
			TSharedRef<TArray<FString>> Received = Requests;
			Handles.Add(Router->BindRoute(FHttpPath(Path), Verb,
				FHttpRequestHandler::CreateLambda([Code, Body, DelaySeconds, Received, Path](const FHttpServerRequest& Request,
					const FHttpResultCallback& OnComplete)
				{
					FUTF8ToTCHAR Converted(reinterpret_cast<const ANSICHAR*>(Request.Body.GetData()), Request.Body.Num());
					Received->Add(Path + TEXT(" ") + FString(Converted.Length(), Converted.Get()));
					const FHttpResultCallback Complete = OnComplete;
					auto Respond = [Complete, Code, Body]()
					{
						TUniquePtr<FHttpServerResponse> Response = FHttpServerResponse::Create(Body, TEXT("application/json"));
						Response->Code = Code;
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

		/** Every request received, as `<path> <body>`, in order. */
		const TArray<FString>& GetRequests() const { return *Requests; }

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
			Requests->Reset();
		}

	private:
		TSharedPtr<IHttpRouter> Router;
		TArray<FHttpRouteHandle> Handles;
		TSharedRef<TArray<FString>> Requests = MakeShared<TArray<FString>>();
	};

	/** Calls `Then` once, the first time `Condition` holds after a flow change (or right away). */
	void WhenFlow(UStationRunFlow* Flow, TFunction<bool()> Condition, TFunction<void()> Then)
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

	/** Calls `Then` after `Seconds`, for answers that change nothing the flow broadcasts. */
	void After(float Seconds, TFunction<void()> Then)
	{
		FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([Then](float) { Then(); return false; }), Seconds);
	}
}

BEGIN_DEFINE_SPEC(FStationRunPhoenixLossSpec, "ProyectoMed.StationRun.Unit.PhoenixLoss",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	UStationClient* Client = nullptr;
	UStationRunFlow* Flow = nullptr;
	StationPhoenixLoss::FServer Server;
	TSharedPtr<int32> Silenced;
	TSharedPtr<int32> Resumed;

	/** The fake Phoenix stops answering anything at all. */
	void LosePhoenix() { Client->SetPhoenixBaseUrl(StationPhoenixLoss::Unreachable); }

	/** Phoenix answers the check that follows a call it left unanswered. */
	void AnswerChecks()
	{
		Server.Route(StationPhoenixLoss::SessionPath, EHttpServerRequestVerbs::VERB_GET, EHttpServerResponseCodes::Ok,
			StationPhoenixLoss::ShowBody);
	}

	void ExpectInvalidated()
	{
		TestEqual("invalidated", Flow->GetStep(), EStationRunStep::Invalidated);
		TestNull("no feedback", Flow->GetResult());
		TestEqual("no partial conversation", Flow->GetTranscript().Num(), 0);
		TestEqual("no exam request kept", Flow->GetExamRequests().Num(), 0);
		TestFalse("no turn", Flow->CanSendTurn());
		TestFalse("no exam request", Flow->CanRequestExam());
		TestFalse("no finish", Flow->CanFinish());
		TestFalse("no discard", Flow->CanDiscard());
		TestTrue("can restart", Flow->CanRestart());
		TestTrue("the patient is silenced", *Silenced > 0);
		TestNull("the room is left", Client->GetVoice());
	}
END_DEFINE_SPEC(FStationRunPhoenixLossSpec)

void FStationRunPhoenixLossSpec::Define()
{
	using namespace StationPhoenixLoss;

	const FTimespan Timeout = FTimespan::FromSeconds(20);

	BeforeEach([this]()
	{
		Server.Start();
		TestTrue("fake Phoenix listening", Server.IsListening());
		Server.Route(SessionsPath, EHttpServerRequestVerbs::VERB_POST, EHttpServerResponseCodes::Ok, SessionBody);
		Client = NewObject<UStationClient>();
		Client->AddToRoot();
		Client->SetPhoenixBaseUrl(FString::Printf(TEXT("http://127.0.0.1:%u"), Port));
		Flow = NewObject<UStationRunFlow>();
		Flow->AddToRoot();
		Silenced = MakeShared<int32>(0);
		Resumed = MakeShared<int32>(0);
		FStationPatientOutput Patient;
		Patient.Silence = [Count = Silenced]() { ++*Count; };
		Patient.Resume = [Count = Resumed]() { ++*Count; };
		Flow->SetPatientOutput(MoveTemp(Patient));
	});

	// A running training of the stub session, as `Enter` leaves it.
	LatentBeforeEach(Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(true, [this, Done](const TStationResult<FStationSession>& Started)
		{
			TestFalse("started", Started.HasError());
			Flow->Client = Client;
			FStationSummary Station;
			Station.VoiceMode = EStationVoiceMode::Realtime;
			Flow->Station = Station;
			Flow->Mode = EStationTrainingMode::Voice;
			Flow->Step = EStationRunStep::Running;
			Done.Execute();
		});
	});

	AfterEach([this]()
	{
		Flow->RemoveFromRoot();
		Client->RemoveFromRoot();
		Server.Stop();
	});

	LatentIt("invalidates the run when a typed turn and the check after it go unanswered", Timeout,
		[this](const FDoneDelegate& Done)
	{
		LosePhoenix();
		TestTrue("accepted locally", Flow->SendTypedTurn(TEXT("Bom dia")));
		WhenFlow(Flow, [this]() { return Flow->GetStep() != EStationRunStep::Running || (!Flow->IsTurnInFlight() && !Flow->IsReloadingTranscript()); },
			[this, Done]()
			{
				ExpectInvalidated();
				TestTrue("no error under the conversation", Flow->GetErrorText().IsEmpty());
				TestEqual("no turn to give back", Flow->TakeUnsentTurn(), FString());

				// Whatever the room still delivers neither shows nor plays.
				FStationVoiceEvent Late;
				Late.Kind = EStationVoiceEventKind::PatientText;
				Late.TurnId = 1;
				Late.Text = TEXT("Dói aqui.");
				Flow->HandleVoiceEvent(Late);
				TestEqual("the patient stays silent", *Resumed, 0);
				TestTrue("no reply shown", Flow->GetVoice().PatientText.IsEmpty());
				TestEqual("nothing joins the conversation", Flow->GetTranscript().Num(), 0);
				Done.Execute();
			});
	});

	LatentIt("keeps the run going when Phoenix answers the check after an unanswered turn", Timeout,
		[this](const FDoneDelegate& Done)
	{
		Server.Route(FString(SessionPath) + TEXT("/messages"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::ServiceUnavail, FString());
		AnswerChecks();
		TestTrue("accepted locally", Flow->SendTypedTurn(TEXT("Bom dia")));
		WhenFlow(Flow, [this]() { return !Flow->IsTurnInFlight() && !Flow->IsReloadingTranscript(); }, [this, Done]()
		{
			TestEqual("still running", Flow->GetStep(), EStationRunStep::Running);
			TestFalse("error shown", Flow->GetErrorText().IsEmpty());
			TestTrue("can send again", Flow->CanSendTurn());
			// Phoenix's record has no such turn, so the learner may send it again.
			TestEqual("the turn comes back", Flow->TakeUnsentTurn(), TEXT("Bom dia"));
			Done.Execute();
		});
	});

	// #325: the voice worker also speaks a typed turn's reply. Once the learner spoke
	// over the patient, its voice stays silent until a newer reply (#193): the typed
	// turn's reply is one, unless the learner spoke again while it was on its way.
	auto LearnerSpeaks = [](int32 TurnId, const TCHAR* Text, bool bFinal = false)
	{
		FStationVoiceEvent Event;
		Event.Kind = EStationVoiceEventKind::Learner;
		Event.TurnId = TurnId;
		Event.Text = Text;
		Event.bFinal = bFinal;
		return Event;
	};

	LatentIt("lets the patient speak a typed turn's reply after the learner spoke over it", Timeout,
		[this, LearnerSpeaks](const FDoneDelegate& Done)
	{
		Server.Route(FString(SessionPath) + TEXT("/messages"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::Ok, TypedReplyBody);
		Flow->HandleVoiceEvent(LearnerSpeaks(1, TEXT("Espera")));
		Flow->HandleVoiceEvent(LearnerSpeaks(1, TEXT("Espera, vou examinar."), true));
		FStationVoiceEvent Noted;
		Noted.Kind = EStationVoiceEventKind::ExaminerAcknowledged;
		Noted.TurnId = 1;
		Flow->HandleVoiceEvent(Noted);
		TestEqual("the patient is silenced", *Silenced, 1);

		TestTrue("accepted locally", Flow->SendTypedTurn(TEXT("Onde dói?")));
		WhenFlow(Flow, [this]() { return !Flow->IsTurnInFlight(); }, [this, Done]()
		{
			TestEqual("the reply's voice may play", *Resumed, 1);
			const TArray<FStationMessage>& Lines = Flow->GetTranscript();
			if (TestEqual("both turns", Lines.Num(), 3))
			{
				TestEqual("the reply is shown", Lines[2].Text, TEXT("Dói aqui."));
			}
			Done.Execute();
		});
	});

	LatentIt("keeps the patient silent when the learner speaks again before a typed turn's reply arrives", Timeout,
		[this, LearnerSpeaks](const FDoneDelegate& Done)
	{
		Server.Route(FString(SessionPath) + TEXT("/messages"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::Ok, TypedReplyBody, /*DelaySeconds*/ 0.5f);
		TestTrue("accepted locally", Flow->SendTypedTurn(TEXT("Onde dói?")));
		Flow->HandleVoiceEvent(LearnerSpeaks(1, TEXT("Espera")));
		TestEqual("the patient is silenced", *Silenced, 1);

		WhenFlow(Flow, [this]() { return !Flow->IsTurnInFlight(); }, [this, Done]()
		{
			// The worker never speaks that reply now; nothing stale may play either.
			TestEqual("the patient stays silent", *Resumed, 0);
			const TArray<FStationMessage>& Lines = Flow->GetTranscript();
			if (TestEqual("the typed turn and its reply", Lines.Num(), 2))
			{
				TestEqual("the reply is still shown", Lines[1].Text, TEXT("Dói aqui."));
			}
			Done.Execute();
		});
	});

	LatentIt("invalidates the run when an exam request and the check after it go unanswered", Timeout,
		[this](const FDoneDelegate& Done)
	{
		LosePhoenix();
		TestTrue("accepted locally", Flow->RequestExam(TEXT("Exame físico")));
		WhenFlow(Flow, [this]() { return Flow->GetStep() == EStationRunStep::Invalidated; }, [this, Done]()
		{
			ExpectInvalidated();
			TestTrue("no exam error", Flow->GetExamErrorText().IsEmpty());
			TestEqual("no request to give back", Flow->TakeUnsentExamRequest(), FString());
			Done.Execute();
		});
	});

	LatentIt("gives an exam request back, with its id, when Phoenix answers the check after leaving it unanswered", Timeout,
		[this](const FDoneDelegate& Done)
	{
		const FString RequestPath = FString(SessionPath) + TEXT("/impressos/request");
		Server.Route(RequestPath, EHttpServerRequestVerbs::VERB_POST, EHttpServerResponseCodes::ServiceUnavail, FString());
		AnswerChecks();
		TestTrue("accepted locally", Flow->RequestExam(TEXT("Exame físico")));
		WhenFlow(Flow, [this]() { return !Flow->IsExamRequestInFlight(); }, [this, Done, RequestPath]()
		{
			After(1.f, [this, Done, RequestPath]()
			{
				TestEqual("still running", Flow->GetStep(), EStationRunStep::Running);
				TestFalse("error shown", Flow->GetExamErrorText().IsEmpty());
				TestTrue("can request again", Flow->CanRequestExam());
				TestEqual("the request comes back", Flow->TakeUnsentExamRequest(), TEXT("Exame físico"));
				TestTrue("resent", Flow->RequestExam(TEXT("Exame físico")));
				WhenFlow(Flow, [this]() { return !Flow->IsExamRequestInFlight(); }, [this, Done, RequestPath]()
				{
					TArray<FString> Sent = Server.GetRequests().FilterByPredicate(
						[&RequestPath](const FString& Line) { return Line.StartsWith(RequestPath); });
					if (TestEqual("two requests", Sent.Num(), 2))
					{
						// Phoenix may have recorded the first: the same id lets it answer that one.
						TestEqual("the retry reuses the id", Sent[1], Sent[0]);
					}
					Done.Execute();
				});
			});
		});
	});

	LatentIt("invalidates the run, with no feedback, when its finish and the check after it go unanswered", Timeout,
		[this](const FDoneDelegate& Done)
	{
		LosePhoenix();
		Flow->Finish();
		WhenFlow(Flow, [this]() { return Flow->GetStep() != EStationRunStep::Finishing; }, [this, Done]()
		{
			ExpectInvalidated();
			TestTrue("no error shown", Flow->GetErrorText().IsEmpty());
			Done.Execute();
		});
	});

	LatentIt("invalidates the run, with no feedback, when its result and the check after it go unanswered", Timeout,
		[this](const FDoneDelegate& Done)
	{
		Server.Route(FString(SessionPath) + TEXT("/finish"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::Ok, FinishBody);
		Server.Route(ResultPath, EHttpServerRequestVerbs::VERB_GET, EHttpServerResponseCodes::ServiceUnavail, FString());
		Server.Route(SessionPath, EHttpServerRequestVerbs::VERB_GET, EHttpServerResponseCodes::ServiceUnavail, FString());
		Flow->Finish();
		WhenFlow(Flow, [this]() { return Flow->GetStep() != EStationRunStep::Finishing; }, [this, Done]()
		{
			ExpectInvalidated();
			Done.Execute();
		});
	});

	LatentIt("keeps the feedback when a check started during the run goes unanswered after it", Timeout,
		[this](const FDoneDelegate& Done)
	{
		// The exam request's check is slow; the finish and the result are answered meanwhile.
		Server.Route(FString(SessionPath) + TEXT("/impressos/request"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::ServiceUnavail, FString());
		Server.Route(SessionPath, EHttpServerRequestVerbs::VERB_GET, EHttpServerResponseCodes::ServiceUnavail, FString(), 2.f);
		Server.Route(FString(SessionPath) + TEXT("/finish"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::Ok, FinishBody);
		Server.Route(ResultPath, EHttpServerRequestVerbs::VERB_GET, EHttpServerResponseCodes::Ok, ResultBody);
		TestTrue("exam accepted", Flow->RequestExam(TEXT("Exame físico")));
		WhenFlow(Flow, [this]() { return !Flow->IsExamRequestInFlight(); }, [this, Done]()
		{
			Flow->Finish();
			WhenFlow(Flow, [this]() { return Flow->GetStep() != EStationRunStep::Finishing; }, [this, Done]()
			{
				TestEqual("feedback", Flow->GetStep(), EStationRunStep::Feedback);
				After(2.5f, [this, Done]()
				{
					TestEqual("still on the feedback", Flow->GetStep(), EStationRunStep::Feedback);
					TestNotNull("result kept", Flow->GetResult());
					Done.Execute();
				});
			});
		});
	});

	LatentIt("shows why the feedback is missing when Phoenix refuses to close the run, and still discards it", Timeout,
		[this](const FDoneDelegate& Done)
	{
		// Phoenix answers, with an error of its own: the run is over, not lost.
		Server.Route(FString(SessionPath) + TEXT("/finish"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::ServerError, TEXT(R"({"error": "internal_error", "message": "Erro interno."})"));
		Server.Route(FString(SessionPath) + TEXT("/discard"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::Ok, TEXT("{}"));
		Flow->Finish();
		WhenFlow(Flow, [this]() { return Flow->GetStep() != EStationRunStep::Finishing; }, [this, Done]()
		{
			TestEqual("feedback", Flow->GetStep(), EStationRunStep::Feedback);
			TestEqual("Phoenix's message is shown", Flow->GetErrorText().ToString(), FString(TEXT("Erro interno.")));
			TestNull("no result", Flow->GetResult());
			TestFalse("no restart", Flow->CanRestart());
			Flow->Discard();
			WhenFlow(Flow, [this]() { return !Flow->IsDiscarding(); }, [this, Done]()
			{
				TestEqual("back on the menu (#421)", Flow->GetStep(), EStationRunStep::Menu);
				TestNull("session forgotten", Client->GetSession());
				Done.Execute();
			});
		});
	});

	LatentIt("keeps a voice training going in writing when the transcription fails", Timeout,
		[this](const FDoneDelegate& Done)
	{
		AnswerChecks();
		FStationVoiceEvent Fatal;
		Fatal.Kind = EStationVoiceEventKind::Fatal;
		Fatal.Failure = TEXT("timeout");
		Flow->HandleVoiceEvent(Fatal);
		TestTrue("the voice is lost", Flow->GetVoice().bLost);
		After(1.f, [this, Done]()
		{
			TestEqual("still running", Flow->GetStep(), EStationRunStep::Running);
			TestTrue("typed turns go on", Flow->CanSendTurn());
			TestTrue("exam requests go on", Flow->CanRequestExam());
			Flow->ReportMicrophoneUnavailable();
			TestEqual("a microphone failure keeps it running too", Flow->GetStep(), EStationRunStep::Running);
			Done.Execute();
		});
	});

	LatentIt("invalidates a voice training when the voice fails and Phoenix does not answer either", Timeout,
		[this](const FDoneDelegate& Done)
	{
		LosePhoenix();
		Flow->HandleVoiceState(EStationVoiceState::Failed);
		TestTrue("the voice is lost", Flow->GetVoice().bLost);
		WhenFlow(Flow, [this]() { return Flow->GetStep() == EStationRunStep::Invalidated; }, [this, Done]()
		{
			ExpectInvalidated();
			Done.Execute();
		});
	});

	LatentIt("restarts an invalidated run from the brief, and drops what Phoenix answers for it late", Timeout,
		[this](const FDoneDelegate& Done)
	{
		// The turn's answer arrives after the run was invalidated and restarted.
		Server.Route(FString(SessionPath) + TEXT("/messages"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::Ok, TEXT(R"({"reply_text": "Pois não."})"), 1.5f);
		Server.Route(FString(SessionPath) + TEXT("/impressos/request"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::ServiceUnavail, FString());
		Server.Route(SessionPath, EHttpServerRequestVerbs::VERB_GET, EHttpServerResponseCodes::ServiceUnavail, FString());
		Server.Route(FString(SessionPath) + TEXT("/discard"), EHttpServerRequestVerbs::VERB_POST,
			EHttpServerResponseCodes::Ok, TEXT("{}"));
		TestTrue("turn accepted", Flow->SendTypedTurn(TEXT("Bom dia")));
		TestTrue("exam accepted", Flow->RequestExam(TEXT("Exame físico")));
		WhenFlow(Flow, [this]() { return Flow->GetStep() == EStationRunStep::Invalidated; }, [this, Done]()
		{
			TestFalse("no turn waits for Phoenix", Flow->IsTurnInFlight());
			Flow->Restart();
			TestEqual("brief", Flow->GetStep(), EStationRunStep::Brief);
			TestNull("session forgotten", Client->GetSession());
			TestTrue("can start a new run", Flow->CanEnter(EStationTrainingMode::Text));
			After(2.5f, [this, Done]()
			{
				TestEqual("still on the brief", Flow->GetStep(), EStationRunStep::Brief);
				TestEqual("the late reply is dropped", Flow->GetTranscript().Num(), 0);
				TestTrue("no error", Flow->GetErrorText().IsEmpty());
				TestTrue("Phoenix was asked to forget the run",
					Server.GetRequests().ContainsByPredicate([](const FString& Line) { return Line.Contains(TEXT("/discard")); }));
				Done.Execute();
			});
		});
	});
}

#endif // WITH_DEV_AUTOMATION_TESTS
