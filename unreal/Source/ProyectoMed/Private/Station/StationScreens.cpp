#include "Station/StationScreens.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/EditableTextBox.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "Components/ScrollBox.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Station/StationRunFlow.h"
#include "Station/StationUi.h"
#include "StationClient.h"

#define LOCTEXT_NAMESPACE "StationScreens"

// The learner-facing copy is Brazilian Portuguese, matching the web station
// (web/src/features/station/i18n/pt-BR.json) where both say the same thing.

TSharedRef<SWidget> UStationNoticeWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UVerticalBox* Column = StationUi::MakeCenteredCard(*WidgetTree, 760.f, 900.f, false);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("NoticeTitle", "Ferramenta Educacional"), 32, true,
			StationUi::Ink, 0.f);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("NoticeBody",
			"Ferramenta educacional independente para treino de habilidades clínicas. Não insira dados de pacientes reais."), 18);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("NoticeDisclaimer",
			"Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica aprovação, reprovação, certificação ou prontidão para o exame."),
			16, false, StationUi::Muted);
		UButton* Acknowledge = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("NoticeButton", "Entendi"));
		Acknowledge->OnClicked.AddDynamic(this, &UStationNoticeWidget::HandleAcknowledge);
	}
	return Super::RebuildWidget();
}

void UStationNoticeWidget::HandleAcknowledge()
{
	OnAcknowledged.ExecuteIfBound();
}

TSharedRef<SWidget> UStationBriefWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UVerticalBox* Column = StationUi::MakeCenteredCard(*WidgetTree, 860.f, 920.f, true);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("BriefHeading", "Antes de entrar na estação"), 16, true,
			StationUi::Muted, 0.f);

		StatusText = StationUi::AddText(*WidgetTree, *Column, LOCTEXT("BriefLoading", "Carregando cenário e tarefas..."), 18);
		ErrorText = StationUi::AddText(*WidgetTree, *Column, FText::GetEmpty(), 18, false, StationUi::Caution);
		RetryButton = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("Retry", "Tentar novamente"));
		RetryButton->OnClicked.AddDynamic(this, &UStationBriefWidget::HandleRetry);

		BriefBox = WidgetTree->ConstructWidget<UVerticalBox>();
		Column->AddChild(BriefBox);
		TitleText = StationUi::AddText(*WidgetTree, *BriefBox, FText::GetEmpty(), 30, true);
		StationUi::AddText(*WidgetTree, *BriefBox, LOCTEXT("ScenarioHeading", "Cenário de atuação"), 20, true,
			StationUi::Ink, 24.f);
		ScenarioText = StationUi::AddText(*WidgetTree, *BriefBox, FText::GetEmpty(), 18);
		StationUi::AddText(*WidgetTree, *BriefBox, LOCTEXT("TasksHeading", "Tarefas"), 20, true, StationUi::Ink, 24.f);
		TaskList = WidgetTree->ConstructWidget<UVerticalBox>();
		BriefBox->AddChild(TaskList);
		StationUi::AddText(*WidgetTree, *BriefBox, LOCTEXT("FictionalNote",
			"Caso clínico fictício, criado para treino educacional. Não corresponde a um paciente real."),
			15, false, StationUi::Muted, 24.f);
		StationUi::AddText(*WidgetTree, *BriefBox, LOCTEXT("TimerNote",
			"O tempo da estação começa a contar quando você entrar."), 15, false, StationUi::Muted);

		TextButton = StationUi::AddButton(*WidgetTree, *BriefBox, LOCTEXT("TextTraining", "Treino por texto"));
		TextButton->OnClicked.AddDynamic(this, &UStationBriefWidget::HandleTextTraining);
		VoiceButton = StationUi::AddButton(*WidgetTree, *BriefBox, LOCTEXT("VoiceTraining", "Treino por voz"), 12.f);
		VoiceButton->OnClicked.AddDynamic(this, &UStationBriefWidget::HandleVoiceTraining);
		VoiceNote = StationUi::AddText(*WidgetTree, *BriefBox, LOCTEXT("VoiceNote",
			"No treino por voz, seu áudio é transcrito e a resposta do paciente é sintetizada por serviços externos."),
			14, false, StationUi::Muted, 8.f);
	}
	return Super::RebuildWidget();
}

