// Run flow tests. `ProyectoMed.StationRun.Unit` needs nothing else;
// `ProyectoMed.StationRun.Phoenix` needs a local Phoenix with realtime voice and
// the scripted patient (see docs/unreal-station-client.md).

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
}

#endif // WITH_DEV_AUTOMATION_TESTS
