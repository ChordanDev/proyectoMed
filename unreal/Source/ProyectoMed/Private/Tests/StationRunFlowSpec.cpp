// Run flow tests. `ProyectoMed.StationRun.Unit` needs nothing else;
// `ProyectoMed.StationRun.Phoenix` needs a local Phoenix with realtime voice
// (see docs/unreal-station-client.md).

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
}

#endif // WITH_DEV_AUTOMATION_TESTS
