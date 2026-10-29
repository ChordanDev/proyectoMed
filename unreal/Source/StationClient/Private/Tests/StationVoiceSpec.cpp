// Voice link tests. `ProyectoMed.StationVoice.Unit` needs nothing else;
// `ProyectoMed.StationVoice.Stack` needs the local voice stack, started by
// scripts/run-voice-stack.sh with its default transcript and patient reply (see
// docs/unreal-station-client.md):
//   scripts/run-voice-stack.sh -- scripts/run-unreal-tests.sh ProyectoMed.StationVoice.Stack

#include "Containers/Ticker.h"
#include "Misc/AutomationTest.h"
#include "StationClient.h"
#include "StationLiveKit.h"
#include "StationPcm.h"
#include "StationVoiceLiveness.h"
#include "StationWorkerPresence.h"

THIRD_PARTY_INCLUDES_START
#include "livekit/livekit.h"
THIRD_PARTY_INCLUDES_END
#include "StationVoice.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace StationVoiceTests
{
	TOptional<FStationVoiceEvent> Parse(const FString& Json, const FString& SessionId = TEXT("s1"))
	{
		const FTCHARToUTF8 Utf8(*Json);
		return ParseStationVoiceEvent(TConstArrayView<uint8>(reinterpret_cast<const uint8*>(Utf8.Get()), Utf8.Length()), SessionId);
	}

	FString PhoenixUrl()
	{
		const FString FromEnv = FPlatformMisc::GetEnvironmentVariable(TEXT("STATION_PHOENIX_URL"));
		return FromEnv.IsEmpty() ? TEXT("http://127.0.0.1:4000") : FromEnv;
	}

	// The voice stack's defaults (scripts/run-voice-stack.sh).
	const TCHAR* StackTranscript = TEXT("Qual é o seu nome?");
	const TCHAR* StackPatientReply = TEXT("Meu nome é Carlos.");

	/** Seconds of tone the fake speech provider plays for `Text` (voice-worker/fake_providers.py). */
	double FakeToneSeconds(const FString& Text)
	{
		return FMath::Clamp(Text.TrimStartAndEnd().Len() * 0.08, 0.4, 3.0);
	}

	/**
	 * 10 ms of a spoken-like sound at 48 kHz: a 150 Hz voice with harmonics under a
	 * 4 Hz syllable envelope, or silence. `Index` counts 10 ms chunks.
	 */
	TArray<float> SpeechChunk(int32 Index, bool bVoiced)
	{
		TArray<float> Chunk;
		Chunk.SetNumZeroed(FStationPcmFramer::FrameSamples);
		if (!bVoiced)
		{
			return Chunk;
		}
		for (int32 i = 0; i < Chunk.Num(); ++i)
		{
			const double T = (Index * Chunk.Num() + i) / double(FStationPcmFramer::SampleRate);
			const double Envelope = 0.6 + 0.4 * FMath::Sin(2.0 * PI * 4.0 * T);
			double Voice = 0.0;
			for (int32 Harmonic = 1; Harmonic <= 6; ++Harmonic)
			{
				Voice += FMath::Sin(2.0 * PI * 150.0 * Harmonic * T) / Harmonic;
			}
			Chunk[i] = static_cast<float>(0.3 * Envelope * Voice);
		}
		return Chunk;
	}

	TArray<TArray<int16>> Frames(FStationPcmFramer& Framer, const TArray<float>& Samples, int32 Rate, int32 Channels)
	{
		TArray<TArray<int16>> Out;
		Framer.Push(Samples, Rate, Channels, [&Out](TConstArrayView<int16> Frame) { Out.Emplace(Frame); });
		return Out;
	}
}

