// Run flow tests for a real test's patient, heard and never read (#423): the worker
// sends how each reply goes with no text, as these JSON messages show.

#include "Misc/AutomationTest.h"
#include "Station/StationRunFlow.h"
#include "StationVoice.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace StationRunAudioOnly
{
	FStationVoiceEvent Event(const TCHAR* Json)
	{
		const FTCHARToUTF8 Utf8(Json);
		const TOptional<FStationVoiceEvent> Parsed = ParseStationVoiceEvent(
			TConstArrayView<uint8>(reinterpret_cast<const uint8*>(Utf8.Get()), Utf8.Length()), TEXT("s1"));
		check(Parsed.IsSet());
		return *Parsed;
	}

	const TCHAR* LearnerCaption = TEXT(R"({"session_id":"s1","turn_id":1,"final":false,"text":"Onde"})");
	const TCHAR* LearnerFinal = TEXT(R"({"session_id":"s1","turn_id":1,"final":true,"text":"Onde dói?"})");
	const TCHAR* NextLearnerCaption = TEXT(R"({"session_id":"s1","turn_id":2,"final":false,"text":"Tem febre"})");
	const TCHAR* Speaking = TEXT(R"({"session_id":"s1","turn_id":1,"generation_id":1,"role":"voice","status":"speaking","segment":0})");
	const TCHAR* Spoken = TEXT(R"({"session_id":"s1","turn_id":1,"generation_id":1,"role":"voice","status":"complete"})");
}

BEGIN_DEFINE_SPEC(FStationRunAudioOnlySpec, "ProyectoMed.StationRun.AudioOnly",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
END_DEFINE_SPEC(FStationRunAudioOnlySpec)

void FStationRunAudioOnlySpec::Define()
{
	using namespace StationRunAudioOnly;

	It("lets the patient be heard after the learner spoke, with no text", [this]()
	{
		UStationRunFlow* Flow = NewObject<UStationRunFlow>();
		TSharedRef<int32> Silenced = MakeShared<int32>(0);
		TSharedRef<int32> Resumed = MakeShared<int32>(0);
		FStationPatientOutput Patient;
		Patient.Silence = [Silenced]() { ++*Silenced; };
		Patient.Resume = [Resumed]() { ++*Resumed; };
		Flow->SetPatientOutput(MoveTemp(Patient));
		Flow->Step = EStationRunStep::Running;

		Flow->HandleVoiceEvent(Event(LearnerCaption));
		Flow->HandleVoiceEvent(Event(LearnerFinal));
		TestEqual("the learner's turn silences the patient", *Silenced, 1);
		TestEqual("nothing plays yet", *Resumed, 0);

		Flow->HandleVoiceEvent(Event(Speaking));
		TestEqual("the reply plays", *Resumed, 1);
		TestTrue("no text in progress", Flow->GetVoice().PatientText.IsEmpty());
	});

	It("ends the turn with no patient line, and keeps the learner's", [this]()
	{
		UStationRunFlow* Flow = NewObject<UStationRunFlow>();
		Flow->Step = EStationRunStep::Running;

		Flow->HandleVoiceEvent(Event(LearnerCaption));
		Flow->HandleVoiceEvent(Event(LearnerFinal));
		TestTrue("the patient is answering", Flow->IsPatientAnswering());

		Flow->HandleVoiceEvent(Event(Speaking));
		Flow->HandleVoiceEvent(Event(Spoken));
		TestFalse("the patient has answered", Flow->IsPatientAnswering());

		Flow->HandleVoiceEvent(Event(NextLearnerCaption));
		if (TestEqual("the spoken turn stays, alone", Flow->GetTranscript().Num(), 1))
		{
			TestEqual("the learner's line", Flow->GetTranscript()[0].Text, FString(TEXT("Onde dói?")));
		}
	});
}

#endif
