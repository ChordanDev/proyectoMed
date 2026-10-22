// Run flow tests. `ProyectoMed.StationRun.Unit` needs nothing else;
// `ProyectoMed.StationRun.Phoenix` needs a local Phoenix with realtime voice, the
// scripted patient and the default station (see docs/unreal-station-client.md).

#include "Misc/AutomationTest.h"
#include "Station/StationRunFlow.h"
#include "StationClient.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace StationRunTests
{
	FString PhoenixUrl()
	{
		const FString FromEnv = FPlatformMisc::GetEnvironmentVariable(TEXT("STATION_PHOENIX_URL"));
		return FromEnv.IsEmpty() ? TEXT("http://127.0.0.1:4000") : FromEnv;
	}

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
				// Removing a delegate during its broadcast destroys this lambda's
				// captures, so keep what is still needed on the stack first.
				const TFunction<void()> ThenCopy = Then;
				Flow->OnChanged.Remove(*Handle);
				ThenCopy();
			}
		});
	}
}

BEGIN_DEFINE_SPEC(FStationRunUnitSpec, "ProyectoMed.StationRun.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
END_DEFINE_SPEC(FStationRunUnitSpec)

void FStationRunUnitSpec::Define()
{
	It("formats the Station Timer as minutes and seconds", [this]()
	{
		TestEqual("start", FormatStationTimer(FTimespan::FromMinutes(10)).ToString(), TEXT("10:00"));
		TestEqual("one second gone", FormatStationTimer(FTimespan::FromSeconds(599)).ToString(), TEXT("09:59"));
		TestEqual("partial second rounds up", FormatStationTimer(FTimespan::FromSeconds(0.3)).ToString(), TEXT("00:01"));
		TestEqual("deadline", FormatStationTimer(FTimespan::Zero()).ToString(), TEXT("00:00"));
	});

	It("shows Phoenix's message only for Phoenix error statuses", [this]()
	{
		const FText Fallback = FText::FromString(TEXT("Não foi possível carregar o cenário e as tarefas da estação."));
		TestEqual("2xx body the client cannot read",
			StationErrorText(FStationClientError{200, TEXT("invalid_response"), TEXT("Phoenix answered with a body the station client does not understand.")}, Fallback).ToString(),
			Fallback.ToString());
		TestEqual("Phoenix error",
			StationErrorText(FStationClientError{422, TEXT("session_completed"), TEXT("A sessão já foi concluída.")}, Fallback).ToString(),
			TEXT("A sessão já foi concluída."));
		TestEqual("unreachable Phoenix",
			StationErrorText(FStationClientError{0, TEXT("network_error"), TEXT("Phoenix did not answer at http://127.0.0.1:4000.")}, Fallback).ToString(),
			Fallback.ToString());
		TestEqual("Phoenix error without a message",
			StationErrorText(FStationClientError{502, TEXT("http_502"), FString()}, Fallback).ToString(),
			Fallback.ToString());
	});

	It("offers a voice training only with realtime voice", [this]()
	{
		FStationSummary Station;
		Station.VoiceMode = EStationVoiceMode::Realtime;
		TestTrue("realtime", IsVoiceTrainingAvailable(Station));
		Station.VoiceMode = EStationVoiceMode::Turn;
		TestFalse("turn", IsVoiceTrainingAvailable(Station));
		Station.VoiceMode = EStationVoiceMode::Off;
		TestFalse("off", IsVoiceTrainingAvailable(Station));
	});

	It("does not start a run before the notice is acknowledged", [this]()
	{
		UStationClient* Client = NewObject<UStationClient>();
		Client->SetPhoenixBaseUrl(TEXT("http://127.0.0.1:9"));
		UStationRunFlow* Flow = NewObject<UStationRunFlow>();
		Flow->Begin(Client);

		TestEqual("starts on the notice", Flow->GetStep(), EStationRunStep::Notice);
		TestFalse("cannot enter", Flow->CanEnter(EStationTrainingMode::Text));
		Flow->Enter(EStationTrainingMode::Text);
		TestEqual("still on the notice", Flow->GetStep(), EStationRunStep::Notice);
		TestNull("no session", Client->GetSession());
	});

	It("takes no typed turn before the run is running", [this]()
	{
		UStationClient* Client = NewObject<UStationClient>();
		Client->SetPhoenixBaseUrl(TEXT("http://127.0.0.1:9"));
		UStationRunFlow* Flow = NewObject<UStationRunFlow>();
		Flow->Begin(Client);

		TestFalse("cannot send", Flow->CanSendTurn());
		TestFalse("refused", Flow->SendTypedTurn(TEXT("Bom dia")));
		TestFalse("nothing in flight", Flow->IsTurnInFlight());
		TestEqual("empty transcript", Flow->GetTranscript().Num(), 0);
	});

	It("takes no exam request before the run is running", [this]()
	{
		UStationClient* Client = NewObject<UStationClient>();
		Client->SetPhoenixBaseUrl(TEXT("http://127.0.0.1:9"));
		UStationRunFlow* Flow = NewObject<UStationRunFlow>();
		Flow->Begin(Client);

		TestFalse("cannot request", Flow->CanRequestExam());
		TestFalse("refused", Flow->RequestExam(TEXT("Exame físico")));
		TestFalse("nothing in flight", Flow->IsExamRequestInFlight());
		TestEqual("no requests", Flow->GetExamRequests().Num(), 0);
		TestEqual("nothing released", Flow->GetReleasedImpressos().Num(), 0);
	});

	It("neither finishes nor discards before the run is running", [this]()
	{
		UStationClient* Client = NewObject<UStationClient>();
		Client->SetPhoenixBaseUrl(TEXT("http://127.0.0.1:9"));
		UStationRunFlow* Flow = NewObject<UStationRunFlow>();
		Flow->Begin(Client);

		TestFalse("cannot finish", Flow->CanFinish());
		Flow->Finish();
		Flow->ExpireTimer();
		Flow->CheckStationTimer();
		TestEqual("still on the notice", Flow->GetStep(), EStationRunStep::Notice);
		TestFalse("cannot discard", Flow->CanDiscard());
		Flow->Discard();
		TestFalse("no discard", Flow->IsDiscarding());
		TestNull("no result", Flow->GetResult());
	});
}

BEGIN_DEFINE_SPEC(FStationRunPhoenixSpec, "ProyectoMed.StationRun.Phoenix",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	UStationClient* Client = nullptr;
	UStationRunFlow* Flow = nullptr;
END_DEFINE_SPEC(FStationRunPhoenixSpec)

void FStationRunPhoenixSpec::Define()
{
	using namespace StationRunTests;

	const FTimespan Timeout = FTimespan::FromSeconds(20);

	BeforeEach([this]()
	{
		Client = NewObject<UStationClient>();
		Client->AddToRoot();
		Client->SetPhoenixBaseUrl(PhoenixUrl());
		Flow = NewObject<UStationRunFlow>();
		Flow->AddToRoot();
		Flow->Begin(Client);
	});

	LatentAfterEach(Timeout, [this](const FDoneDelegate& Done)
	{
		auto Release = [this, Done]()
		{
			Flow->RemoveFromRoot();
			Client->RemoveFromRoot();
			Done.Execute();
		};
		if (!Client->GetSession())
		{
			Release();
			return;
		}
		Client->DiscardSession([Release](const TStationResult<FStationNone>&) { Release(); });
	});

	LatentIt("shows Phoenix's station on the brief once the notice is acknowledged", Timeout, [this](const FDoneDelegate& Done)
	{
		WhenFlow(Flow, [this]() { return !Flow->IsStationLoading(); }, [this, Done]()
		{
			Flow->AcknowledgeNotice();
			TestEqual("brief", Flow->GetStep(), EStationRunStep::Brief);
			if (TestNotNull(TEXT("station (is Phoenix running?)"), Flow->GetStation()))
			{
				TestFalse("title", Flow->GetStation()->DisplayTitle.IsEmpty());
				TestFalse("scenario", Flow->GetStation()->Scenario.IsEmpty());
			}
			TestTrue("can enter by text", Flow->CanEnter(EStationTrainingMode::Text));
			TestNull("no session yet", Client->GetSession());
			Done.Execute();
		});
	});

	LatentIt("starts a text training without audio consent", Timeout, [this](const FDoneDelegate& Done)
	{
		WhenFlow(Flow, [this]() { return !Flow->IsStationLoading(); }, [this, Done]()
		{
			Flow->AcknowledgeNotice();
			Flow->Enter(EStationTrainingMode::Text);
			WhenFlow(Flow, [this]() { return Flow->GetStep() == EStationRunStep::Running || !Flow->GetErrorText().IsEmpty(); },
				[this, Done]()
				{
					TestEqual("running", Flow->GetStep(), EStationRunStep::Running);
					if (TestNotNull("session", Client->GetSession()))
					{
						TestFalse("no audio consent", Client->GetSession()->bAudioConsent);
					}
					TestTrue("timer counting", Client->GetRemainingTime() > FTimespan::FromMinutes(9.5));
					TestNull("no credential", Flow->GetVoiceCredential());
					Done.Execute();
				});
		});
	});

	LatentIt("starts a voice training with audio consent and the room credential", Timeout, [this](const FDoneDelegate& Done)
	{
		WhenFlow(Flow, [this]() { return !Flow->IsStationLoading(); }, [this, Done]()
		{
			Flow->AcknowledgeNotice();
			if (!TestTrue(TEXT("voice offered (is Phoenix on VOICE_MODE=realtime?)"), Flow->CanEnter(EStationTrainingMode::Voice)))
			{
				Done.Execute();
				return;
			}
			Flow->Enter(EStationTrainingMode::Voice);
			WhenFlow(Flow, [this]() { return Flow->GetStep() == EStationRunStep::Running || !Flow->GetErrorText().IsEmpty(); },
				[this, Done]()
				{
					TestEqual("running", Flow->GetStep(), EStationRunStep::Running);
					TestFalse("no fallback", Flow->IsVoiceFallback());
					if (TestNotNull("session", Client->GetSession()) && TestNotNull("credential", Flow->GetVoiceCredential()))
					{
						TestTrue("audio consent", Client->GetSession()->bAudioConsent);
						TestEqual("room", Flow->GetVoiceCredential()->Room, TEXT("station-session-") + Client->GetSession()->SessionId);
					}
					Done.Execute();
				});
		});
	});

	// The typed-turn tests need Phoenix's scripted patient (STATION_AI_E2E_SCRIPTED_ADAPTER).
	auto ExpectTypedTurn = [this](EStationTrainingMode Mode, const FDoneDelegate& Done)
	{
		WhenFlow(Flow, [this]() { return !Flow->IsStationLoading(); }, [this, Mode, Done]()
		{
			Flow->AcknowledgeNotice();
			if (!TestTrue(TEXT("can enter (is Phoenix on VOICE_MODE=realtime?)"), Flow->CanEnter(Mode)))
			{
				Done.Execute();
				return;
			}
			Flow->Enter(Mode);
			WhenFlow(Flow, [this]() { return Flow->GetStep() == EStationRunStep::Running || !Flow->GetErrorText().IsEmpty(); },
				[this, Done]()
				{
					if (!TestTrue("can send a typed turn", Flow->CanSendTurn()))
					{
						Done.Execute();
						return;
					}
					TestFalse("blank text refused", Flow->SendTypedTurn(TEXT("   ")));
					TestTrue("accepted", Flow->SendTypedTurn(TEXT("  Bom dia, como o senhor está?  ")));
					TestTrue("in flight", Flow->IsTurnInFlight());
					TestFalse("one turn at a time", Flow->SendTypedTurn(TEXT("Mais uma")));
					WhenFlow(Flow, [this]() { return !Flow->IsTurnInFlight(); }, [this, Done]()
					{
						TestTrue(TEXT("no error (is Phoenix on STATION_AI_E2E_SCRIPTED_ADAPTER=true?)"),
							Flow->GetErrorText().IsEmpty());
						const TArray<FStationMessage>& Transcript = Flow->GetTranscript();
						if (TestEqual("learner and patient lines", Transcript.Num(), 2))
						{
							TestEqual("learner speaker", Transcript[0].Speaker, EStationSpeaker::Learner);
							TestEqual("learner text, trimmed", Transcript[0].Text, TEXT("Bom dia, como o senhor está?"));
							TestEqual("patient speaker", Transcript[1].Speaker, EStationSpeaker::Patient);
							TestEqual("approved reply", Transcript[1].Text, TEXT("Bom dia, doutor."));
						}
						// Phoenix kept the same turn: the transcript is its record, not a local guess.
						Client->RefreshSession([this, Done](const TStationResult<FStationSession>& Refreshed)
						{
							if (TestFalse("refreshed", Refreshed.HasError()))
							{
								const TArray<FStationMessage>& Kept = Refreshed.GetValue().Messages;
								if (TestEqual("Phoenix transcript", Kept.Num(), 2))
								{
									TestEqual("kept learner turn", Kept[0].Text, TEXT("Bom dia, como o senhor está?"));
									TestEqual("kept patient reply", Kept[1].Text, TEXT("Bom dia, doutor."));
								}
							}
							Done.Execute();
						});
					});
				});
		});
	};

	LatentIt("answers a typed turn in a text training, without audio consent", Timeout, [this, ExpectTypedTurn](const FDoneDelegate& Done)
	{
		ExpectTypedTurn(EStationTrainingMode::Text, Done);
	});

	LatentIt("answers a typed turn in a voice training too", Timeout, [this, ExpectTypedTurn](const FDoneDelegate& Done)
	{
		ExpectTypedTurn(EStationTrainingMode::Voice, Done);
	});

	/** Enters a text training and calls `Then` once it runs. */
	auto WhenRunning = [this](const FDoneDelegate& Done, TFunction<void()> Then)
	{
		WhenFlow(Flow, [this]() { return !Flow->IsStationLoading(); }, [this, Done, Then]()
		{
			Flow->AcknowledgeNotice();
			Flow->Enter(EStationTrainingMode::Text);
			WhenFlow(Flow, [this]() { return Flow->GetStep() == EStationRunStep::Running || !Flow->GetErrorText().IsEmpty(); },
				[this, Done, Then]()
				{
					if (TestEqual("running", Flow->GetStep(), EStationRunStep::Running))
					{
						Then();
						return;
					}
					Done.Execute();
				});
		});
	};

	LatentIt("gives a turn Phoenix refused back to the learner", Timeout, [this, WhenRunning](const FDoneDelegate& Done)
	{
		WhenRunning(Done, [this, Done]()
		{
			// Phoenix refuses turns over 2,000 characters with `message_too_long`.
			const FString TooLong = FString::ChrN(2001, TEXT('a'));
			TestTrue("accepted locally", Flow->SendTypedTurn(TooLong));
			WhenFlow(Flow, [this]() { return !Flow->IsTurnInFlight(); }, [this, Done, TooLong]()
			{
				TestFalse("Phoenix's message is shown", Flow->GetErrorText().IsEmpty());
				TestEqual("nothing joined the transcript", Flow->GetTranscript().Num(), 0);
				TestTrue("can send again", Flow->CanSendTurn());
				TestEqual("the turn comes back", Flow->TakeUnsentTurn(), TooLong);
				TestEqual("only once", Flow->TakeUnsentTurn(), FString());
				Done.Execute();
			});
		});
	});

	LatentIt("waits for Phoenix's record before the next turn after a lost answer", Timeout, [this, WhenRunning](const FDoneDelegate& Done)
	{
		WhenRunning(Done, [this, Done]()
		{
			// The run exists in Phoenix; only this client stops hearing back.
			Client->SetPhoenixBaseUrl(TEXT("http://127.0.0.1:9"));
			TestTrue("accepted locally", Flow->SendTypedTurn(TEXT("Bom dia")));
			WhenFlow(Flow, [this]() { return !Flow->IsTurnInFlight(); }, [this, Done]()
			{
				TestTrue("reloading the transcript", Flow->IsReloadingTranscript());
				TestFalse("no new turn meanwhile", Flow->CanSendTurn());
				TestFalse("refused meanwhile", Flow->SendTypedTurn(TEXT("Outra pergunta")));
				TestEqual("the turn is held until Phoenix's record is known", Flow->TakeUnsentTurn(), FString());
				WhenFlow(Flow, [this]() { return !Flow->IsReloadingTranscript(); }, [this, Done]()
				{
					TestTrue("can send again", Flow->CanSendTurn());
					TestFalse("error shown", Flow->GetErrorText().IsEmpty());
					// The record could not be read either, so the learner may resend.
					TestEqual("the turn comes back", Flow->TakeUnsentTurn(), TEXT("Bom dia"));
					Client->SetPhoenixBaseUrl(StationRunTests::PhoenixUrl());
					Done.Execute();
				});
			});
		});
	});

	// The exam tests read the default station (chest-pain-initial-assessment),
	// which authors the physical exam and an ECG and no tomography.

	/** Checks that Phoenix's own transcript of the run is still empty. */
	auto ExpectNoDialogue = [this](const FDoneDelegate& Done)
	{
		TestEqual("no line in the conversation", Flow->GetTranscript().Num(), 0);
		Client->RefreshSession([this, Done](const TStationResult<FStationSession>& Refreshed)
		{
			if (TestFalse("refreshed", Refreshed.HasError()))
			{
				TestEqual("no line in Phoenix's transcript", Refreshed.GetValue().Messages.Num(), 0);
			}
			Done.Execute();
		});
	};

	LatentIt("shows the physical exam findings Phoenix releases, without addressing the patient", Timeout,
		[this, WhenRunning, ExpectNoDialogue](const FDoneDelegate& Done)
	{
		WhenRunning(Done, [this, Done, ExpectNoDialogue]()
		{
			TestTrue("can request an exam", Flow->CanRequestExam());
			TestFalse("blank text refused", Flow->RequestExam(TEXT("   ")));
			TestTrue("accepted", Flow->RequestExam(TEXT("  Vou realizar o exame físico  ")));
			TestTrue("in flight", Flow->IsExamRequestInFlight());
			TestFalse("one request at a time", Flow->RequestExam(TEXT("Sinais vitais")));
			TestTrue("the dialogue stays open", Flow->CanSendTurn());
			WhenFlow(Flow, [this]() { return !Flow->IsExamRequestInFlight(); }, [this, Done, ExpectNoDialogue]()
			{
				TestTrue("no error", Flow->GetExamErrorText().IsEmpty());
				const TArray<FStationExamRequest>& Requests = Flow->GetExamRequests();
				if (TestEqual("one request", Requests.Num(), 1))
				{
					TestEqual("request text, trimmed", Requests[0].Text, TEXT("Vou realizar o exame físico"));
					TestEqual("released", Requests[0].Reply.Decision, EStationImpressoDecision::Released);
					TestFalse("Phoenix's feedback", Requests[0].Reply.FeedbackMessage.IsEmpty());
				}
				const TArray<FStationImpresso>& Released = Flow->GetReleasedImpressos();
				if (TestEqual("one document", Released.Num(), 1))
				{
					TestEqual("physical exam", Released[0].Category, TEXT("physical_exam"));
					TestFalse("findings", Released[0].Content.IsEmpty());
				}
				ExpectNoDialogue(Done);
			});
		});
	});

	LatentIt("shows an impresso Phoenix releases, and releases it once", Timeout,
		[this, WhenRunning, ExpectNoDialogue](const FDoneDelegate& Done)
	{
		WhenRunning(Done, [this, Done, ExpectNoDialogue]()
		{
			TestTrue("accepted", Flow->RequestExam(TEXT("Gostaria de ver o eletrocardiograma")));
			WhenFlow(Flow, [this]() { return !Flow->IsExamRequestInFlight(); }, [this, Done, ExpectNoDialogue]()
			{
				if (!TestEqual("one document", Flow->GetReleasedImpressos().Num(), 1))
				{
					Done.Execute();
					return;
				}
				const FString Id = Flow->GetReleasedImpressos()[0].Id;
				TestFalse("content", Flow->GetReleasedImpressos()[0].Content.IsEmpty());
				TestTrue("asked again", Flow->RequestExam(TEXT("Gostaria de ver o eletrocardiograma")));
				WhenFlow(Flow, [this]() { return !Flow->IsExamRequestInFlight(); }, [this, Done, ExpectNoDialogue, Id]()
				{
					const TArray<FStationExamRequest>& Requests = Flow->GetExamRequests();
					if (TestEqual("two requests", Requests.Num(), 2))
					{
						TestEqual("first released", Requests[0].Reply.Decision, EStationImpressoDecision::Released);
						TestEqual("then already released", Requests[1].Reply.Decision, EStationImpressoDecision::AlreadyReleased);
						TestEqual("nothing new", Requests[1].Reply.NewlyReleased.Num(), 0);
					}
					if (TestEqual("still one document", Flow->GetReleasedImpressos().Num(), 1))
					{
						TestEqual("same document", Flow->GetReleasedImpressos()[0].Id, Id);
					}
					ExpectNoDialogue(Done);
				});
			});
		});
	});

	LatentIt("shows a request Phoenix declines as declined, with nothing released", Timeout,
		[this, WhenRunning, ExpectNoDialogue](const FDoneDelegate& Done)
	{
		WhenRunning(Done, [this, Done, ExpectNoDialogue]()
		{
			TestTrue("accepted", Flow->RequestExam(TEXT("Solicito uma tomografia de crânio")));
			WhenFlow(Flow, [this]() { return !Flow->IsExamRequestInFlight(); }, [this, Done, ExpectNoDialogue]()
			{
				TestTrue("a decline is no error", Flow->GetExamErrorText().IsEmpty());
				const TArray<FStationExamRequest>& Requests = Flow->GetExamRequests();
				if (TestEqual("one request", Requests.Num(), 1))
				{
					TestEqual("declined", Requests[0].Reply.Decision, EStationImpressoDecision::Unavailable);
					TestEqual("nothing new", Requests[0].Reply.NewlyReleased.Num(), 0);
					TestFalse("Phoenix's feedback", Requests[0].Reply.FeedbackMessage.IsEmpty());
				}
				TestEqual("no document", Flow->GetReleasedImpressos().Num(), 0);
				ExpectNoDialogue(Done);
			});
		});
	});

	// The finish tests read the educational result, which Phoenix grades with
	// the E2E approving Jev adapter (JEV_E2E_APPROVING_ADAPTER): it cites the
	// first learner line for every criterion it can ground.
	const FTimespan ResultTimeout = FTimespan::FromSeconds(60);
	const FString Turn = TEXT("Bom dia, quando começou a dor?");

	/** Ends the running run early and calls `Then` on the feedback. */
	auto WhenFeedback = [this](const FDoneDelegate& Done, TFunction<void()> Then)
	{
		Flow->Finish();
		WhenFlow(Flow, [this]() { return Flow->GetStep() == EStationRunStep::Feedback; }, [this, Done, Then]()
		{
			if (TestNotNull(TEXT("result (is Phoenix on JEV_E2E_APPROVING_ADAPTER=true?)"), Flow->GetResult()))
			{
				Then();
				return;
			}
			Done.Execute();
		});
	};

	LatentIt("finishes early, after the turn still waiting for Phoenix, and shows the feedback with its evidence", ResultTimeout,
		[this, WhenRunning, Turn](const FDoneDelegate& Done)
	{
		WhenRunning(Done, [this, Done, Turn]()
		{
			TestTrue("can finish", Flow->CanFinish());
			TestTrue("turn accepted", Flow->SendTypedTurn(Turn));
			Flow->Finish();
			TestEqual("finishing", Flow->GetStep(), EStationRunStep::Finishing);
			TestTrue("the turn still waits for Phoenix", Flow->IsTurnInFlight());
			TestFalse("no turn after the end", Flow->CanSendTurn());
			TestFalse("turn refused", Flow->SendTypedTurn(TEXT("Mais uma pergunta")));
			TestFalse("exam refused", Flow->RequestExam(TEXT("Exame físico")));
			TestFalse("finishes once", Flow->CanFinish());
			TestFalse("no discard while grading", Flow->CanDiscard());
			WhenFlow(Flow, [this]() { return Flow->GetStep() == EStationRunStep::Feedback; }, [this, Done, Turn]()
			{
				TestTrue(TEXT("no error (is Phoenix on JEV_E2E_APPROVING_ADAPTER=true?)"), Flow->GetErrorText().IsEmpty());
				TestEqual("the turn joined the run before it ended", Flow->GetTranscript().Num(), 2);
				if (TestNotNull("session", Client->GetSession()))
				{
					TestEqual("completed", Client->GetSession()->Status, EStationSessionStatus::Completed);
					TestEqual("ended by the learner", Client->GetSession()->CompletionReason, TEXT("user"));
				}
				const FStationResult* Result = Flow->GetResult();
				if (TestNotNull("result", Result) && TestTrue("criteria", Result->Criteria.Num() > 0))
				{
					TestEqual("this run's result", Result->SessionId, Client->GetSession()->SessionId);
					const bool bCited = Result->Criteria.ContainsByPredicate([&Turn](const FStationCriterionResult& Criterion)
					{
						return Criterion.Evidence.ContainsByPredicate([&Turn](const FStationEvidence& Excerpt)
						{
							return Excerpt.Speaker == EStationSpeaker::Learner && Excerpt.Text == Turn;
						});
					});
					TestTrue("a criterion cites the learner's turn", bCited);
				}
				TestFalse("still no turn", Flow->SendTypedTurn(TEXT("Mais uma pergunta")));
				TestTrue("can discard", Flow->CanDiscard());
				Done.Execute();
			});
		});
	});

	LatentIt("keeps the run going when the timer ends it before Phoenix's deadline", Timeout,
		[this, WhenRunning](const FDoneDelegate& Done)
	{
		WhenRunning(Done, [this, Done]()
		{
			// The local timer has not run out: Phoenix refuses a timer finish this early.
			Flow->ExpireTimer();
			TestEqual("finishing", Flow->GetStep(), EStationRunStep::Finishing);
			WhenFlow(Flow, [this]() { return Flow->GetStep() != EStationRunStep::Finishing; }, [this, Done]()
			{
				TestEqual("running again", Flow->GetStep(), EStationRunStep::Running);
				TestTrue("no error shown", Flow->GetErrorText().IsEmpty());
				TestTrue("can send a turn", Flow->CanSendTurn());
				if (TestNotNull("session", Client->GetSession()))
				{
					TestEqual("still active", Client->GetSession()->Status, EStationSessionStatus::Active);
				}
				Flow->CheckStationTimer();
				TestEqual("the timer has time left", Flow->GetStep(), EStationRunStep::Running);
				Done.Execute();
			});
		});
	});

	LatentIt("discards the run only once Phoenix confirms, then offers a new run", ResultTimeout,
		[this, WhenRunning, WhenFeedback](const FDoneDelegate& Done)
	{
		WhenRunning(Done, [this, Done, WhenFeedback]()
		{
			WhenFeedback(Done, [this, Done]()
			{
				// Phoenix stops answering: the run stays, and so does its feedback.
				Client->SetPhoenixBaseUrl(TEXT("http://127.0.0.1:9"));
				Flow->Discard();
				TestTrue("discarding", Flow->IsDiscarding());
				TestFalse("one discard at a time", Flow->CanDiscard());
				WhenFlow(Flow, [this]() { return !Flow->IsDiscarding(); }, [this, Done]()
				{
					Client->SetPhoenixBaseUrl(StationRunTests::PhoenixUrl());
					TestEqual("still on the feedback", Flow->GetStep(), EStationRunStep::Feedback);
					TestFalse("error shown", Flow->GetErrorText().IsEmpty());
					TestNotNull("session kept", Client->GetSession());
					TestNotNull("feedback kept", Flow->GetResult());
					TestFalse("no new run", Flow->CanEnter(EStationTrainingMode::Text));

					Flow->Discard();
					TestNotNull("session kept until Phoenix confirms", Client->GetSession());
					WhenFlow(Flow, [this]() { return !Flow->IsDiscarding(); }, [this, Done]()
					{
						TestEqual("brief", Flow->GetStep(), EStationRunStep::Brief);
						TestTrue("error cleared", Flow->GetErrorText().IsEmpty());
						TestNull("session forgotten", Client->GetSession());
						TestNull("feedback forgotten", Flow->GetResult());
						TestEqual("transcript forgotten", Flow->GetTranscript().Num(), 0);
						TestTrue("can start a new run", Flow->CanEnter(EStationTrainingMode::Text));
						Done.Execute();
					});
				});
			});
		});
	});

	LatentIt("shows why the feedback is missing when the run cannot be closed, and still discards it", Timeout,
		[this, WhenRunning](const FDoneDelegate& Done)
	{
		WhenRunning(Done, [this, Done]()
		{
			Client->SetPhoenixBaseUrl(TEXT("http://127.0.0.1:9"));
			Flow->Finish();
			WhenFlow(Flow, [this]() { return Flow->GetStep() == EStationRunStep::Feedback; }, [this, Done]()
			{
				Client->SetPhoenixBaseUrl(StationRunTests::PhoenixUrl());
				TestFalse("error shown", Flow->GetErrorText().IsEmpty());
				TestNull("no result", Flow->GetResult());
				TestFalse("no turn", Flow->CanSendTurn());
				Flow->Discard();
				WhenFlow(Flow, [this]() { return !Flow->IsDiscarding(); }, [this, Done]()
				{
					TestEqual("brief", Flow->GetStep(), EStationRunStep::Brief);
					TestNull("session forgotten", Client->GetSession());
					Done.Execute();
				});
			});
		});
	});

	LatentIt("gives an exam request Phoenix did not answer back to the learner", Timeout,
		[this, WhenRunning](const FDoneDelegate& Done)
	{
		WhenRunning(Done, [this, Done]()
		{
			Client->SetPhoenixBaseUrl(TEXT("http://127.0.0.1:9"));
			TestTrue("accepted locally", Flow->RequestExam(TEXT("Exame físico")));
			WhenFlow(Flow, [this]() { return !Flow->IsExamRequestInFlight(); }, [this, Done]()
			{
				Client->SetPhoenixBaseUrl(StationRunTests::PhoenixUrl());
				TestFalse("error shown", Flow->GetExamErrorText().IsEmpty());
				TestTrue("the conversation shows no error", Flow->GetErrorText().IsEmpty());
				TestEqual("no answered request", Flow->GetExamRequests().Num(), 0);
				TestEqual("no document", Flow->GetReleasedImpressos().Num(), 0);
				TestTrue("can request again", Flow->CanRequestExam());
				TestEqual("the request comes back", Flow->TakeUnsentExamRequest(), TEXT("Exame físico"));
				TestEqual("only once", Flow->TakeUnsentExamRequest(), FString());
				TestTrue("resent", Flow->RequestExam(TEXT("Exame físico")));
				WhenFlow(Flow, [this]() { return !Flow->IsExamRequestInFlight(); }, [this, Done]()
				{
					TestTrue("error cleared", Flow->GetExamErrorText().IsEmpty());
					TestEqual("released on the retry", Flow->GetReleasedImpressos().Num(), 1);
					Done.Execute();
				});
			});
		});
	});
}

#endif // WITH_DEV_AUTOMATION_TESTS
