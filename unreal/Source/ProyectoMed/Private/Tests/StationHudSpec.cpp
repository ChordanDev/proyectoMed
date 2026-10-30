// What the in-run HUD shows for a given run (#364): the exam panel, the
// document reader and the conversation. Needs nothing else; the look itself is
// judged on the images of StationHudSnapshotSpec.cpp.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/EditableTextBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Engine/Engine.h"
#include "Station/StationRunFlow.h"
#include "Station/StationScreens.h"
#include "Station/StationUi.h"

BEGIN_DEFINE_SPEC(FStationHudUnitSpec, "ProyectoMed.StationHud.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)

	UStationRunFlow* MakeFlow(EStationTrainingMode Mode) const;
	UStationHudWidget* MakeHud(UStationRunFlow* Flow) const;
	/** Every text under `Root`, in tree order. */
	static TArray<FString> Texts(UWidget* Root);
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

		// The top bar, the conversation and the exam drawer: the panel's colour.
		int32 Panels = 0;
		for (UBorder* Border : Borders(Hud->GetRootWidget()))
		{
			const FLinearColor Fill = Border->Background.TintColor.GetSpecifiedColor();
			if (Fill.Equals(StationUi::Panel.CopyWithNewOpacity(Fill.A)))
			{
				++Panels;
				TestTrue(TEXT("a panel is translucent"), Fill.A < 1.f);
			}
		}
		TestEqual(TEXT("the top bar, the conversation and the exam drawer"), Panels, 3);

		const TArray<UBorder*> Bubbles = Borders(Hud->TranscriptBox);
		TestEqual(TEXT("one bubble per line"), Bubbles.Num(), 2);
		for (UBorder* Bubble : Bubbles)
		{
			TestEqual(TEXT("a bubble is opaque"), Alpha(Bubble->Background), 1.f);
		}

		const TArray<UBorder*> Cards = Borders(Hud->ExamCardBox);
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
}

#endif