void UStationBriefWidget::Refresh()
{
	if (!Flow || !BriefBox)
	{
		return;
	}

	const FStationSummary* Station = Flow->GetStation();
	const bool bStarting = Flow->GetStep() == EStationRunStep::Starting;

	StationUi::SetShown(StatusText, Flow->IsStationLoading() || bStarting);
	StatusText->SetText(bStarting
		? LOCTEXT("Starting", "Iniciando a estação...")
		: LOCTEXT("BriefLoading", "Carregando cenário e tarefas..."));

	StationUi::SetShown(ErrorText, !Flow->GetErrorText().IsEmpty());
	ErrorText->SetText(Flow->GetErrorText());
	StationUi::SetShown(RetryButton, !Station && !Flow->IsStationLoading());

	StationUi::SetShown(BriefBox, Station != nullptr);
	if (!Station)
	{
		return;
	}

	TitleText->SetText(FText::FromString(Station->DisplayTitle));
	ScenarioText->SetText(FText::FromString(Station->Scenario));
	TaskList->ClearChildren();
	for (const FString& Task : Station->Tasks)
	{
		StationUi::AddText(*WidgetTree, *TaskList, FText::FromString(TEXT("•  ") + Task), 18, false, StationUi::Ink, 8.f);
	}

	TextButton->SetIsEnabled(Flow->CanEnter(EStationTrainingMode::Text));
	const bool bVoiceOffered = IsVoiceTrainingAvailable(*Station);
	StationUi::SetShown(VoiceButton, bVoiceOffered);
	StationUi::SetShown(VoiceNote, bVoiceOffered);
	VoiceButton->SetIsEnabled(Flow->CanEnter(EStationTrainingMode::Voice));
}

void UStationBriefWidget::HandleTextTraining()
{
	if (Flow)
	{
		Flow->Enter(EStationTrainingMode::Text);
	}
}

void UStationBriefWidget::HandleVoiceTraining()
{
	if (Flow)
	{
		Flow->Enter(EStationTrainingMode::Voice);
	}
}

void UStationBriefWidget::HandleRetry()
{
	if (Flow)
	{
		Flow->RetryLoadStation();
	}
}

TSharedRef<SWidget> UStationHudWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UOverlay* Root = WidgetTree->ConstructWidget<UOverlay>();
		WidgetTree->RootWidget = Root;

		UBorder* Panel = WidgetTree->ConstructWidget<UBorder>();
		Panel->SetBrushColor(FLinearColor(0.f, 0.f, 0.f, 0.55f));
		Panel->SetPadding(FMargin(24.f, 12.f));
		if (UOverlaySlot* Slot = Root->AddChildToOverlay(Panel))
		{
			Slot->SetHorizontalAlignment(HAlign_Center);
			Slot->SetVerticalAlignment(VAlign_Top);
			Slot->SetPadding(FMargin(0.f, 24.f, 0.f, 0.f));
		}

		UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>();
		Panel->SetContent(Column);
		ModeText = StationUi::AddText(*WidgetTree, *Column, FText::GetEmpty(), 14, false, StationUi::Muted, 0.f);
		TimerText = StationUi::AddText(*WidgetTree, *Column, FormatStationTimer(FTimespan::Zero()), 40, true,
			StationUi::Ink, 2.f);
		FallbackText = StationUi::AddText(*WidgetTree, *Column, LOCTEXT("VoiceFallback", "Voz indisponível — usando texto."),
			14, false, StationUi::Caution, 4.f);
		ModeText->SetJustification(ETextJustify::Center);
		TimerText->SetJustification(ETextJustify::Center);
		FallbackText->SetJustification(ETextJustify::Center);

		BuildConversation(*Root);
		BuildExams(*Root);
	}
	return Super::RebuildWidget();
}

