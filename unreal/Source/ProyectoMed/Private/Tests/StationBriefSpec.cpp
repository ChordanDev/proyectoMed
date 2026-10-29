// What the screens before a run offer (#421): the main menu with the training
// and the simulated exam ("Prova simulada"), and the brief with the chosen
// mode's way in, or why the simulated exam cannot start. Needs nothing else;
// the look itself is judged on the images of StationCardSnapshotSpec.cpp.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Button.h"
#include "Components/HorizontalBox.h"
#include "Components/TextBlock.h"
#include "Engine/Engine.h"
#include "Station/StationRunFlow.h"
#include "Station/StationScreens.h"

BEGIN_DEFINE_SPEC(FStationBriefUnitSpec, "ProyectoMed.StationCards.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)

	UStationRunFlow* MakeFlow(EStationSessionMode SessionMode, EStationVoiceMode VoiceMode, EStationMicPermission Permission) const;
	UStationBriefWidget* MakeBrief(UStationRunFlow* Flow) const;
	/** Every text under `Root`, in tree order. */
	static TArray<FString> Texts(UWidget* Root);
	static bool IsShown(const UWidget* Widget);
END_DEFINE_SPEC(FStationBriefUnitSpec)

UStationRunFlow* FStationBriefUnitSpec::MakeFlow(EStationSessionMode SessionMode, EStationVoiceMode VoiceMode,
	EStationMicPermission Permission) const
{
	FStationSummary Station;
	Station.DisplayTitle = TEXT("Abdome agudo inflamatório — apendicite aguda");
	Station.Scenario = TEXT("Você é o médico ou a médica de plantão.");
	Station.Tasks = {TEXT("Obter anamnese dirigida.")};
	Station.VoiceMode = VoiceMode;

	UStationRunFlow* Flow = NewObject<UStationRunFlow>();
	Flow->Step = EStationRunStep::Brief;
	Flow->SessionMode = SessionMode;
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

TArray<FString> FStationBriefUnitSpec::Texts(UWidget* Root)
{
	TArray<FString> Found;
	UWidgetTree::ForWidgetAndChildren(Root, [&Found](UWidget* Widget)
	{
		if (const UTextBlock* Text = Cast<UTextBlock>(Widget))
		{
			Found.Add(Text->GetText().ToString());
		}
	});
	return Found;
}

bool FStationBriefUnitSpec::IsShown(const UWidget* Widget)
{
	return Widget && Widget->GetVisibility() != ESlateVisibility::Collapsed
		&& Widget->GetVisibility() != ESlateVisibility::Hidden;
}

void FStationBriefUnitSpec::Define()
{
	It("offers the training and the simulated exam on the menu, each with what it is", [this]()
	{
		UStationMenuWidget* Menu = CreateWidget<UStationMenuWidget>(GEngine->GetWorldContexts()[0].World());
		Menu->TakeWidget();
		TArray<EStationSessionMode> Chosen;
		Menu->OnModeChosen.BindLambda([&Chosen](EStationSessionMode Mode) { Chosen.Add(Mode); });

		const TArray<FString> Training = Texts(Menu->TrainingButton);
		TestTrue("training", Training.Contains(TEXT("Treino")));
		TestTrue("what a training is", Training.ContainsByPredicate([](const FString& Text) { return Text.Contains(TEXT("texto ou por voz")); }));
		const TArray<FString> Exam = Texts(Menu->SimulatedExamButton);
		TestTrue("simulated exam", Exam.Contains(TEXT("Prova simulada")));
		TestTrue("what a simulated exam is", Exam.ContainsByPredicate([](const FString& Text) { return Text.Contains(TEXT("Só por voz")); }));

		Menu->HandleTraining();
		Menu->HandleSimulatedExam();
		TestEqual("both chosen, in order", Chosen,
			TArray<EStationSessionMode>{EStationSessionMode::Training, EStationSessionMode::SimulatedExam});
	});

	It("shows each mode's traits on its card", [this]()
	{
		UStationMenuWidget* Menu = CreateWidget<UStationMenuWidget>(GEngine->GetWorldContexts()[0].World());
		Menu->TakeWidget();

		const TArray<FString> Training = Texts(Menu->TrainingButton);
		TestTrue("text or voice", Training.Contains(TEXT("Texto ou voz")));
		TestTrue("the clock in view", Training.Contains(TEXT("Relógio à vista")));
		const TArray<FString> Exam = Texts(Menu->SimulatedExamButton);
		TestTrue("voice only", Exam.Contains(TEXT("Só voz")));
		TestTrue("no help", Exam.Contains(TEXT("Sem ajuda")));
		TestTrue("ten minutes", Exam.Contains(TEXT("10 minutos")));
	});

	It("offers a way out of the app, and the settings only as coming soon", [this]()
	{
		UStationMenuWidget* Menu = CreateWidget<UStationMenuWidget>(GEngine->GetWorldContexts()[0].World());
		Menu->TakeWidget();
		int32 Quits = 0;
		Menu->OnQuit.BindLambda([&Quits]() { ++Quits; });

		TestTrue("quit", IsShown(Menu->QuitButton) && Menu->QuitButton->GetIsEnabled()
			&& Texts(Menu->QuitButton).Contains(TEXT("Sair")));
		Menu->HandleQuit();
		TestEqual("quit asked once", Quits, 1);

		TestTrue("settings shown", IsShown(Menu->SettingsButton));
		TestFalse("settings not there yet", Menu->SettingsButton->GetIsEnabled());
		TestTrue("said so", Texts(Menu->SettingsButton).Contains(TEXT("Ajustes · em breve")));
	});

	It("offers a training's two ways in, and not the simulated exam, on a training's brief", [this]()
	{
		UStationBriefWidget* Brief = MakeBrief(
			MakeFlow(EStationSessionMode::Training, EStationVoiceMode::Realtime, EStationMicPermission::Granted));

		TestTrue("titled as a training", Brief->HeadingText->GetText().ToString().StartsWith(TEXT("Treino")));
		TestTrue("text training", IsShown(Brief->TextButton) && Brief->TextButton->GetIsEnabled());
		TestTrue("voice training", IsShown(Brief->VoiceButton) && Brief->VoiceButton->GetIsEnabled());
		TestFalse("no simulated exam", IsShown(Brief->SimulatedExamButton));
		TestFalse("no simulated exam note", IsShown(Brief->SimulatedExamNote));
	});

	It("offers only the simulated exam, by voice, on a simulated exam's brief", [this]()
	{
		UStationBriefWidget* Brief = MakeBrief(
			MakeFlow(EStationSessionMode::SimulatedExam, EStationVoiceMode::Realtime, EStationMicPermission::Granted));

		TestTrue("titled as a simulated exam", Brief->HeadingText->GetText().ToString().StartsWith(TEXT("Prova simulada")));
		TestFalse("no trainings", IsShown(Brief->TrainingsRow));
		TestFalse("no voice training note", IsShown(Brief->VoiceNote));
		TestTrue("simulated exam", IsShown(Brief->SimulatedExamButton) && Brief->SimulatedExamButton->GetIsEnabled());
		TestTrue("its label", Texts(Brief->SimulatedExamButton).Contains(TEXT("Iniciar prova simulada")));
		TestTrue("what a simulated exam is", Brief->SimulatedExamNote->GetText().ToString().Contains(TEXT("Só por voz")));
	});

	It("keeps the simulated exam in view but disabled, with the reason, when the microphone is blocked", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationSessionMode::SimulatedExam, EStationVoiceMode::Realtime, EStationMicPermission::Denied);
		UStationBriefWidget* Brief = MakeBrief(Flow);

		TestTrue("simulated exam shown", IsShown(Brief->SimulatedExamButton));
		TestFalse("simulated exam disabled", Brief->SimulatedExamButton->GetIsEnabled());
		TestEqual("the reason, in Brazilian Portuguese", Brief->SimulatedExamNote->GetText().ToString(),
			SimulatedExamUnavailableText(*Flow->GetStation(), EStationMicPermission::Denied).ToString());
	});

	It("keeps the simulated exam in view but disabled, with the reason, without realtime voice", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationSessionMode::SimulatedExam, EStationVoiceMode::Off, EStationMicPermission::Granted);
		UStationBriefWidget* Brief = MakeBrief(Flow);

		TestTrue("simulated exam shown", IsShown(Brief->SimulatedExamButton));
		TestFalse("simulated exam disabled", Brief->SimulatedExamButton->GetIsEnabled());
		TestEqual("the reason, in Brazilian Portuguese", Brief->SimulatedExamNote->GetText().ToString(),
			SimulatedExamUnavailableText(*Flow->GetStation(), EStationMicPermission::Granted).ToString());
	});

	It("leads back to the menu from the brief", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationSessionMode::SimulatedExam, EStationVoiceMode::Realtime, EStationMicPermission::Granted);
		UStationBriefWidget* Brief = MakeBrief(Flow);

		TestTrue("the way back", IsShown(Brief->MenuButton) && Texts(Brief->MenuButton).Contains(TEXT("‹ Voltar ao menu")));
		Brief->HandleBackToMenu();
		TestEqual("on the menu", Flow->GetStep(), EStationRunStep::Menu);
	});
}

#endif