BEGIN_DEFINE_SPEC(FStationVoiceUnitSpec, "ProyectoMed.StationVoice.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
END_DEFINE_SPEC(FStationVoiceUnitSpec)

void FStationVoiceUnitSpec::Define()
{
	using namespace StationVoiceTests;

	Describe("ParseStationVoiceEvent", [this]()
	{
		It("reads the learner's interim caption and final transcript", [this]()
		{
			const TOptional<FStationVoiceEvent> Interim = Parse(TEXT(R"({"session_id":"s1","turn_id":3,"final":false,"text":"Qual"})"));
			if (TestTrue("interim", Interim.IsSet()))
			{
				TestEqual("kind", Interim->Kind, EStationVoiceEventKind::Learner);
				TestEqual("turn", Interim->TurnId, 3);
				TestFalse("not final", Interim->bFinal);
				TestEqual("text", Interim->Text, TEXT("Qual"));
			}
			const TOptional<FStationVoiceEvent> Final = Parse(TEXT(R"({"session_id":"s1","turn_id":3,"final":true,"text":"Qual é o seu nome?"})"));
			if (TestTrue("final", Final.IsSet()))
			{
				TestTrue("is final", Final->bFinal);
				TestEqual("text", Final->Text, TEXT("Qual é o seu nome?"));
			}
			TestTrue("blank interim kept", Parse(TEXT(R"({"session_id":"s1","turn_id":3,"final":false,"text":""})")).IsSet());
			TestFalse("blank final dropped", Parse(TEXT(R"({"session_id":"s1","turn_id":3,"final":true,"text":"  "})")).IsSet());
			TestFalse("final not a boolean", Parse(TEXT(R"({"session_id":"s1","turn_id":3,"final":"yes","text":"Oi"})")).IsSet());
		});

		It("reads the patient's sentences and the end of the reply", [this]()
		{
			const TOptional<FStationVoiceEvent> Sentence = Parse(TEXT(R"({"session_id":"s1","turn_id":3,"generation_id":1,"role":"patient","text":"Meu nome é Carlos.","segment":0})"));
			if (TestTrue("sentence", Sentence.IsSet()))
			{
				TestEqual("kind", Sentence->Kind, EStationVoiceEventKind::PatientText);
				TestEqual("text", Sentence->Text, TEXT("Meu nome é Carlos."));
				TestEqual("segment", Sentence->Segment, 0);
			}
			const TOptional<FStationVoiceEvent> Whole = Parse(TEXT(R"({"session_id":"s1","turn_id":3,"role":"patient","text":"Não consta no script."})"));
			if (TestTrue("unsegmented reply", Whole.IsSet()))
			{
				TestEqual("no segment", Whole->Segment, INDEX_NONE);
			}
			const TOptional<FStationVoiceEvent> Complete = Parse(TEXT(R"({"session_id":"s1","turn_id":3,"role":"patient","status":"complete"})"));
			if (TestTrue("complete", Complete.IsSet()))
			{
				TestEqual("kind", Complete->Kind, EStationVoiceEventKind::PatientComplete);
				TestTrue("no text", Complete->Text.IsEmpty());
			}
			TestFalse("blank sentence", Parse(TEXT(R"({"session_id":"s1","turn_id":3,"role":"patient","text":" "})")).IsSet());
			TestFalse("negative segment", Parse(TEXT(R"({"session_id":"s1","turn_id":3,"role":"patient","text":"Oi","segment":-1})")).IsSet());
			TestFalse("fractional segment", Parse(TEXT(R"({"session_id":"s1","turn_id":3,"role":"patient","text":"Oi","segment":1.5})")).IsSet());
		});

		It("reads the examiner's kept turns", [this]()
		{
			const TOptional<FStationVoiceEvent> Acknowledged = Parse(TEXT(R"({"session_id":"s1","turn_id":4,"role":"examiner","status":"acknowledged"})"));
			TestTrue("acknowledged", Acknowledged.IsSet() && Acknowledged->Kind == EStationVoiceEventKind::ExaminerAcknowledged);
			const TOptional<FStationVoiceEvent> Kept = Parse(TEXT(R"({"session_id":"s1","turn_id":4,"role":"examiner","status":"kept"})"));
			TestTrue("kept", Kept.IsSet() && Kept->Kind == EStationVoiceEventKind::PatientUnanswered);
			TestFalse("unknown status", Parse(TEXT(R"({"session_id":"s1","turn_id":4,"role":"examiner","status":"other"})")).IsSet());
		});

		It("compares the session, role and status exactly, as the web parser does", [this]()
		{
			TestFalse("session in another case", Parse(TEXT(R"({"session_id":"S1","turn_id":3,"final":true,"text":"Oi"})")).IsSet());
			TestFalse("role in another case", Parse(TEXT(R"({"session_id":"s1","turn_id":3,"role":"Patient","text":"Oi"})")).IsSet());
			TestFalse("patient status in another case", Parse(TEXT(R"({"session_id":"s1","turn_id":3,"role":"patient","status":"COMPLETE"})")).IsSet());
			TestFalse("examiner status in another case", Parse(TEXT(R"({"session_id":"s1","turn_id":4,"role":"examiner","status":"Acknowledged"})")).IsSet());
		});

		It("reads turn failures and the worker stopping", [this]()
		{
			const TOptional<FStationVoiceEvent> Failure = Parse(TEXT(R"({"session_id":"s1","turn_id":5,"generation_id":2,"failure":"synthesis_failed"})"));
			if (TestTrue("turn failure", Failure.IsSet()))
			{
				TestEqual("kind", Failure->Kind, EStationVoiceEventKind::TurnFailure);
				TestEqual("code", Failure->Failure, TEXT("synthesis_failed"));
			}
			const TOptional<FStationVoiceEvent> Fatal = Parse(TEXT(R"({"session_id":"s1","error":"stt_unavailable"})"));
			if (TestTrue("fatal", Fatal.IsSet()))
			{
				TestEqual("kind", Fatal->Kind, EStationVoiceEventKind::Fatal);
				TestEqual("turn", Fatal->TurnId, 0);
				TestEqual("code", Fatal->Failure, TEXT("stt_unavailable"));
			}
		});

		It("drops other sessions and malformed messages", [this]()
		{
			TestFalse("other session", Parse(TEXT(R"({"session_id":"s2","turn_id":3,"final":true,"text":"Oi"})")).IsSet());
			TestFalse("no session", Parse(TEXT(R"({"turn_id":3,"final":true,"text":"Oi"})")).IsSet());
			TestFalse("not json", Parse(TEXT("Oi")).IsSet());
			TestFalse("array", Parse(TEXT(R"([1,2])")).IsSet());
			TestFalse("turn zero", Parse(TEXT(R"({"session_id":"s1","turn_id":0,"final":true,"text":"Oi"})")).IsSet());
			TestFalse("fractional turn", Parse(TEXT(R"({"session_id":"s1","turn_id":1.5,"final":true,"text":"Oi"})")).IsSet());
			TestFalse("string turn", Parse(TEXT(R"({"session_id":"s1","turn_id":"3","final":true,"text":"Oi"})")).IsSet());
			TestFalse("unknown role", Parse(TEXT(R"({"session_id":"s1","turn_id":3,"role":"doctor","text":"Oi"})")).IsSet());
			TestFalse("role not a string", Parse(TEXT(R"({"session_id":"s1","turn_id":3,"role":null,"final":true,"text":"Oi"})")).IsSet());
		});
	});

	It("shares the LiveKit SDK with any other module that initialised it", [this]()
	{
		// Another module (the #189 spike) may initialise the SDK first; LiveKit then answers false.
		livekit::initialize(livekit::LogLevel::Warn);
		TestTrue("ready after another module", StationLiveKit::EnsureInitialized());
		TestTrue("ready when asked again", StationLiveKit::EnsureInitialized());
	});

	Describe("FStationPcmFramer", [this]()
	{
		It("cuts 48 kHz mono into 10 ms frames and keeps the remainder", [this]()
		{
			FStationPcmFramer Framer;
			TArray<float> Samples;
			Samples.Init(0.5f, 1000);
			const TArray<TArray<int16>> First = Frames(Framer, Samples, 48000, 1);
			TestEqual("two frames", First.Num(), 2);
			if (First.Num() == 2)
			{
				TestEqual("frame size", First[0].Num(), FStationPcmFramer::FrameSamples);
				TestEqual("value", First[1][100], int16(16384));
			}
			Samples.Init(0.5f, 440);
			TestEqual("remainder completes a frame", Frames(Framer, Samples, 48000, 1).Num(), 1);
		});

		It("averages channels into mono", [this]()
		{
			FStationPcmFramer Framer;
			TArray<float> Stereo;
			for (int32 i = 0; i < FStationPcmFramer::FrameSamples; ++i)
			{
				Stereo.Add(1.0f);
				Stereo.Add(0.0f);
			}
			const TArray<TArray<int16>> Out = Frames(Framer, Stereo, 48000, 2);
			if (TestEqual("one frame", Out.Num(), 1))
			{
				TestEqual("average", Out[0][10], int16(16384));
			}
		});

		It("resamples other rates to 48 kHz", [this]()
		{
			FStationPcmFramer Framer;
			TArray<float> Samples;
			Samples.Init(0.25f, 1600); // 100 ms at 16 kHz
			const TArray<TArray<int16>> Out = Frames(Framer, Samples, 16000, 1);
			TestTrue("about ten frames", Out.Num() >= 9 && Out.Num() <= 10);
			if (Out.Num() > 0)
			{
				TestEqual("level kept", Out[0][200], int16(8192));
			}
		});

		It("clips samples outside [-1, 1]", [this]()
		{
			FStationPcmFramer Framer;
			TArray<float> Samples;
			Samples.Init(2.0f, FStationPcmFramer::FrameSamples);
			const TArray<TArray<int16>> Loud = Frames(Framer, Samples, 48000, 1);
			Samples.Init(-2.0f, FStationPcmFramer::FrameSamples);
			const TArray<TArray<int16>> Quiet = Frames(Framer, Samples, 48000, 1);
			if (TestEqual("frames", Loud.Num() + Quiet.Num(), 2))
			{
				TestEqual("top", Loud[0][0], int16(MAX_int16));
				TestEqual("bottom", Quiet[0][0], int16(-MAX_int16));
			}
		});
	});

	Describe("FStationVoiceLiveness", [this]()
	{
		using FSignals = FStationVoiceLiveness::FSignals;
		const FSignals Answering{ true, false };
		const FSignals WorkerGone{ false, false };
		const FSignals Retrying{ true, true };

		It("waits twenty seconds for the worker to first join, then loses the voice", [this, Answering, WorkerGone]()
		{
			FStationVoiceLiveness Liveness;
			TestEqual("waiting", Liveness.Update(WorkerGone, 0.0), EStationVoiceState::WaitingForWorker);
			TestEqual("before twenty seconds", Liveness.Tick(19.9), EStationVoiceState::WaitingForWorker);
			TestEqual("after twenty seconds", Liveness.Tick(20.0), EStationVoiceState::Failed);
			TestEqual("a late worker changes nothing", Liveness.Update(Answering, 21.0), EStationVoiceState::Failed);
		});

		It("counts the twenty seconds from the first report, not from later ones", [this, Answering, WorkerGone]()
		{
			FStationVoiceLiveness Liveness;
			Liveness.Update(WorkerGone, 0.0);
			TestEqual("still waiting", Liveness.Update(WorkerGone, 15.0), EStationVoiceState::WaitingForWorker);
			TestEqual("lost", Liveness.Tick(20.0), EStationVoiceState::Failed);
		});

		It("has no first-join limit once the worker answered", [this, Answering]()
		{
			FStationVoiceLiveness Liveness;
			Liveness.Update(Answering, 0.0);
			TestEqual("ready long after", Liveness.Tick(1000.0), EStationVoiceState::Ready);
		});

		It("reconnects when the worker leaves, and loses the voice after ten seconds for good", [this, Answering, WorkerGone]()
		{
			FStationVoiceLiveness Liveness;
			TestEqual("ready", Liveness.Update(Answering, 0.0), EStationVoiceState::Ready);
			TestEqual("worker left", Liveness.Update(WorkerGone, 1.0), EStationVoiceState::Reconnecting);
			TestEqual("before ten seconds", Liveness.Tick(10.9), EStationVoiceState::Reconnecting);
			TestEqual("after ten seconds", Liveness.Tick(11.0), EStationVoiceState::Failed);
			TestEqual("stays lost", Liveness.Update(Answering, 12.0), EStationVoiceState::Failed);
		});

		It("shows LiveKit's retries as reconnecting, even before the worker joined", [this, Retrying]()
		{
			FStationVoiceLiveness Liveness;
			TestEqual("retrying", Liveness.Update(Retrying, 0.0), EStationVoiceState::Reconnecting);
			TestEqual("lost", Liveness.Tick(10.0), EStationVoiceState::Failed);
		});

		It("names the rule that lost the voice, not the state shown before it", [this, Answering, WorkerGone, Retrying]()
		{
			using EFailure = FStationVoiceLiveness::EFailure;
			FStationVoiceLiveness Joining;
			Joining.Update(WorkerGone, 0.0);
			TestEqual("nothing lost yet", Joining.GetFailure(), EFailure::None);
			Joining.Update(Retrying, 15.0);
			TestEqual("lost on the first-join limit", Joining.Update(WorkerGone, 22.0), EStationVoiceState::Failed);
			TestEqual("the worker never joined", Joining.GetFailure(), EFailure::WorkerNeverJoined);

			FStationVoiceLiveness Answered;
			Answered.Update(Answering, 0.0);
			Answered.Update(WorkerGone, 1.0);
			TestEqual("lost after ten seconds", Answered.Tick(11.0), EStationVoiceState::Failed);
			TestEqual("the voice did not come back", Answered.GetFailure(), EFailure::VoiceNotBack);
		});

		It("is ready again when the voice comes back in time, and counts a new loss from zero", [this, Answering, WorkerGone, Retrying]()
		{
			FStationVoiceLiveness Liveness;
			Liveness.Update(Answering, 0.0);
			Liveness.Update(Retrying, 1.0);
			TestEqual("back", Liveness.Update(Answering, 9.0), EStationVoiceState::Ready);
			TestEqual("lost again", Liveness.Update(WorkerGone, 20.0), EStationVoiceState::Reconnecting);
			TestEqual("a fresh ten seconds", Liveness.Tick(29.0), EStationVoiceState::Reconnecting);
			TestEqual("given up", Liveness.Tick(30.0), EStationVoiceState::Failed);
		});
	});

	Describe("FStationWorkerPresence", [this]()
	{
		It("is absent until something reports the worker", [this]()
		{
			FStationWorkerPresence Presence;
			TestFalse("unknown reads as absent", Presence.IsPresent());
		});

		It("stays absent when the worker leaves during the connect scan", [this]()
		{
			FStationWorkerPresence Presence;
			Presence.OnLeft();
			Presence.OnSeenInScan();
			TestFalse("the leave event wins over the stale scan", Presence.IsPresent());
		});

		It("is absent when the worker leaves after the scan saw it", [this]()
		{
			FStationWorkerPresence Presence;
			Presence.OnSeenInScan();
			TestTrue("seen by the scan", Presence.IsPresent());
			Presence.OnLeft();
			TestFalse("left", Presence.IsPresent());
		});

		It("is present when the scan finds the worker from unknown", [this]()
		{
			FStationWorkerPresence Presence;
			Presence.OnSeenInScan();
			TestTrue("present", Presence.IsPresent());
		});

		It("is present when the worker joins after it left", [this]()
		{
			FStationWorkerPresence Presence;
			Presence.OnLeft();
			Presence.OnJoined();
			TestTrue("present", Presence.IsPresent());
		});
	});
}

BEGIN_DEFINE_SPEC(FStationVoiceStackSpec, "ProyectoMed.StationVoice.Stack",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	UStationClient* Client = nullptr;
	TArray<FStationVoiceEvent> Events;
	TArray<EStationVoiceState> States;
	std::atomic<int32> LoudPatientFrames{0};
	// Mono samples of the patient's voice in loud chunks, and their rate.
	std::atomic<int64> LoudPatientSamples{0};
	std::atomic<int32> PatientSampleRate{0};
	FTSTicker::FDelegateHandle Ticker;

	/** Seconds of the patient's voice heard so far. */
	double SpokenSeconds() const
	{
		const int32 Rate = PatientSampleRate;
		return Rate > 0 ? double(LoudPatientSamples) / Rate : 0.0;
	}

	/** Joins the voice stack's room for a new consented run; `Then` runs once the worker is there. */
	void JoinRoom(const FDoneDelegate& Done, TFunction<void()> Then);
	/** Speaks one second, then a second of silence, in real time. */
	void Speak();
	/** Calls `Then` once `Condition` holds, checking every tick; fails after `Seconds`. */
	void WaitUntil(const FString& What, TFunction<bool()> Condition, const FDoneDelegate& Done, TFunction<void()> Then, double Seconds = 30.0);
	const FStationVoiceEvent* Find(EStationVoiceEventKind Kind) const;
END_DEFINE_SPEC(FStationVoiceStackSpec)

const FStationVoiceEvent* FStationVoiceStackSpec::Find(EStationVoiceEventKind Kind) const
{
	return Events.FindByPredicate([Kind](const FStationVoiceEvent& Event)
	{
		return Event.Kind == Kind && (Kind != EStationVoiceEventKind::Learner || Event.bFinal);
	});
}

void FStationVoiceStackSpec::WaitUntil(const FString& What, TFunction<bool()> Condition, const FDoneDelegate& Done,
	TFunction<void()> Then, double Seconds)
{
	const double Deadline = FPlatformTime::Seconds() + Seconds;
	FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda(
		[this, What, Condition = MoveTemp(Condition), Done, Then = MoveTemp(Then), Deadline](float)
		{
			if (Condition())
			{
				Then();
				return false;
			}
			if (FPlatformTime::Seconds() > Deadline)
			{
				AddError(FString::Printf(TEXT("Timed out waiting for %s (is scripts/run-voice-stack.sh running?)"), *What));
				Done.Execute();
				return false;
			}
			return true;
		}));
}

void FStationVoiceStackSpec::JoinRoom(const FDoneDelegate& Done, TFunction<void()> Then)
{
	Client->StartSession(true, [this, Done, Then = MoveTemp(Then)](const TStationResult<FStationSession>& Started) mutable
	{
		if (!TestFalse(TEXT("session started (is the voice stack running?)"), Started.HasError()))
		{
			Done.Execute();
			return;
		}
		Client->RequestVoiceCredential([this, Done, Then = MoveTemp(Then)](const TStationResult<FStationVoiceCredential>& Credential) mutable
		{
			if (!TestFalse(TEXT("voice credential"), Credential.HasError()))
			{
				Done.Execute();
				return;
			}
			FStationVoiceHandlers Handlers;
			Handlers.OnEvent = [this](const FStationVoiceEvent& Event) { Events.Add(Event); };
			Handlers.OnStateChanged = [this](EStationVoiceState State) { States.Add(State); };
			Handlers.OnPatientPcm = [this](TConstArrayView<int16> Samples, int32 SampleRate, int32 NumChannels)
			{
				for (const int16 Sample : Samples)
				{
					if (FMath::Abs(Sample) > 1000)
					{
						++LoudPatientFrames;
						LoudPatientSamples += Samples.Num() / FMath::Max(1, NumChannels);
						PatientSampleRate = SampleRate;
						return;
					}
				}
			};
			TestTrue("link created", Client->ConnectVoice(Credential.GetValue(), MoveTemp(Handlers)).IsValid());
			WaitUntil(TEXT("the voice worker"), [this]()
			{
				const FStationVoiceLink* Voice = Client->GetVoice();
				return !Voice || Voice->GetState() == EStationVoiceState::Ready || Voice->GetState() == EStationVoiceState::Failed;
			}, Done, [this, Done, Then = MoveTemp(Then)]()
			{
				const FStationVoiceLink* Voice = Client->GetVoice();
				if (!TestTrue(TEXT("voice ready"), Voice && Voice->GetState() == EStationVoiceState::Ready))
				{
					AddError(Voice ? Voice->GetFailure() : TEXT("no link"));
					Done.Execute();
					return;
				}
				Then();
			});
		});
	});
}

void FStationVoiceStackSpec::Speak()
{
	const double Start = FPlatformTime::Seconds();
	TSharedRef<int32> Sent = MakeShared<int32>(0);
	Ticker = FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateLambda([this, Start, Sent](float)
	{
		const int32 Due = FMath::Min(200, FMath::FloorToInt((FPlatformTime::Seconds() - Start) * 100.0));
		FStationVoiceLink* Voice = Client->GetVoice();
		for (; *Sent < Due && Voice; ++*Sent)
		{
			Voice->PushMicrophonePcm(StationVoiceTests::SpeechChunk(*Sent, *Sent < 100), FStationPcmFramer::SampleRate, 1);
		}
		return *Sent < 200 && Voice != nullptr;
	}));
}