void UStationHudWidget::BuildConversation(UOverlay& Root)
{
	// The typed Station Input: available for the whole run, in either training,
	// so the station can be completed without a microphone.
	USizeBox* Size = WidgetTree->ConstructWidget<USizeBox>();
	Size->SetWidthOverride(860.f);
	if (UOverlaySlot* Slot = Root.AddChildToOverlay(Size))
	{
		Slot->SetHorizontalAlignment(HAlign_Center);
		Slot->SetVerticalAlignment(VAlign_Bottom);
		Slot->SetPadding(FMargin(16.f, 0.f, 16.f, 24.f));
	}

	UBorder* Panel = WidgetTree->ConstructWidget<UBorder>();
	Panel->SetBrushColor(FLinearColor(0.f, 0.f, 0.f, 0.65f));
	Panel->SetPadding(FMargin(20.f, 16.f));
	Size->SetContent(Panel);

	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>();
	Panel->SetContent(Column);

	USizeBox* ScrollSize = WidgetTree->ConstructWidget<USizeBox>();
	ScrollSize->SetMaxDesiredHeight(260.f);
	Column->AddChild(ScrollSize);
	TranscriptScroll = WidgetTree->ConstructWidget<UScrollBox>();
	ScrollSize->SetContent(TranscriptScroll);
	TranscriptBox = WidgetTree->ConstructWidget<UVerticalBox>();
	TranscriptScroll->AddChild(TranscriptBox);

	TurnErrorText = StationUi::AddText(*WidgetTree, *Column, FText::GetEmpty(), 15, false, StationUi::Caution, 8.f);

	UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>();
	if (UVerticalBoxSlot* RowSlot = Column->AddChildToVerticalBox(Row))
	{
		RowSlot->SetPadding(FMargin(0.f, 12.f, 0.f, 0.f));
	}

	TurnInput = WidgetTree->ConstructWidget<UEditableTextBox>();
	TurnInput->SetHintText(LOCTEXT("TurnHint", "Digite sua mensagem ao paciente"));
	TurnInput->OnTextCommitted.AddDynamic(this, &UStationHudWidget::HandleTurnCommitted);
	if (UHorizontalBoxSlot* InputSlot = Row->AddChildToHorizontalBox(TurnInput))
	{
		InputSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		InputSlot->SetVerticalAlignment(VAlign_Center);
	}

	SendButton = StationUi::AddButton(*WidgetTree, *Row, LOCTEXT("SendTurn", "Enviar"));
	SendButton->OnClicked.AddDynamic(this, &UStationHudWidget::HandleSend);
	if (UHorizontalBoxSlot* ButtonSlot = Cast<UHorizontalBoxSlot>(SendButton->Slot))
	{
		ButtonSlot->SetPadding(FMargin(12.f, 0.f, 0.f, 0.f));
		ButtonSlot->SetVerticalAlignment(VAlign_Center);
	}
}

void UStationHudWidget::RefreshConversation()
{
	TranscriptBox->ClearChildren();
	for (const FStationMessage& Line : Flow->GetTranscript())
	{
		AddTranscriptLine(Line.Speaker == EStationSpeaker::Learner
			? FText::Format(LOCTEXT("LearnerLine", "Você: {0}"), FText::FromString(Line.Text))
			: FText::Format(LOCTEXT("PatientLine", "Paciente: {0}"), FText::FromString(Line.Text)),
			StationUi::Ink);
	}
	if (Flow->IsTurnInFlight())
	{
		AddTranscriptLine(FText::Format(LOCTEXT("PendingLine", "Você: {0} (enviando...)"),
			FText::FromString(Flow->GetPendingTurnText())), StationUi::Muted);
	}
	TranscriptScroll->ScrollToEnd();

	StationUi::SetShown(TurnErrorText, !Flow->GetErrorText().IsEmpty());
	TurnErrorText->SetText(Flow->GetErrorText());
	SendButton->SetIsEnabled(Flow->CanSendTurn());

	// A turn Phoenix did not take goes back into the box, unless the learner
	// already started typing another one.
	if (TurnInput->GetText().IsEmpty())
	{
		const FString Unsent = Flow->TakeUnsentTurn();
		if (!Unsent.IsEmpty())
		{
			TurnInput->SetText(FText::FromString(Unsent));
		}
	}
}

void UStationHudWidget::AddTranscriptLine(const FText& Text, const FLinearColor& Color)
{
	StationUi::AddText(*WidgetTree, *TranscriptBox, Text, 17, false, Color, TranscriptBox->GetChildrenCount() ? 8.f : 0.f);
}

