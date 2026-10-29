// What the brief offers before a run (#421): the trainings and the simulated
// exam ("Prova simulada"), and why the simulated exam cannot start when it
// cannot. Needs nothing else; the look itself is judged on the images of
// StationCardSnapshotSpec.cpp.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Blueprint/UserWidget.h"
#include "Components/Button.h"
#include "Components/TextBlock.h"
#include "Engine/Engine.h"
#include "Station/StationRunFlow.h"
#include "Station/StationScreens.h"

BEGIN_DEFINE_SPEC(FStationBriefUnitSpec, "ProyectoMed.StationCards.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)

	UStationRunFlow* MakeFlow(EStationVoiceMode VoiceMode, EStationMicPermission Permission) const;
	UStationBriefWidget* MakeBrief(UStationRunFlow* Flow) const;
	static FString Label(const UButton* Button);
	static bool IsShown(const UWidget* Widget);
END_DEFINE_SPEC(FStationBriefUnitSpec)

UStationRunFlow* FStationBriefUnitSpec::MakeFlow(EStationVoiceMode VoiceMode, EStationMicPermission Permission) const
{
	FStationSummary Station;
	Station.DisplayTitle = TEXT("Abdome agudo inflamatório — apendicite aguda");
	Station.Scenario = TEXT("Você é o médico ou a médica de plantão.");
	Station.Tasks = {TEXT("Obter anamnese dirigida.")};
	Station.VoiceMode = VoiceMode;

	UStationRunFlow* Flow = NewObject<UStationRunFlow>();
	Flow->Step = EStationRunStep::Brief;
	Flow->Station = Station;
	Flow->Microphone.GetPermission = [Permission]() { return Permission; };
	return Flow;
}

UStationBriefWidget* FStationBriefUnitSpec::MakeBrief(UStationRunFlow* Flow) const
{
	UStationBriefWidget* Brief = CreateWidget<UStationBriefWidget>(GEngine->GetWorldContexts()[0].World());
	Brief->TakeWidget();
	Brief->SetFlow(Flow);
	Brief->Refresh();
	return Brief;
}

FString FStationBriefUnitSpec::Label(const UButton* Button)
{
	const UTextBlock* Text = Button ? Cast<UTextBlock>(Button->GetContent()) : nullptr;
	return Text ? Text->GetText().ToString() : FString();
}

bool FStationBriefUnitSpec::IsShown(const UWidget* Widget)
{
	return Widget && Widget->GetVisibility() != ESlateVisibility::Collapsed
		&& Widget->GetVisibility() != ESlateVisibility::Hidden;
}

void FStationBriefUnitSpec::Define()
{
	It("offers the trainings and the simulated exam when the voice and the microphone allow it", [this]()
	{
		UStationBriefWidget* Brief = MakeBrief(MakeFlow(EStationVoiceMode::Realtime, EStationMicPermission::Granted));

		TestEqual("text training", Label(Brief->TextButton), TEXT("Treino por texto"));
		TestTrue("text training enabled", Brief->TextButton->GetIsEnabled());
		TestEqual("voice training", Label(Brief->VoiceButton), TEXT("Treino por voz"));
		TestTrue("voice training enabled", Brief->VoiceButton->GetIsEnabled());

		TestEqual("simulated exam", Label(Brief->SimulatedExamButton), TEXT("Prova simulada"));
		TestTrue("simulated exam shown", IsShown(Brief->SimulatedExamButton));
		TestTrue("simulated exam enabled", Brief->SimulatedExamButton->GetIsEnabled());
		TestTrue("what a simulated exam is",
			Brief->SimulatedExamNote->GetText().ToString().Contains(TEXT("Só por voz")));
	});

	It("keeps the simulated exam in view but disabled, with the reason, when the microphone is blocked", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationVoiceMode::Realtime, EStationMicPermission::Denied);
		UStationBriefWidget* Brief = MakeBrief(Flow);

		TestTrue("text training still enabled", Brief->TextButton->GetIsEnabled());
		TestTrue("simulated exam shown", IsShown(Brief->SimulatedExamButton));
		TestFalse("simulated exam disabled", Brief->SimulatedExamButton->GetIsEnabled());
		TestEqual("the reason, in Brazilian Portuguese", Brief->SimulatedExamNote->GetText().ToString(),
			SimulatedExamUnavailableText(*Flow->GetStation(), EStationMicPermission::Denied).ToString());
	});

	It("keeps the simulated exam in view but disabled, with the reason, without realtime voice", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationVoiceMode::Off, EStationMicPermission::Granted);
		UStationBriefWidget* Brief = MakeBrief(Flow);

		TestTrue("text training still enabled", Brief->TextButton->GetIsEnabled());
		TestFalse("no voice training without realtime voice", IsShown(Brief->VoiceButton));
		TestTrue("simulated exam shown", IsShown(Brief->SimulatedExamButton));
		TestFalse("simulated exam disabled", Brief->SimulatedExamButton->GetIsEnabled());
		TestEqual("the reason, in Brazilian Portuguese", Brief->SimulatedExamNote->GetText().ToString(),
			SimulatedExamUnavailableText(*Flow->GetStation(), EStationMicPermission::Granted).ToString());
	});
}

#endif