void FStationVoiceStackSpec::Define()
{
	using namespace StationVoiceTests;

	const FTimespan Timeout = FTimespan::FromSeconds(90);

	BeforeEach([this]()
	{
		Events.Reset();
		States.Reset();
		LoudPatientFrames = 0;
		LoudPatientSamples = 0;
		PatientSampleRate = 0;
		Client = NewObject<UStationClient>();
		Client->AddToRoot();
		Client->SetPhoenixBaseUrl(PhoenixUrl());
	});

	LatentAfterEach(Timeout, [this](const FDoneDelegate& Done)
	{
		FTSTicker::GetCoreTicker().RemoveTicker(Ticker);
		auto Release = [this, Done]()
		{
			Client->DisconnectVoice();
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

	LatentIt("speaks a turn and receives the approved reply as text and voice", Timeout, [this](const FDoneDelegate& Done)
	{
		JoinRoom(Done, [this, Done]()
		{
			Speak();
			WaitUntil(TEXT("the end of the patient reply"), [this]()
			{
				return Find(EStationVoiceEventKind::PatientComplete) != nullptr
					|| Find(EStationVoiceEventKind::TurnFailure) != nullptr || Find(EStationVoiceEventKind::Fatal) != nullptr;
			}, Done, [this, Done]()
			{
				const FStationVoiceEvent* Learner = Find(EStationVoiceEventKind::Learner);
				const FStationVoiceEvent* Patient = Find(EStationVoiceEventKind::PatientText);
				const FStationVoiceEvent* Complete = Find(EStationVoiceEventKind::PatientComplete);
				TestNull("no turn failure", Find(EStationVoiceEventKind::TurnFailure));
				TestNull("no fatal error", Find(EStationVoiceEventKind::Fatal));
				if (!TestNotNull("learner transcript", Learner) || !TestNotNull("patient text", Patient)
					|| !TestNotNull("reply end", Complete))
				{
					Done.Execute();
					return;
				}
				TestEqual("worker heard the learner", Learner->Text, StackTranscript);
				TestEqual("patient text", Patient->Text, StackPatientReply);
				TestEqual("reply answers the turn", Patient->TurnId, Learner->TurnId);
				TestEqual("reply end of the same turn", Complete->TurnId, Learner->TurnId);
				// The voice plays after the text event; give its tail time to arrive.
				WaitUntil(TEXT("the patient's voice"), [this]() { return LoudPatientFrames > 0; }, Done,
					[this, Done, TurnText = Patient->Text]()
					{
						// What was shown and spoken is what Phoenix approved and stored for the run.
						Client->RefreshSession([this, Done, TurnText](const TStationResult<FStationSession>& Refreshed)
						{
							if (TestFalse("refresh", Refreshed.HasError()))
							{
								const FStationMessage* Stored = Refreshed.GetValue().Messages.FindByPredicate(
									[](const FStationMessage& Message) { return Message.Speaker == EStationSpeaker::Patient; });
								if (TestNotNull("patient reply in the transcript", Stored))
								{
									TestEqual("same approved reply", Stored->Text, TurnText);
								}
							}
							Done.Execute();
						});
					}, 10.0);
			});
		});
	});

	// #325: the voice worker speaks a typed turn's approved reply too; the turn's own
	// answer stays text-only.
	LatentIt("speaks the approved reply to a typed turn with the patient's voice", Timeout, [this](const FDoneDelegate& Done)
	{
		JoinRoom(Done, [this, Done]()
		{
			Client->SendTurn(TEXT("Como o senhor se chama?"), EStationTurnModality::Text,
				[this, Done](const TStationResult<FStationTurnReply>& Reply)
			{
				if (!TestFalse("typed turn answered", Reply.HasError()))
				{
					Done.Execute();
					return;
				}
				const FString Shown = Reply.GetValue().ReplyText;
				TestEqual("the approved reply is shown", Shown, StackPatientReply);
				TestTrue("the answer carries no audio", Reply.GetValue().ReplyAudioUrl.IsEmpty());
				const double Expected = FakeToneSeconds(Shown);
				WaitUntil(TEXT("the patient's voice"), [this, Expected]() { return SpokenSeconds() >= Expected - 0.1; }, Done,
					[this, Done, Expected]()
					{
						// Let a longer, wrong reply show itself before comparing.
						const double Settled = FPlatformTime::Seconds() + 1.0;
						WaitUntil(TEXT("the end of the patient's voice"), [Settled]() { return FPlatformTime::Seconds() >= Settled; },
							Done, [this, Done, Expected]()
							{
								// What was heard is as long as the text shown, so it is that text.
								TestTrue(FString::Printf(TEXT("spoke %.2f s of the reply's %.2f s"), SpokenSeconds(), Expected),
									FMath::Abs(SpokenSeconds() - Expected) < 0.25);
								TestNull("the screen gets the text from the answer, not the room",
									Find(EStationVoiceEventKind::PatientText));
								TestNull("no turn failure", Find(EStationVoiceEventKind::TurnFailure));
								Done.Execute();
							});
					}, 10.0);
			});
		});
	});

	LatentIt("leaves the room when the run is discarded", Timeout, [this](const FDoneDelegate& Done)
	{
		JoinRoom(Done, [this, Done]()
		{
			const TSharedRef<FStationVoiceLink, ESPMode::ThreadSafe> Link = Client->GetVoice()->AsShared();
			const int32 StatesBefore = States.Num();
			Client->DiscardSession([this, Done](const TStationResult<FStationNone>& Discarded)
			{
				TestFalse("discarded", Discarded.HasError());
				TestNull("no voice link", Client->GetVoice());
				Done.Execute();
			});
			TestNull("left at once", Client->GetVoice());
			TestEqual("link disconnected", Link->GetState(), EStationVoiceState::Disconnected);
			// Speech after the run reaches nobody and calls no handler.
			Link->PushMicrophonePcm(StationVoiceTests::SpeechChunk(0, true), FStationPcmFramer::SampleRate, 1);
			TestEqual("no state change reported", States.Num(), StatesBefore);
		});
	});

	LatentIt("leaves at once even while the room is still being joined", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(true, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse(TEXT("session started (is the voice stack running?)"), Started.HasError()))
			{
				Done.Execute();
				return;
			}
			// An address nothing answers: joining hangs until LiveKit gives up, about 30 s.
			FStationVoiceCredential Unreachable;
			Unreachable.Url = TEXT("ws://10.255.255.1:7880");
			Unreachable.Token = TEXT("unused");
			Client->ConnectVoice(Unreachable, FStationVoiceHandlers());
			// Leave once the join is well under way.
			WaitUntil(TEXT("the join to start"), [Begun = FPlatformTime::Seconds()]() { return FPlatformTime::Seconds() - Begun > 1.0; }, Done,
				[this, Done]()
				{
					const double Start = FPlatformTime::Seconds();
					Client->DisconnectVoice();
					TestTrue("the game is not held up", FPlatformTime::Seconds() - Start < 0.5);
					TestNull("no voice link", Client->GetVoice());
					Done.Execute();
				});
		});
	});

	LatentIt("leaves the room when the run finishes", Timeout, [this](const FDoneDelegate& Done)
	{
		JoinRoom(Done, [this, Done]()
		{
			Client->FinishSession(EStationFinishReason::User, [this, Done](const TStationResult<FStationSession>& Finished)
			{
				TestFalse("finished", Finished.HasError());
				TestNull("no voice link", Client->GetVoice());
				const size_t EventsAtFinish = Events.Num();
				WaitUntil(TEXT("a quiet second"), [Start = FPlatformTime::Seconds()]() { return FPlatformTime::Seconds() - Start > 1.0; }, Done,
					[this, Done, EventsAtFinish]()
					{
						TestEqual("no event after the run", size_t(Events.Num()), EventsAtFinish);
						Done.Execute();
					});
			});
		});
	});

	It("does not join a room without a run", [this]()
	{
		FStationVoiceCredential Credential;
		Credential.Url = TEXT("ws://127.0.0.1:7880");
		TestFalse("no link", Client->ConnectVoice(Credential, FStationVoiceHandlers()).IsValid());
		TestNull("none held", Client->GetVoice());
	});
}

#endif // WITH_DEV_AUTOMATION_TESTS