void UStationHudWidget::SendTypedTurn()
{
	if (Flow && TurnInput && Flow->SendTypedTurn(TurnInput->GetText().ToString()))
	{
		TurnInput->SetText(FText::GetEmpty());
	}
}

void UStationHudWidget::HandleSend()
{
	SendTypedTurn();
}

void UStationHudWidget::HandleTurnCommitted(const FText& Text, ETextCommit::Type CommitMethod)
{
	if (CommitMethod == ETextCommit::OnEnter)
	{
		SendTypedTurn();
	}
}

void UStationHudWidget::BuildExams(UOverlay& Root)
{
	// Exam and impresso requests have their own control and their own Phoenix
	// route (ADR-008): what is asked here never reaches the patient.
	USizeBox* Size = WidgetTree->ConstructWidget<USizeBox>();
	Size->SetWidthOverride(420.f);
	Size->SetMaxDesiredHeight(640.f);
	if (UOverlaySlot* Slot = Root.AddChildToOverlay(Size))
	{
		Slot->SetHorizontalAlignment(HAlign_Right);
		Slot->SetVerticalAlignment(VAlign_Top);
		Slot->SetPadding(FMargin(0.f, 24.f, 24.f, 0.f));
	}

	UBorder* Panel = WidgetTree->ConstructWidget<UBorder>();
	Panel->SetBrushColor(FLinearColor(0.f, 0.f, 0.f, 0.65f));
	Panel->SetPadding(FMargin(20.f, 16.f));
	Size->SetContent(Panel);

	UScrollBox* Scroll = WidgetTree->ConstructWidget<UScrollBox>();
	Panel->SetContent(Scroll);
	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>();
	Scroll->AddChild(Column);

	UButton* Toggle = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("ExamsButton", "Exames"), 0.f);
	Toggle->OnClicked.AddDynamic(this, &UStationHudWidget::HandleToggleExams);

	ExamPanel = WidgetTree->ConstructWidget<UVerticalBox>();
	Column->AddChild(ExamPanel);
	StationUi::SetShown(ExamPanel, false);

	StationUi::AddText(*WidgetTree, *ExamPanel, LOCTEXT("ExamHeading", "Solicitar Exame Físico ou Exame Complementar"),
		18, true, StationUi::Ink, 16.f);
	ExamInput = WidgetTree->ConstructWidget<UEditableTextBox>();
	ExamInput->SetHintText(LOCTEXT("ExamHint", "Descreva a manobra de exame físico ou o exame complementar solicitado"));
	ExamInput->OnTextCommitted.AddDynamic(this, &UStationHudWidget::HandleExamCommitted);
	if (UVerticalBoxSlot* InputSlot = ExamPanel->AddChildToVerticalBox(ExamInput))
	{
		InputSlot->SetPadding(FMargin(0.f, 12.f, 0.f, 0.f));
	}
	ExamButton = StationUi::AddButton(*WidgetTree, *ExamPanel, LOCTEXT("ExamSubmit", "Solicitar"), 12.f);
	ExamButton->OnClicked.AddDynamic(this, &UStationHudWidget::HandleRequestExam);
	ExamErrorText = StationUi::AddText(*WidgetTree, *ExamPanel, FText::GetEmpty(), 15, false, StationUi::Caution, 8.f);

	ExamRequestBox = WidgetTree->ConstructWidget<UVerticalBox>();
	ExamPanel->AddChild(ExamRequestBox);

	StationUi::AddText(*WidgetTree, *ExamPanel, LOCTEXT("DocumentsHeading", "Documentos liberados"), 18, true,
		StationUi::Ink, 20.f);
	NoDocumentText = StationUi::AddText(*WidgetTree, *ExamPanel,
		LOCTEXT("NoDocuments", "Nenhum documento liberado ainda."), 15, false, StationUi::Muted, 8.f);
	DocumentBox = WidgetTree->ConstructWidget<UVerticalBox>();
	ExamPanel->AddChild(DocumentBox);
}

