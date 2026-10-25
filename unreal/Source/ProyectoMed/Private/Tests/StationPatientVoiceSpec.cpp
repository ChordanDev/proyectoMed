// Patient voice tests (#191). `ProyectoMed.PatientVoice.Unit` needs nothing else.

#include "Misc/AutomationTest.h"
#include "Station/Voice/StationFaceBlend.h"
#include "Station/Voice/StationPatientFaceAnim.h"
#include "Station/Voice/StationPatientVoice.h"
#include "Station/Voice/StationPatientWave.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace
{
	/** Whether the speaker plays voice next, pulling it as the audio thread does. */
	bool PlaysVoice(UStationPatientWave* Wave)
	{
		TArray<int16> Out;
		Out.SetNumZeroed(4096);
		const int32 Bytes = Wave->GeneratePCMData(reinterpret_cast<uint8*>(Out.GetData()), Out.Num());
		return Bytes > 0 && Out.ContainsByPredicate([](int16 Sample) { return Sample != 0; });
	}
}

BEGIN_DEFINE_SPEC(FStationPatientVoiceUnitSpec, "ProyectoMed.PatientVoice.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
END_DEFINE_SPEC(FStationPatientVoiceUnitSpec)

void FStationPatientVoiceUnitSpec::Define()
{
	It("moves only the mouth with speech", [this]()
	{
		for (const TCHAR* Control : { TEXT("CTRL_expressions_jawOpen"), TEXT("CTRL_expressions_mouthCornerPullL"),
			TEXT("CTRL_expressions_mouthLipsTogetherUL"), TEXT("CTRL_expressions_tongueOut"), TEXT("CTRL_expressions_teethUpU") })
		{
			TestTrue(Control, StationFaceBlend::IsMouthControl(Control));
		}
		for (const TCHAR* Control : { TEXT("CTRL_expressions_eyeBlinkL"), TEXT("CTRL_expressions_browRaiseInL"),
			TEXT("CTRL_expressions_eyeLookUpR"), TEXT("HeadYaw") })
		{
			TestFalse(Control, StationFaceBlend::IsMouthControl(Control));
		}
	});

	It("eases the speaking mouth in and out", [this]()
	{
		float Weight = 0.f;
		for (int32 Frame = 0; Frame < 30; ++Frame)
		{
			Weight = StationFaceBlend::StepSpeechWeight(Weight, true, 1.f / 60.f);
		}
		TestTrue("speaking after half a second", Weight > 0.95f);
		const float AfterOneFrame = StationFaceBlend::StepSpeechWeight(Weight, false, 1.f / 60.f);
		TestTrue("no snap back to idle", AfterOneFrame > 0.9f);
		for (int32 Frame = 0; Frame < 90; ++Frame)
		{
			Weight = StationFaceBlend::StepSpeechWeight(Weight, false, 1.f / 60.f);
		}
		TestTrue("idle after a second and a half", Weight < 0.01f);
		TestEqual("a long frame stays in range", StationFaceBlend::StepSpeechWeight(0.5f, true, 100.f), 1.f);
		TestEqual("no time, no change", StationFaceBlend::StepSpeechWeight(0.5f, true, 0.f), 0.5f);
	});

	It("keeps only the solved mouth and knows when the patient speaks", [this]()
	{
		FStationMouthState Mouth;
		TMap<FName, float> Read;
		TestFalse("silent before any voice", Mouth.Read(Read));

		Mouth.PushControls({ { TEXT("CTRL_expressions_jawOpen"), 0.7f }, { TEXT("CTRL_expressions_eyeBlinkL"), 1.f } });
		Mouth.NoteSpeech();
		TestTrue("speaking", Mouth.Read(Read));
		TestEqual("jaw kept", Read.FindRef(TEXT("CTRL_expressions_jawOpen")), 0.7f);
		TestFalse("eyes left to the idle loop", Read.Contains(TEXT("CTRL_expressions_eyeBlinkL")));

		Mouth.Rest();
		TestFalse("silent once it rests", Mouth.Read(Read));
		TestEqual("no mouth left", Read.Num(), 0);
		// The solver may still be working through voice it got before.
		Mouth.PushControls({ { TEXT("CTRL_expressions_jawOpen"), 0.4f } });
		Mouth.Read(Read);
		TestEqual("a late solved mouth is ignored", Read.Num(), 0);
		Mouth.NoteSpeech();
		Mouth.PushControls({ { TEXT("CTRL_expressions_jawOpen"), 0.4f } });
		TestTrue("speaking again", Mouth.Read(Read));
		TestEqual("moves again", Read.FindRef(TEXT("CTRL_expressions_jawOpen")), 0.4f);
	});

	It("plays and lip-syncs the patient's voice only while attached", [this]()
	{
		UStationPatientWave* Wave = NewObject<UStationPatientWave>();
		Wave->SetSampleRate(48000);
		Wave->NumChannels = 1;
		const TSharedRef<FStationMouthState, ESPMode::ThreadSafe> Mouth = MakeShared<FStationMouthState, ESPMode::ThreadSafe>();
		FStationPatientAudioSink Sink;
		Sink.Attach(Wave, nullptr, Mouth);

		TArray<int16> Voice;
		Voice.Init(8000, 480);
		Sink.Handle(Voice, 48000, 1);
		TMap<FName, float> Read;
		TestTrue("played by the speaker", PlaysVoice(Wave));
		TestTrue("mouth told the patient speaks", Mouth->Read(Read));

		Sink.Detach();
		Sink.Handle(Voice, 48000, 1);
		TestFalse("nothing after detach", PlaysVoice(Wave));
	});

	It("stops the patient's voice and mouth at once, until it may speak again", [this]()
	{
		UStationPatientWave* Wave = NewObject<UStationPatientWave>();
		Wave->SetSampleRate(48000);
		Wave->NumChannels = 1;
		const TSharedRef<FStationMouthState, ESPMode::ThreadSafe> Mouth = MakeShared<FStationMouthState, ESPMode::ThreadSafe>();
		FStationPatientAudioSink Sink;
		Sink.Attach(Wave, nullptr, Mouth);
		TArray<int16> Voice;
		Voice.Init(8000, 480);
		TMap<FName, float> Read;
		Sink.Handle(Voice, 48000, 1);

		Sink.Silence();
		TestFalse("the queued voice is gone", PlaysVoice(Wave));
		TestFalse("the mouth rests", Mouth->Read(Read));

		Sink.Handle(Voice, 48000, 1);
		TestFalse("late voice is dropped", PlaysVoice(Wave));
		TestFalse("and does not move the mouth", Mouth->Read(Read));

		Sink.Resume();
		Sink.Handle(Voice, 48000, 1);
		TestTrue("the next reply plays", PlaysVoice(Wave));
		TestTrue("and moves the mouth", Mouth->Read(Read));
	});

	It("treats a silent patient track as silence", [this]()
	{
		UStationPatientWave* Wave = NewObject<UStationPatientWave>();
		const TSharedRef<FStationMouthState, ESPMode::ThreadSafe> Mouth = MakeShared<FStationMouthState, ESPMode::ThreadSafe>();
		FStationPatientAudioSink Sink;
		Sink.Attach(Wave, nullptr, Mouth);
		TArray<int16> Quiet;
		Quiet.Init(10, 480);
		Sink.Handle(Quiet, 48000, 1);
		TMap<FName, float> Read;
		TestFalse("not speaking", Mouth->Read(Read));
	});
}

#endif // WITH_DEV_AUTOMATION_TESTS
