// Voice link unit tests: `ProyectoMed.StationVoice.Unit` needs nothing else.

#include "Misc/AutomationTest.h"
#include "StationLiveKit.h"
#include "StationPcm.h"

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
}

#endif // WITH_DEV_AUTOMATION_TESTS
