// What the screens before a run offer (#421): the main menu with the training
// and the simulated exam ("Prova simulada"), and the brief with the chosen
// mode's way in, or why the simulated exam cannot start. Needs nothing else;
// the look itself is judged on the images of StationCardSnapshotSpec.cpp.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/HorizontalBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Engine/Engine.h"
#include "Framework/Application/SlateApplication.h"
#include "InputCoreTypes.h"
#include "Station/StationRunFlow.h"
#include "Station/StationScreens.h"
#include "Station/StationUi.h"
#include "Widgets/SWindow.h"

BEGIN_DEFINE_SPEC(FStationBriefUnitSpec, "ProyectoMed.StationCards.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)

	UStationRunFlow* MakeFlow(EStationSessionMode SessionMode, EStationVoiceMode VoiceMode, EStationMicPermission Permission) const;
	UStationBriefWidget* MakeBrief(UStationRunFlow* Flow) const;
	UStationMenuWidget* MakeMenu() const;
	/** Every text under `Root`, in tree order. */
	static TArray<FString> Texts(UWidget* Root);
	static bool IsShown(const UWidget* Widget);
	static FReply Press(UStationMenuWidget& Menu, const FKey& Key, bool bRepeat = false);
	/** Lets every fade end, then checks that `Mode` is the lit one and the only one with an arrow. */
	void ExpectSelected(UStationMenuWidget& Menu, EStationSessionMode Mode);
END_DEFINE_SPEC(FStationBriefUnitSpec)

UStationMenuWidget* FStationBriefUnitSpec::MakeMenu() const
{
	UStationMenuWidget* Menu = CreateWidget<UStationMenuWidget>(GEngine->GetWorldContexts()[0].World());
	Menu->TakeWidget();
	return Menu;
}

FReply FStationBriefUnitSpec::Press(UStationMenuWidget& Menu, const FKey& Key, bool bRepeat)
{
	return Menu.NativeOnPreviewKeyDown(FGeometry(), FKeyEvent(Key, FModifierKeysState(), 0, bRepeat, 0, 0));
}

void FStationBriefUnitSpec::ExpectSelected(UStationMenuWidget& Menu, EStationSessionMode Mode)
{
	Menu.NativeTick(FGeometry(), 10.f);

	const bool bTraining = Mode == EStationSessionMode::Training;
	UButton* Lit = bTraining ? Menu.TrainingButton : Menu.SimulatedExamButton;
	UButton* Dimmed = bTraining ? Menu.SimulatedExamButton : Menu.TrainingButton;
	UButton* Arrow = bTraining ? Menu.TrainingArrow : Menu.SimulatedExamArrow;
	UButton* OtherArrow = bTraining ? Menu.SimulatedExamArrow : Menu.TrainingArrow;
	TestEqual("the selected mode lit", Lit->GetRenderOpacity(), 1.f);
	TestEqual("the other dimmed", Dimmed->GetRenderOpacity(), 0.45f);
	if (TestNotNull("its arrow", Arrow) && TestNotNull("the other arrow", OtherArrow))
	{
		TestEqual("its arrow in view", Arrow->GetVisibility(), ESlateVisibility::Visible);
		TestEqual("and solid", Arrow->GetRenderOpacity(), 1.f);
		TestEqual("the other arrow keeps its place out of view, so nothing moves", OtherArrow->GetVisibility(), ESlateVisibility::Hidden);
	}
}

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
		TestTrue("what a training is", Training.Contains(TEXT("Pratique a estação no seu ritmo, por texto ou por voz.")));
		const TArray<FString> Exam = Texts(Menu->SimulatedExamButton);
		TestTrue("simulated exam", Exam.Contains(TEXT("Prova simulada")));
		TestTrue("what a simulated exam is", Exam.Contains(TEXT("Uma estação completa, como no dia da prova prática.")));
		TestTrue("not an official grade", Exam.Contains(TEXT("Não é nota oficial do Revalida.")));

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
		TestFalse("text or voice is in its description, not a trait", Training.Contains(TEXT("Texto ou voz")));
		TestTrue("the clock in view", Training.Contains(TEXT("Relógio à vista")));
		TestTrue("with help", Training.Contains(TEXT("Com ajuda")));
		const TArray<FString> Exam = Texts(Menu->SimulatedExamButton);
		TestTrue("voice only", Exam.Contains(TEXT("Só voz")));
		TestTrue("no help", Exam.Contains(TEXT("Sem ajuda")));
		TestTrue("ten minutes", Exam.Contains(TEXT("10 minutos")));
	});

	It("hides the scene behind a solid background until the office behind the menu exists (#431)", [this]()
	{
		UStationMenuWidget* Menu = CreateWidget<UStationMenuWidget>(GEngine->GetWorldContexts()[0].World());
		Menu->TakeWidget();

		TestTrue("the background", IsShown(Menu->Backdrop));
		TestEqual("opaque, so no patient shows behind the cards", Menu->Backdrop->GetBrushColor().A, 1.f);
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
		TestTrue("history shown", IsShown(Menu->HistoryButton));
		TestFalse("history not there yet", Menu->HistoryButton && Menu->HistoryButton->GetIsEnabled());
		TestTrue("said so too", Texts(Menu->HistoryButton).Contains(TEXT("Histórico · em breve")));
	});

	It("leaves the app with Esc", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();
		int32 Quits = 0;
		Menu->OnQuit.BindLambda([&Quits]() { ++Quits; });

		TestTrue("taken", Press(*Menu, EKeys::Escape).IsEventHandled());
		TestEqual("quit asked once", Quits, 1);
	});

	It("opens with the training selected and the simulated exam dimmed, nothing else in view", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();
		ExpectSelected(*Menu, EStationSessionMode::Training);
		TestEqual("the arrow fully in view at once", Menu->TrainingArrow ? Menu->TrainingArrow->GetRenderOpacity() : 0.f, 1.f);
	});

	It("selects a mode with a click, without entering it", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();
		TArray<EStationSessionMode> Chosen;
		Menu->OnModeChosen.BindLambda([&Chosen](EStationSessionMode Mode) { Chosen.Add(Mode); });

		Menu->SimulatedExamButton->OnClicked.Broadcast();
		ExpectSelected(*Menu, EStationSessionMode::SimulatedExam);
		Menu->TrainingButton->OnClicked.Broadcast();
		ExpectSelected(*Menu, EStationSessionMode::Training);
		TestEqual("nothing entered", Chosen.Num(), 0);
	});

	It("selects a mode with the arrow keys", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();

		TestTrue("down taken", Press(*Menu, EKeys::Down).IsEventHandled());
		ExpectSelected(*Menu, EStationSessionMode::SimulatedExam);
		TestTrue("up taken", Press(*Menu, EKeys::Up).IsEventHandled());
		ExpectSelected(*Menu, EStationSessionMode::Training);
	});

	It("selects the mode that takes the focus, and rings it", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();

		Menu->SimulatedExamButton->OnReceivedFocus.ExecuteIfBound();
		ExpectSelected(*Menu, EStationSessionMode::SimulatedExam);
		TestEqual("the ring", Menu->SimulatedExamButton->GetStyle().Normal.OutlineSettings.Width, 2.f);
		Menu->SimulatedExamButton->OnLostFocus.ExecuteIfBound();
		TestEqual("the ring gone", Menu->SimulatedExamButton->GetStyle().Normal.OutlineSettings.Width, 0.f);
	});

	It("selects the training again each time the menu opens", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();
		Menu->SimulatedExamButton->OnClicked.Broadcast();

		Menu->SetVisibility(ESlateVisibility::Collapsed);
		Menu->SetVisibility(ESlateVisibility::Visible);
		ExpectSelected(*Menu, EStationSessionMode::Training);
	});

	It("keeps the selection when the menu is only told to stay open", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();
		Menu->SimulatedExamButton->OnClicked.Broadcast();

		Menu->SetVisibility(ESlateVisibility::Visible);
		ExpectSelected(*Menu, EStationSessionMode::SimulatedExam);
	});

	It("enters a mode from its arrow", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();
		TArray<EStationSessionMode> Chosen;
		Menu->OnModeChosen.BindLambda([&Chosen](EStationSessionMode Mode) { Chosen.Add(Mode); });

		Menu->TrainingArrow->OnClicked.Broadcast();
		Menu->SimulatedExamButton->OnClicked.Broadcast();
		Menu->SimulatedExamArrow->OnClicked.Broadcast();
		TestEqual("each its own", Chosen,
			TArray<EStationSessionMode>{EStationSessionMode::Training, EStationSessionMode::SimulatedExam});
	});

	It("enters the selected mode with Enter", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();
		TArray<EStationSessionMode> Chosen;
		Menu->OnModeChosen.BindLambda([&Chosen](EStationSessionMode Mode) { Chosen.Add(Mode); });

		TestTrue("taken", Press(*Menu, EKeys::Enter).IsEventHandled());
		Press(*Menu, EKeys::Down);
		Press(*Menu, EKeys::Enter);
		TestEqual("each in turn", Chosen,
			TArray<EStationSessionMode>{EStationSessionMode::Training, EStationSessionMode::SimulatedExam});
	});

	It("enters the selected mode once however long Enter stays down", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();
		int32 Entered = 0;
		Menu->OnModeChosen.BindLambda([&Entered](EStationSessionMode) { ++Entered; });

		Press(*Menu, EKeys::Enter);
		Press(*Menu, EKeys::Enter, /*bRepeat*/ true);
		TestEqual("once", Entered, 1);
	});

	It("leaves Enter to \"Sair\" while it has the keyboard, so it does not enter a mode instead", [this]()
	{
		UStationMenuWidget* Menu = MakeMenu();
		int32 Entered = 0;
		Menu->OnModeChosen.BindLambda([&Entered](EStationSessionMode) { ++Entered; });
		TSharedRef<SWindow> Window = SNew(SWindow).ClientSize(FVector2f(800.f, 600.f))[Menu->TakeWidget()];
		FSlateApplication::Get().AddWindow(Window, false);

		FSlateApplication::Get().SetUserFocus(0, Menu->QuitButton->TakeWidget(), EFocusCause::Navigation);
		TestFalse("left to the button", Press(*Menu, EKeys::Enter).IsEventHandled());
		TestEqual("no mode entered", Entered, 0);

		FSlateApplication::Get().ClearUserFocus(0);
		FSlateApplication::Get().RequestDestroyWindow(Window);
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
		TestEqual("in the Prova simulada accent", Brief->SimulatedExamButton->GetStyle().Normal.TintColor.GetSpecifiedColor(),
			StationUi::ProvaAccent);
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

	// #425 (#318 T3): the scenario and tasks are read with the time already running.
	It("keeps a simulated exam's scenario and tasks for when its time runs, then shows them over the room", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationSessionMode::SimulatedExam, EStationVoiceMode::Realtime, EStationMicPermission::Granted);
		UStationBriefWidget* Brief = MakeBrief(Flow);
		TestFalse("no scenario or tasks before", IsShown(Brief->BriefBox));
		TestEqual("says when they show", Brief->TimerNote->GetText().ToString(),
			FString(TEXT("O cenário e as tarefas aparecem quando a prova começar, com o tempo já correndo.")));
		TestFalse("no way back to the room yet", IsShown(Brief->CloseButton));

		Flow->Step = EStationRunStep::Running;
		Flow->OpenBrief();
		Brief->Refresh();
		TestTrue("the scenario and tasks", IsShown(Brief->BriefBox));
		TestTrue("its tasks", Texts(Brief->TaskList).Contains(TEXT("•  Obter anamnese dirigida.")));
		TestFalse("no way in any more", IsShown(Brief->SimulatedExamButton));
		TestFalse("no way out to the menu", IsShown(Brief->MenuButton));
		TestFalse("no note on the time", IsShown(Brief->TimerNote));
		TestTrue("back to the room", IsShown(Brief->CloseButton) && Texts(Brief->CloseButton).Contains(TEXT("Voltar ao consultório")));
		Brief->HandleCloseBrief();
		TestFalse("closed", Flow->IsBriefOpen());
	});

	It("shows a training's scenario and tasks on its brief, as before", [this]()
	{
		UStationBriefWidget* Brief = MakeBrief(
			MakeFlow(EStationSessionMode::Training, EStationVoiceMode::Realtime, EStationMicPermission::Granted));
		TestTrue("the scenario and tasks", IsShown(Brief->BriefBox));
		TestEqual("the note on the time", Brief->TimerNote->GetText().ToString(),
			FString(TEXT("O tempo da estação começa a contar quando você entrar.")));
		TestFalse("no way back to a room", IsShown(Brief->CloseButton));
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
