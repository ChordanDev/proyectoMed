// What the in-run HUD shows for a given run (#364): the exam panel, the
// document reader and the conversation. Needs nothing else; the look itself is
// judged on the images of StationHudSnapshotSpec.cpp.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/ContentWidget.h"
#include "Components/EditableTextBox.h"
#include "Components/HorizontalBox.h"
#include "Components/PanelWidget.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Engine/Engine.h"
#include "Station/StationPlayerController.h"
#include "Station/StationRunFlow.h"
#include "Station/StationScreens.h"
#include "Station/StationUi.h"
#include "StationClient.h"

BEGIN_DEFINE_SPEC(FStationHudUnitSpec, "ProyectoMed.StationHud.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)

	UStationRunFlow* MakeFlow(EStationTrainingMode Mode) const;
	UStationHudWidget* MakeHud(UStationRunFlow* Flow) const;
	/** Every text under `Root`, in tree order. */
	static TArray<FString> Texts(UWidget* Root);
	UStationFeedbackWidget* MakeFeedback(UStationRunFlow* Flow) const;
END_DEFINE_SPEC(FStationHudUnitSpec)

UStationRunFlow* FStationHudUnitSpec::MakeFlow(EStationTrainingMode Mode) const
{
	UStationRunFlow* Flow = NewObject<UStationRunFlow>();
	Flow->Step = EStationRunStep::Running;
	Flow->Mode = Mode;
	Flow->Voice.State = EStationVoiceState::Ready;
	return Flow;
}

UStationHudWidget* FStationHudUnitSpec::MakeHud(UStationRunFlow* Flow) const
{
	UStationHudWidget* Hud = CreateWidget<UStationHudWidget>(GEngine->GetWorldContexts()[0].World());
	Hud->TakeWidget();
	Hud->SetFlow(Flow);
	Hud->Refresh();
	return Hud;
}

UStationFeedbackWidget* FStationHudUnitSpec::MakeFeedback(UStationRunFlow* Flow) const
{
	UStationFeedbackWidget* Feedback = CreateWidget<UStationFeedbackWidget>(GEngine->GetWorldContexts()[0].World());
	Feedback->TakeWidget();
	Feedback->SetFlow(Flow);
	Feedback->Refresh();
	return Feedback;
}

TArray<FString> FStationHudUnitSpec::Texts(UWidget* Root)
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

void FStationHudUnitSpec::Define()
{
	It("names the control the training shows when no exam was requested yet, and follows a lost voice", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		UStationHudWidget* Hud = MakeHud(Flow);
		TestTrue(TEXT("the microphone while the voice works"),
			Texts(Hud->ExamCardBox).Contains(TEXT("Nenhum exame solicitado ainda. Segure o microfone e diga o que você solicita.")));

		Flow->Voice.bLost = true;
		Hud->Refresh();
		const TArray<FString> AfterLoss = Texts(Hud->ExamCardBox);
		TestTrue(TEXT("the typed box once the voice is lost"),
			AfterLoss.Contains(TEXT("Nenhum exame solicitado ainda. Descreva abaixo o que você solicita.")));
		TestFalse(TEXT("no longer the hidden microphone"),
			AfterLoss.Contains(TEXT("Nenhum exame solicitado ainda. Segure o microfone e diga o que você solicita.")));
	});

	// #419: the talk button, for touch screens, does what the space bar does.
	It("shows the talk button in a voice training, and how to cut the patient while it answers", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		UStationHudWidget* Hud = MakeHud(Flow);
		TestEqual(TEXT("shown while the voice works"), Hud->TalkButton->GetVisibility(), ESlateVisibility::Visible);
		TestEqual(TEXT("hold to talk"), Hud->TalkText->GetText().ToString(), FString(TEXT("Segure para falar (Espaço)")));

		FStationVoiceEvent Sent;
		Sent.Kind = EStationVoiceEventKind::Learner;
		Sent.TurnId = 1;
		Sent.Text = TEXT("Onde dói?");
		Sent.bFinal = true;
		Flow->HandleVoiceEvent(Sent);
		Hud->Refresh();
		TestEqual(TEXT("while the patient answers"), Hud->TalkText->GetText().ToString(),
			FString(TEXT("Toque e segure para interromper")));

		Flow->Voice.bLost = true;
		Hud->Refresh();
		TestEqual(TEXT("hidden once the voice is lost"), Hud->TalkButton->GetVisibility(), ESlateVisibility::Collapsed);

		UStationHudWidget* Text = MakeHud(MakeFlow(EStationTrainingMode::Text));
		TestEqual(TEXT("never in a text training"), Text->TalkButton->GetVisibility(), ESlateVisibility::Collapsed);
	});

	It("does not show a press the flow refused as recording", [this]()
	{
		// The previous spoken request still waits for Phoenix's answer.
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		Flow->SpokenExamTurn = 1;
		Flow->SpokenExamText = TEXT("Solicito hemograma");
		UStationHudWidget* Hud = MakeHud(Flow);

		Hud->HandleAskExamAloud();
		TestFalse(TEXT("not the recording look"), Hud->MicrophoneLook == UStationHudWidget::EMicrophoneLook::Recording);
		TestEqual(TEXT("tells the learner to wait"), Hud->ExamAloudText->GetText().ToString(),
			FString(TEXT("Aguarde a resposta do pedido anterior")));

		Hud->HandleReleaseExamAloud();
		TestEqual(TEXT("idle once released"), Hud->ExamAloudText->GetText().ToString(),
			FString(TEXT("Segure para pedir (Shift + Espaço)")));
	});

	// #419: a press refused because the patient answers waits for nothing.
	It("does not ask to wait for a press refused while the patient answers", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		FStationVoiceEvent Sent;
		Sent.Kind = EStationVoiceEventKind::Learner;
		Sent.TurnId = 1;
		Sent.Text = TEXT("Onde dói?");
		Sent.bFinal = true;
		Flow->HandleVoiceEvent(Sent);
		UStationHudWidget* Hud = MakeHud(Flow);

		Hud->HandleAskExamAloud();
		TestFalse(TEXT("not the waiting look"), Hud->MicrophoneLook == UStationHudWidget::EMicrophoneLook::Waiting);
		TestEqual(TEXT("still the idle hint"), Hud->ExamAloudText->GetText().ToString(),
			FString(TEXT("Segure para pedir (Shift + Espaço)")));
		Hud->HandleReleaseExamAloud();
	});

	// #419: the space bar, the talk button and the exam button share one talk key.
	It("leaves a hold of the space bar alone when the exam button is pressed and released", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		UStationHudWidget* Hud = MakeHud(Flow);
		Flow->TalkKey.Press(FPlatformTime::Seconds(), false); // the space bar is held

		Hud->HandleAskExamAloud();
		Hud->HandleReleaseExamAloud();
		TestTrue(TEXT("the space bar still holds the talk key"), Flow->IsTalking());

		Hud->HandlePressTalk();
		Hud->HandleReleaseTalk();
		TestTrue(TEXT("nor does the talk button end it"), Flow->IsTalking());
	});

	It("records while a press the flow took is held", [this]()
	{
		// Phoenix armed the mode for this press: the flow listens for the request.
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		Flow->SpokenExamExpiresAt = FPlatformTime::Seconds() + 20.0;
		UStationHudWidget* Hud = MakeHud(Flow);
		Hud->bMicrophoneHeld = true;
		Hud->bMicrophoneAccepted = true;
		Hud->RefreshMicrophone();
		TestTrue(TEXT("the recording look"), Hud->MicrophoneLook == UStationHudWidget::EMicrophoneLook::Recording);
		TestTrue(TEXT("says it records"), Hud->ExamAloudText->GetText().ToString().StartsWith(TEXT("Gravando")));
	});

	It("links a request's document from its card and lists a document a turn to the examiner released apart", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Text);
		FStationImpresso BloodCount;
		BloodCount.Id = TEXT("hemograma");
		BloodCount.Title = TEXT("IMPRESSO 2 — Hemograma completo");
		FStationImpresso Physical;
		Physical.Id = TEXT("exame-fisico");
		Physical.Title = TEXT("IMPRESSO 1 — EXAME FÍSICO SEGMENTAR");
		FStationExamRequest& Request = Flow->ExamRequests.AddDefaulted_GetRef();
		Request.Text = TEXT("Hemograma");
		Request.Reply.Decision = EStationImpressoDecision::Released;
		Request.Reply.NewlyReleased.Add(BloodCount);
		Flow->ReleasedImpressos = {BloodCount, Physical};

		const TArray<FString> Shown = Texts(MakeHud(Flow)->ExamCardBox);
		TestTrue(TEXT("the request"), Shown.Contains(TEXT("Hemograma")));
		TestTrue(TEXT("its status"), Shown.Contains(TEXT("Liberado")));
		TestTrue(TEXT("its document's link"), Shown.Contains(TEXT("Ver documento  ›")));
		TestTrue(TEXT("the other documents"), Shown.Contains(TEXT("Outros documentos liberados")));
		TestTrue(TEXT("the examiner's document, by title"), Shown.Contains(TEXT("IMPRESSO 1 — EXAME FÍSICO SEGMENTAR  ›")));
		TestFalse(TEXT("the request's document only once"), Shown.Contains(TEXT("IMPRESSO 2 — Hemograma completo  ›")));
	});

	It("wraps every text of the request cards at a fixed width, so a rebuilt list never jumps", [this]()
	{
		// Auto wrap lays a new text out unwrapped for one frame, wider and shorter
		// than it ends, so the whole list jumped when an answer rebuilt it.
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		FStationImpresso Physical;
		Physical.Id = TEXT("exame-fisico");
		Physical.Title = TEXT("IMPRESSO 1 — EXAME FÍSICO SEGMENTAR");
		FStationImpresso Other;
		Other.Id = TEXT("ecg");
		Other.Title = TEXT("IMPRESSO 4 — ELETROCARDIOGRAMA");
		FStationExamRequest& Released = Flow->ExamRequests.AddDefaulted_GetRef();
		Released.Text = TEXT("Solicito exame físico do abdome e dos membros inferiores");
		Released.Reply.Decision = EStationImpressoDecision::Released;
		Released.Reply.NewlyReleased.Add(Physical);
		FStationExamRequest& Declined = Flow->ExamRequests.AddDefaulted_GetRef();
		Declined.Text = TEXT("Solicito bonecografia");
		Declined.Reply.Decision = EStationImpressoDecision::Unavailable;
		Declined.Reply.FeedbackMessage = TEXT("Não consta no script.");
		Flow->ReleasedImpressos = {Physical, Other};
		Flow->SpokenExamTurn = 3;
		Flow->SpokenExamText = TEXT("Solicito exame físico");
		UStationHudWidget* Hud = MakeHud(Flow);

		int32 Checked = 0;
		TArray<FString> Wrapped;
		UWidgetTree::ForWidgetAndChildren(Hud->ExamCardBox, [this, &Checked, &Wrapped](UWidget* Widget)
		{
			if (const UTextBlock* Text = Cast<UTextBlock>(Widget))
			{
				++Checked;
				const FString Shown = Text->GetText().ToString();
				TestFalse(*FString::Printf(TEXT("'%s' is not auto wrapped"), *Shown), Text->GetAutoWrapText());
				if (Text->GetWrapTextAt() > 0.f)
				{
					Wrapped.Add(Shown);
				}
			}
		});
		TestTrue(TEXT("the cards' texts were checked"), Checked >= 8);
		// The status labels stay on one line; every longer text wraps at a fixed width.
		for (const TCHAR* Long : {TEXT("Solicito exame físico do abdome e dos membros inferiores"),
			TEXT("Não consta no script."), TEXT("Ver documento  ›"), TEXT("Outros documentos liberados"),
			TEXT("IMPRESSO 4 — ELETROCARDIOGRAMA  ›")})
		{
			TestTrue(*FString::Printf(TEXT("'%s' wraps at a fixed width"), Long), Wrapped.Contains(FString(Long)));
		}
	});

	It("shows a released document's headings, labels and items in Phoenix's order and words", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Text);
		FStationImpresso& Document = Flow->ReleasedImpressos.AddDefaulted_GetRef();
		Document.Id = TEXT("lab");
		Document.Title = TEXT("IMPRESSO 2 — EXAMES LABORATORIAIS");
		Document.Category = TEXT("laboratorio");
		Document.Content = TEXT("**Hemograma completo:**\n\n- Hemoglobina: 14,6 g/dL.\n- **Estado geral:** regular, **consciente**.\nTexto livre.\n");
		UStationHudWidget* Hud = MakeHud(Flow);
		Hud->OpenDocument(TEXT("lab"));

		TestEqual(TEXT("the category"), Hud->DocumentCategoryText->GetText().ToString(), FString(TEXT("Exames laboratoriais")));
		TestEqual(TEXT("the title"), Hud->DocumentTitleText->GetText().ToString(), FString(TEXT("IMPRESSO 2 — EXAMES LABORATORIAIS")));
		TestEqual(TEXT("every line, in order"), Texts(Hud->DocumentBody), TArray<FString>{
			TEXT("Hemograma completo:"),
			TEXT("•  Hemoglobina: 14,6 g/dL."),
			TEXT("Estado geral:"),
			TEXT("regular, consciente."),
			TEXT("Texto livre.")});
		TestEqual(TEXT("the reader is open"), Hud->DocumentViewer->GetVisibility(), ESlateVisibility::Visible);
	});

	// #462: the document's dim stops at the requests, which stay in reach beside the sheet.
	It("keeps the exam requests over the dimmed scene while a document is open", [this]()
	{
		UStationHudWidget* Hud = MakeHud(MakeFlow(EStationTrainingMode::Text));
		const UPanelWidget* Root = Cast<UPanelWidget>(Hud->GetRootWidget());
		TestTrue(TEXT("the drawer over the dim"), Root->GetChildIndex(Hud->ExamDrawer) > Root->GetChildIndex(Hud->DocumentViewer));
		TestTrue(TEXT("the dim over the time"), Root->GetChildIndex(Hud->DocumentViewer) > Root->GetChildIndex(Hud->TimerPanel));
	});

	It("outlines the request cards and their status labels, in the Cine look", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Text);
		FStationExamRequest& Request = Flow->ExamRequests.AddDefaulted_GetRef();
		Request.Text = TEXT("Hemograma");
		Request.Reply.Decision = EStationImpressoDecision::Unavailable;
		UStationHudWidget* Hud = MakeHud(Flow);

		int32 Outlined = 0;
		UWidgetTree::ForWidgetAndChildren(Hud->ExamCardBox, [&Outlined](UWidget* Widget)
		{
			if (const UBorder* Border = Cast<UBorder>(Widget))
			{
				Outlined += Border->Background.OutlineSettings.Width > 0.f ? 1 : 0;
			}
		});
		TestEqual(TEXT("the card and its status label"), Outlined, 2);
	});

	It("redraws the conversation only when what it shows changes", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		Flow->Transcript.Add({EStationSpeaker::Learner, TEXT("Onde dói?")});
		UStationHudWidget* Hud = MakeHud(Flow);
		const UWidget* First = Hud->TranscriptBox->GetChildAt(0);

		Hud->Refresh();
		TestTrue(TEXT("kept on a change it does not show"), Hud->TranscriptBox->GetChildAt(0) == First);

		Flow->Voice.LearnerText = TEXT("Quando");
		Hud->Refresh();
		TestTrue(TEXT("redrawn for the live caption"), Hud->TranscriptBox->GetChildAt(0) != First);
		TestEqual(TEXT("the line and the caption"), Hud->TranscriptBox->GetChildrenCount(), 2);
	});

	It("lets the scene show through its panels, but not through what the learner reads or types (#444)", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Text);
		Flow->Transcript.Add({EStationSpeaker::Learner, TEXT("Onde dói?")});
		Flow->Transcript.Add({EStationSpeaker::Patient, TEXT("Na barriga, doutor.")});
		FStationImpresso BloodCount;
		BloodCount.Id = TEXT("hemograma");
		BloodCount.Title = TEXT("IMPRESSO 2 — Hemograma completo");
		FStationExamRequest& Request = Flow->ExamRequests.AddDefaulted_GetRef();
		Request.Text = TEXT("Hemograma");
		Request.Reply.Decision = EStationImpressoDecision::Released;
		Request.Reply.NewlyReleased.Add(BloodCount);
		Flow->ReleasedImpressos = {BloodCount};
		UStationHudWidget* Hud = MakeHud(Flow);

		const auto Alpha = [](const FSlateBrush& Brush) { return Brush.TintColor.GetSpecifiedColor().A; };
		const auto Borders = [](UWidget* Root)
		{
			TArray<UBorder*> Found;
			UWidgetTree::ForWidgetAndChildren(Root, [&Found](UWidget* Widget)
			{
				if (UBorder* Border = Cast<UBorder>(Widget))
				{
					Found.Add(Border);
				}
			});
			return Found;
		};

		// The timer, the conversation, the exam drawer and the two buttons' grounds: the panel's
		// colour. The exam cards share it, opaque; they are checked below.
		const TArray<UBorder*> Cards = Borders(Hud->ExamCardBox);
		int32 Panels = 0;
		for (UBorder* Border : Borders(Hud->GetRootWidget()))
		{
			const FLinearColor Fill = Border->Background.TintColor.GetSpecifiedColor();
			if (!Cards.Contains(Border) && Fill.Equals(StationUi::Panel.CopyWithNewOpacity(Fill.A)))
			{
				++Panels;
				TestTrue(TEXT("a panel is translucent"), Fill.A < 1.f);
			}
		}
		TestEqual(TEXT("the timer, the conversation, the exam drawer and the side buttons"), Panels, 5);

		const TArray<UBorder*> Bubbles = Borders(Hud->TranscriptBox);
		TestEqual(TEXT("one bubble per line"), Bubbles.Num(), 2);
		for (UBorder* Bubble : Bubbles)
		{
			TestEqual(TEXT("a bubble is opaque"), Alpha(Bubble->Background), 1.f);
		}

		TestTrue(TEXT("the request's card"), Cards.Num() > 0);
		for (UBorder* Card : Cards)
		{
			TestEqual(TEXT("an exam card is opaque"), Alpha(Card->Background), 1.f);
		}

		for (UEditableTextBox* Input : {Hud->TurnInput.Get(), Hud->ExamInput.Get()})
		{
			const FEditableTextBoxStyle& Style = Input->GetWidgetStyle();
			TestEqual(TEXT("an input is opaque"), Alpha(Style.BackgroundImageNormal), 1.f);
			TestEqual(TEXT("an input is opaque while hovered"), Alpha(Style.BackgroundImageHovered), 1.f);
			TestEqual(TEXT("an input is opaque while focused"), Alpha(Style.BackgroundImageFocused), 1.f);
		}

		int32 Sheets = 0;
		for (UBorder* Border : Borders(Hud->DocumentViewer))
		{
			if (Border->Background.TintColor.GetSpecifiedColor().Equals(StationUi::Paper))
			{
				++Sheets;
			}
		}
		TestEqual(TEXT("the document's sheet is opaque paper"), Sheets, 1);
	});

	// #422: a simulated exam is voice only; impressos are asked aloud with "Exames".
	It("offers no typed turn and no typed exam request in a simulated exam, even once the voice is lost", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		Flow->SessionMode = EStationSessionMode::SimulatedExam;
		UStationHudWidget* Hud = MakeHud(Flow);
		TestEqual(TEXT("no typed turn"), Hud->TurnRow->GetVisibility(), ESlateVisibility::Collapsed);
		TestEqual(TEXT("no typed exam request"), Hud->ExamTypedRow->GetVisibility(), ESlateVisibility::Collapsed);
		TestEqual(TEXT("the spoken exam request"), Hud->MicrophoneBox->GetVisibility(), ESlateVisibility::Visible);

		Flow->Voice.bLost = true;
		Hud->Refresh();
		TestEqual(TEXT("still no typed turn"), Hud->TurnRow->GetVisibility(), ESlateVisibility::Collapsed);
		TestEqual(TEXT("still no typed exam request"), Hud->ExamTypedRow->GetVisibility(), ESlateVisibility::Collapsed);
		TestFalse(TEXT("never points to a typed box"),
			Texts(Hud->ExamCardBox).Contains(TEXT("Nenhum exame solicitado ainda. Descreva abaixo o que você solicita.")));
	});

	It("names a simulated exam that lost its voice on the invalidated screen", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		Flow->SessionMode = EStationSessionMode::SimulatedExam;
		Flow->Step = EStationRunStep::Invalidated;
		Flow->Invalidation = EStationInvalidation::VoiceLost;
		UStationInvalidatedWidget* Screen = CreateWidget<UStationInvalidatedWidget>(GEngine->GetWorldContexts()[0].World());
		Screen->TakeWidget();
		Screen->SetFlow(Flow);
		Screen->Refresh();
		TestEqual(TEXT("the title"), Screen->TitleText->GetText().ToString(), FString(TEXT("Prova simulada invalidada")));
		TestEqual(TEXT("why"), Screen->BodyText->GetText().ToString(),
			StationInvalidatedText(EStationSessionMode::SimulatedExam, EStationInvalidation::VoiceLost).ToString());
	});

	// Jorge J2 on #441: a microphone that will not open invalidates a simulated exam while
	// the screens render, and the invalidated screen must still get the mouse and keys.
	It("leaves the invalidated screen in UI-only input when a simulated exam's microphone fails while rendering", [this]()
	{
		UWorld* World = GEngine->GetWorldContexts()[0].World();
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		Flow->SessionMode = EStationSessionMode::SimulatedExam;
		Flow->Client = NewObject<UStationClient>();
		AStationPlayerController* Controller = World->SpawnActor<AStationPlayerController>();
		Controller->Flow = Flow;
		Controller->Menu = CreateWidget<UStationMenuWidget>(World);
		Controller->Notice = CreateWidget<UStationNoticeWidget>(World);
		Controller->Brief = CreateWidget<UStationBriefWidget>(World);
		Controller->Hud = CreateWidget<UStationHudWidget>(World);
		Controller->Feedback = CreateWidget<UStationFeedbackWidget>(World);
		Controller->Invalidated = CreateWidget<UStationInvalidatedWidget>(World);
		Controller->MicrophoneScreen = CreateWidget<UStationMicrophoneWidget>(World);
		for (UUserWidget* Screen : TArray<UUserWidget*>{Controller->Menu, Controller->Notice, Controller->Brief, Controller->Hud,
				 Controller->Feedback, Controller->Invalidated, Controller->MicrophoneScreen})
		{
			Screen->TakeWidget();
		}
		Controller->Hud->SetFlow(Flow);
		Controller->Brief->SetFlow(Flow);
		Controller->Feedback->SetFlow(Flow);
		Controller->Invalidated->SetFlow(Flow);
		Flow->OnChanged.AddUObject(Controller, &AStationPlayerController::Render);
		Controller->MicrophoneUpdate = [Flow]() { Flow->ReportMicrophoneUnavailable(); };

		Controller->Render();
		TestEqual(TEXT("invalidated"), Flow->GetStep(), EStationRunStep::Invalidated);
		TestTrue(TEXT("an input mode applied"), Controller->bAppliedRunInputMode.IsSet());
		TestFalse(TEXT("UI only, not the run's game and UI"), Controller->bAppliedRunInputMode.Get(true));

		// A training goes on in writing (#196), so it keeps the run's input mode.
		Flow->SessionMode = EStationSessionMode::Training;
		Flow->Step = EStationRunStep::Running;
		Flow->Voice.bMicrophoneUnavailable = false;
		Controller->Render();
		TestEqual(TEXT("a training still runs"), Flow->GetStep(), EStationRunStep::Running);
		TestTrue(TEXT("with the run's game and UI"), Controller->bAppliedRunInputMode.Get(false));
		Controller->Destroy();
	});

	// #426: a Prova simulada's result, with two criteria on a ten-point station.
	auto ExamResult = []()
	{
		FStationCriterionResult Assessed;
		Assessed.Description = TEXT("Pergunta sobre a migração da dor.");
		Assessed.Status = EStationCriterionStatus::Assessed;
		Assessed.Level = TEXT("parcialmente_adequado");
		Assessed.Points = TEXT("6");
		Assessed.MaxPoints = TEXT("8");
		FStationEvidence Excerpt;
		Excerpt.Speaker = EStationSpeaker::Learner;
		Excerpt.Text = TEXT("A dor mudou de lugar?");
		Assessed.Evidence.Add(Excerpt);
		Assessed.Recommendation = TEXT("Pergunte também a intensidade.");
		FStationCriterionResult LeftOut;
		LeftOut.Description = TEXT("Orienta sobre sinais de alarme.");
		LeftOut.Status = EStationCriterionStatus::Uncertain;
		FStationResult Result;
		Result.Criteria = {Assessed, LeftOut};
		Result.ScoredSubtotal = TEXT("6");
		Result.ScoredMax = TEXT("8");
		Result.EligibleMax = TEXT("10");
		Result.ScaledTotal = TEXT("7.5");
		Result.CertaintyLevel = 4;
		Result.bIncomplete = true;
		return Result;
	};
	auto GradedFlow = [this](const FStationResult& Result, EStationSessionMode SessionMode)
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		Flow->SessionMode = SessionMode;
		Flow->Step = EStationRunStep::Feedback;
		Flow->Result = Result;
		return Flow;
	};
	const FString Disclaimer = TEXT(
		"Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica aprovação, reprovação, certificação ou prontidão para o exame.");

	It("shows a Prova simulada's scaled total, certainty and what was left out (#426)", [this, ExamResult, GradedFlow, Disclaimer]()
	{
		UStationFeedbackWidget* Feedback = MakeFeedback(GradedFlow(ExamResult(), EStationSessionMode::SimulatedExam));
		const TArray<FString> Shown = Texts(Feedback->ExamScreen);
		TestEqual("its own layout", Feedback->ExamScreen->GetVisibility(), ESlateVisibility::Visible);
		TestEqual("not the training's card", Feedback->CardScreen->GetVisibility(), ESlateVisibility::Collapsed);
		TestTrue("the scaled total, with a comma", Shown.Contains(TEXT("7,5")));
		TestTrue("of the full maximum", Shown.Contains(TEXT("de 10")));
		TestTrue("the label", Shown.Contains(TEXT("Quase certeira")));
		TestTrue("Phoenix's points, no percentage", Shown.Contains(TEXT("8 dos 10 pontos da estação foram avaliados.")));
		TestTrue("the notice names what was left out", Shown.Contains(
			TEXT("Nota incompleta. Ficou de fora: Critério 2 (incerto). O total foi estimado sem ele.")));
		TestTrue("the disclaimer", Shown.Contains(Disclaimer));
		TestTrue("the outcome", Shown.Contains(TEXT("Parcialmente adequado")));
		TestTrue("exact points", Shown.Contains(TEXT("6 / 8")));
		TestTrue("no points for what was left out", Shown.Contains(TEXT("sem pontos")));
		TestTrue("no fictional mark on a real result", Feedback->ExamSampleMark->GetVisibility() == ESlateVisibility::Collapsed);
		// The result is already stored when this screen shows: leaving does not lose it.
		TestFalse("no claim that the attempt is gone", Shown.ContainsByPredicate(
			[](const FString& Text) { return Text.Contains(TEXT("não poderá ser recuperada")); }));
		for (const FString& Text : Shown)
		{
			for (const TCHAR* Claim : {TEXT("Aprovado"), TEXT("Reprovado"), TEXT("Certificado"), TEXT("Pronto para")})
			{
				TestFalse(*FString::Printf(TEXT("no claim of %s"), Claim), Text.Contains(Claim));
			}
		}
	});

	It("lights one step of the meter per certainty level (#426)", [this, ExamResult, GradedFlow]()
	{
		for (int32 Level = 1; Level <= 5; ++Level)
		{
			FStationResult Result = ExamResult();
			Result.CertaintyLevel = Level;
			UStationFeedbackWidget* Feedback = MakeFeedback(GradedFlow(Result, EStationSessionMode::SimulatedExam));
			TestEqual("five steps", Feedback->ExamMeter->GetChildrenCount(), 5);
			int32 Lit = 0;
			for (int32 Step = 0; Step < Feedback->ExamMeter->GetChildrenCount(); ++Step)
			{
				const UBorder* Segment = Cast<UBorder>(CastChecked<UContentWidget>(Feedback->ExamMeter->GetChildAt(Step))->GetContent());
				Lit += Segment->Background.TintColor.GetSpecifiedColor() == FSlateColor(StationUi::PanelEdge).GetSpecifiedColor() ? 0 : 1;
			}
			TestEqual(*FString::Printf(TEXT("level %d"), Level), Lit, Level);
		}
	});

	It("names the five certainty levels (#426)", [this]()
	{
		TestEqual("5", StationCertaintyLabel(5).ToString(), TEXT("Certeira"));
		TestEqual("4", StationCertaintyLabel(4).ToString(), TEXT("Quase certeira"));
		TestEqual("3", StationCertaintyLabel(3).ToString(), TEXT("Parcialmente certeira"));
		TestEqual("2", StationCertaintyLabel(2).ToString(), TEXT("Pouco certeira"));
		TestEqual("1", StationCertaintyLabel(1).ToString(), TEXT("Insuficiente"));
	});

	It("shows no total at level 1, but still what was left out (#426)", [this, ExamResult, GradedFlow, Disclaimer]()
	{
		FStationResult Result = ExamResult();
		Result.Criteria[0].Status = EStationCriterionStatus::Uncertain;
		Result.Criteria[1].Status = EStationCriterionStatus::NotObservable;
		Result.ScoredMax = TEXT("3");
		Result.ScaledTotal.Empty();
		Result.CertaintyLevel = 1;
		const TArray<FString> Shown = Texts(MakeFeedback(GradedFlow(Result, EStationSessionMode::SimulatedExam))->ExamScreen);
		TestTrue("no total", Shown.Contains(TEXT("Sem total nesta tentativa")));
		TestFalse("not of the maximum either", Shown.Contains(TEXT("de 10")));
		TestTrue("the label", Shown.Contains(TEXT("Insuficiente")));
		TestTrue("the notice, with nothing about a total", Shown.Contains(
			TEXT("Nota incompleta. Ficaram de fora: Critério 1 (incerto), Critério 2 (não observável).")));
		TestTrue("the disclaimer", Shown.Contains(Disclaimer));
	});

	It("warns harder at level 2 and not at all at full coverage (#426)", [this, ExamResult]()
	{
		FStationResult Result = ExamResult();
		Result.CertaintyLevel = 2;
		TestTrue("strong", StationIncompleteNotice(Result).ToString().StartsWith(
			TEXT("Nota incompleta e pouco certeira: leia este total com cautela.")));
		Result.bIncomplete = false;
		TestTrue("nothing left out, nothing to warn of", StationIncompleteNotice(Result).IsEmpty());
	});

	It("opens a criterion's evidence and recommendation from its row (#426)", [this, ExamResult, GradedFlow]()
	{
		UStationFeedbackWidget* Feedback = MakeFeedback(GradedFlow(ExamResult(), EStationSessionMode::SimulatedExam));
		TestEqual("one row per criterion", Feedback->ExamRows.Num(), 2);
		UWidget* Details = Feedback->ExamRows[0]->Details;
		const TArray<FString> Inside = Texts(Details);
		TestTrue("the evidence", Inside.ContainsByPredicate(
			[](const FString& Text) { return Text.Contains(TEXT("A dor mudou de lugar?")); }));
		TestTrue("the recommendation", Inside.Contains(TEXT("Pergunte também a intensidade.")));
		TestEqual("closed at first", Details->GetVisibility(), ESlateVisibility::Collapsed);
		Feedback->ExamRows[0]->HandleClicked();
		TestEqual("opened", Details->GetVisibility(), ESlateVisibility::Visible);
		Feedback->ExamRows[0]->HandleClicked();
		TestEqual("closed again", Details->GetVisibility(), ESlateVisibility::Collapsed);
	});

	It("keeps a training's result in its card, with its total (#426)", [this, GradedFlow]()
	{
		FStationResult Result;
		Result.ScoredSubtotal = TEXT("6");
		Result.ScoredMax = TEXT("8");
		Result.EligibleMax = TEXT("8");
		Result.EstimatedTotal = TEXT("6");
		UStationFeedbackWidget* Feedback = MakeFeedback(GradedFlow(Result, EStationSessionMode::Training));
		TestEqual("the card", Feedback->CardScreen->GetVisibility(), ESlateVisibility::Visible);
		TestEqual("no exam layout", Feedback->ExamScreen->GetVisibility(), ESlateVisibility::Collapsed);
		TestTrue("the total", Texts(Feedback->CardScreen).Contains(TEXT("Total educacional: 6")));
	});

	// #425: a learner's remark to the examiner, which Phoenix notes without a reply.
	auto NoteExaminer = [](UStationRunFlow& Flow)
	{
		FStationVoiceEvent Spoken;
		Spoken.Kind = EStationVoiceEventKind::Learner;
		Spoken.TurnId = 1;
		Spoken.bFinal = true;
		Spoken.Text = TEXT("Vou examinar o abdome.");
		Flow.HandleVoiceEvent(Spoken);
		FStationVoiceEvent Noted;
		Noted.Kind = EStationVoiceEventKind::ExaminerAcknowledged;
		Noted.TurnId = 1;
		Flow.HandleVoiceEvent(Noted);
	};

	It("shows no countdown and no examiner's note in a simulated exam, and keeps its brief at hand", [this, NoteExaminer]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		Flow->SessionMode = EStationSessionMode::SimulatedExam;
		NoteExaminer(*Flow);
		UStationHudWidget* Hud = MakeHud(Flow);
		TestEqual("no countdown", Hud->TimerText->GetVisibility(), ESlateVisibility::Collapsed);
		TestEqual("named a simulated exam", Hud->ModeText->GetText().ToString(), FString(TEXT("Prova simulada")));
		TestFalse("no \"Anotado.\"", Texts(Hud->TranscriptBox).Contains(TEXT("Examinador: Anotado.")));
		TestTrue("the remark is shown", Texts(Hud->TranscriptBox).Contains(TEXT("Vou examinar o abdome.")));
		TestEqual("the brief at hand", Hud->BriefButton->GetVisibility(), ESlateVisibility::Visible);
		TestTrue("its label", Texts(Hud->BriefButton).Contains(TEXT("Cenário e tarefas")));
		Hud->HandleOpenBrief();
		TestTrue("opens the brief", Flow->IsBriefOpen());
	});

	It("keeps the countdown and the examiner's note in a training", [this, NoteExaminer]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		NoteExaminer(*Flow);
		UStationHudWidget* Hud = MakeHud(Flow);
		TestEqual("the countdown", Hud->TimerText->GetVisibility(), ESlateVisibility::Visible);
		TestEqual("named a training", Hud->ModeText->GetText().ToString(), FString(TEXT("Treino por voz")));
		TestTrue("\"Anotado.\"", Texts(Hud->TranscriptBox).Contains(TEXT("Examinador: Anotado.")));
		TestEqual("the brief at hand", Hud->BriefButton->GetVisibility(), ESlateVisibility::Visible);
	});

	It("names a text training", [this]()
	{
		TestEqual("named", MakeHud(MakeFlow(EStationTrainingMode::Text))->ModeText->GetText().ToString(), FString(TEXT("Treino por texto")));
	});

	// #461: the time left until the deadline, then the time past it in the exam accent.
	It("turns the timer into the overtime at the deadline, and back", [this]()
	{
		UStationHudWidget* Hud = MakeHud(MakeFlow(EStationTrainingMode::Voice));
		const auto Color = [Hud]() { return Hud->TimerText->GetColorAndOpacity().GetSpecifiedColor(); };

		Hud->ShowStationTime(FTimespan::FromSeconds(462));
		TestEqual("counts down", Hud->TimerText->GetText().ToString(), FString(TEXT("07:42")));
		TestTrue("the time left", Texts(Hud->GetRootWidget()).Contains(TEXT("Tempo restante")));
		TestEqual("in white", Color(), StationUi::InkTitle);

		Hud->ShowStationTime(FTimespan::Zero());
		TestEqual("zero is still the deadline", Hud->TimerText->GetText().ToString(), FString(TEXT("00:00")));
		TestTrue("not past it yet", Texts(Hud->GetRootWidget()).Contains(TEXT("Tempo restante")));

		Hud->ShowStationTime(FTimespan::FromSeconds(-200));
		TestEqual("counts up", Hud->TimerText->GetText().ToString(), FString(TEXT("+03:20")));
		const TArray<FString> Shown = Texts(Hud->GetRootWidget());
		TestTrue("says so", Shown.Contains(TEXT("Tempo esgotado · além do tempo")));
		TestFalse("no time left", Shown.Contains(TEXT("Tempo restante")));
		TestEqual("in the exam accent", Color(), StationUi::ProvaAccent);

		// Phoenix re-anchored the clock, which ran ahead of its own.
		Hud->ShowStationTime(FTimespan::FromSeconds(3));
		TestEqual("in white again", Color(), StationUi::InkTitle);
	});

	It("keeps the voice states' copy", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		UStationHudWidget* Hud = MakeHud(Flow);
		const auto Status = [Flow, Hud]()
		{
			Hud->Refresh();
			return Hud->VoiceStatusText->GetText().ToString();
		};
		TestEqual("ready", Status(), FString(TEXT("Voz conectada")));
		Flow->Voice.State = EStationVoiceState::Connecting;
		TestEqual("connecting", Status(), FString(TEXT("Conectando a voz...")));
		Flow->Voice.State = EStationVoiceState::Reconnecting;
		TestEqual("reconnecting", Status(), FString(TEXT("Reconectando a voz...")));
		Flow->Voice.bMicrophoneUnavailable = true;
		TestEqual("no microphone", Status(), FString(TEXT("Microfone indisponível. Continue por escrito.")));
		Flow->Voice.bLost = true;
		TestEqual("lost", Status(), FString(TEXT("A voz caiu. O tempo da estação continua.")));
	});

	// #239: the brief, over the scene, while the clock goes on.
	It("opens a training's brief over the scene and goes on with the run", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		FStationSummary Station;
		Station.DisplayTitle = TEXT("Abdome agudo");
		Station.Scenario = TEXT("Pronto atendimento de um hospital geral.");
		Station.Tasks = {TEXT("Faça a anamnese."), TEXT("Solicite exames.")};
		Flow->Station = Station;
		UStationHudWidget* Hud = MakeHud(Flow);
		TestEqual("closed at first", Hud->BriefReader->GetVisibility(), ESlateVisibility::Collapsed);

		Hud->HandleOpenBrief();
		TestEqual("open", Hud->BriefReader->GetVisibility(), ESlateVisibility::Visible);
		const TArray<FString> Shown = Texts(Hud->BriefReader);
		TestTrue("the heading", Shown.Contains(TEXT("Treino · Cenário e tarefas")));
		TestTrue("the title", Shown.Contains(TEXT("Abdome agudo")));
		TestTrue("the scenario", Shown.Contains(TEXT("Pronto atendimento de um hospital geral.")));
		TestTrue("the first task", Shown.Contains(TEXT("•  Faça a anamnese.")));
		TestTrue("the second task", Shown.Contains(TEXT("•  Solicite exames.")));
		TestTrue("the way back", Shown.Contains(TEXT("Voltar ao consultório")));
		TestEqual("the run goes on", Flow->GetStep(), EStationRunStep::Running);
		TestFalse("the exam's brief stays closed", Flow->IsBriefOpen());
		const UPanelWidget* Root = Cast<UPanelWidget>(Hud->GetRootWidget());
		TestTrue("the time stays in view over it", Root->GetChildIndex(Hud->TimerPanel) > Root->GetChildIndex(Hud->BriefReader));

		Hud->HandleCloseBriefReader();
		TestEqual("closed", Hud->BriefReader->GetVisibility(), ESlateVisibility::Collapsed);

		Hud->HandleOpenBrief();
		Flow->Step = EStationRunStep::Finishing;
		Hud->Refresh();
		TestEqual("closed once the run ends", Hud->BriefReader->GetVisibility(), ESlateVisibility::Collapsed);
	});

	It("keeps a simulated exam's brief on its own screen", [this]()
	{
		UStationRunFlow* Flow = MakeFlow(EStationTrainingMode::Voice);
		Flow->SessionMode = EStationSessionMode::SimulatedExam;
		UStationHudWidget* Hud = MakeHud(Flow);
		Hud->HandleOpenBrief();
		TestEqual("not the training's reader", Hud->BriefReader->GetVisibility(), ESlateVisibility::Collapsed);
	});

	It("keeps the typed turn and the typed exam request in a training", [this]()
	{
		UStationHudWidget* Hud = MakeHud(MakeFlow(EStationTrainingMode::Text));
		TestEqual(TEXT("the typed turn"), Hud->TurnRow->GetVisibility(), ESlateVisibility::Visible);
		TestTrue(TEXT("its send button"), Hud->SendButton->GetIsEnabled());
		TestEqual(TEXT("the typed exam request"), Hud->ExamTypedRow->GetVisibility(), ESlateVisibility::Visible);
		TestTrue(TEXT("its request button"), Hud->ExamButton->GetIsEnabled());
	});
}

#endif