void UStationHudWidget::RefreshExams()
{
	ExamRequestBox->ClearChildren();
	for (const FStationExamRequest& Request : Flow->GetExamRequests())
	{
		// Phoenix's feedback is the whole answer: a declined request shows that
		// it was declined and nothing else.
		const FStationImpressoReply& Reply = Request.Reply;
		FText Decision;
		FLinearColor Color = StationUi::Ink;
		switch (Reply.Decision)
		{
		case EStationImpressoDecision::Released:
			Decision = LOCTEXT("ExamReleased", "Liberado");
			break;
		case EStationImpressoDecision::AlreadyReleased:
			Decision = LOCTEXT("ExamAlreadyReleased", "Já liberado");
			Color = StationUi::Muted;
			break;
		case EStationImpressoDecision::Unavailable:
			Decision = LOCTEXT("ExamUnavailable", "Não disponível");
			Color = StationUi::Caution;
			break;
		}
		StationUi::AddText(*WidgetTree, *ExamRequestBox,
			FText::Format(LOCTEXT("ExamRequestLine", "Você solicitou: {0}"), FText::FromString(Request.Text)),
			15, false, StationUi::Muted, 12.f);
		StationUi::AddText(*WidgetTree, *ExamRequestBox,
			Reply.FeedbackMessage.IsEmpty() ? Decision : FText::FromString(Reply.FeedbackMessage), 15, true, Color, 2.f);
	}
	if (Flow->IsExamRequestInFlight())
	{
		StationUi::AddText(*WidgetTree, *ExamRequestBox,
			FText::Format(LOCTEXT("ExamPendingLine", "Você solicitou: {0} (solicitando...)"),
				FText::FromString(Flow->GetPendingExamRequestText())), 15, false, StationUi::Muted, 12.f);
	}

	DocumentBox->ClearChildren();
	const TArray<FStationImpresso>& Released = Flow->GetReleasedImpressos();
	StationUi::SetShown(NoDocumentText, Released.Num() == 0);
	for (const FStationImpresso& Impresso : Released)
	{
		StationUi::AddText(*WidgetTree, *DocumentBox, FText::FromString(Impresso.Title), 16, true, StationUi::Ink, 12.f);
		StationUi::AddText(*WidgetTree, *DocumentBox, FText::FromString(Impresso.Content), 15, false, StationUi::Ink, 4.f);
	}

	StationUi::SetShown(ExamErrorText, !Flow->GetExamErrorText().IsEmpty());
	ExamErrorText->SetText(Flow->GetExamErrorText());
	ExamButton->SetIsEnabled(Flow->CanRequestExam());

	if (ExamInput->GetText().IsEmpty())
	{
		const FString Unsent = Flow->TakeUnsentExamRequest();
		if (!Unsent.IsEmpty())
		{
			ExamInput->SetText(FText::FromString(Unsent));
		}
	}
}

void UStationHudWidget::RequestExam()
{
	if (Flow && ExamInput && Flow->RequestExam(ExamInput->GetText().ToString()))
	{
		ExamInput->SetText(FText::GetEmpty());
	}
}

void UStationHudWidget::HandleToggleExams()
{
	StationUi::SetShown(ExamPanel, !ExamPanel->IsVisible());
}

void UStationHudWidget::HandleRequestExam()
{
	RequestExam();
}

void UStationHudWidget::HandleExamCommitted(const FText& Text, ETextCommit::Type CommitMethod)
{
	if (CommitMethod == ETextCommit::OnEnter)
	{
		RequestExam();
	}
}

void UStationHudWidget::Refresh()
{
	if (!Flow || !ModeText)
	{
		return;
	}
	ModeText->SetText(Flow->GetMode() == EStationTrainingMode::Voice
		? LOCTEXT("VoiceTrainingLabel", "Treino por voz · Tempo restante")
		: LOCTEXT("TextTrainingLabel", "Treino por texto · Tempo restante"));
	StationUi::SetShown(FallbackText, Flow->IsVoiceFallback());
	RefreshConversation();
	RefreshExams();
}

void UStationHudWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);
	if (Flow && Flow->GetClient() && TimerText)
	{
		TimerText->SetText(FormatStationTimer(Flow->GetClient()->GetRemainingTime()));
	}
}

#undef LOCTEXT_NAMESPACE
