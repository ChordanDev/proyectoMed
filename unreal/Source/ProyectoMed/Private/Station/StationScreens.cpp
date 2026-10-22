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

namespace
{
	/**
	 * Gives what Phoenix did not take back to its box, unless the learner
	 * already started typing something else. `Take` is called only then.
	 */
	void RestoreUnsent(UEditableTextBox& Input, TFunctionRef<FString()> Take)
	{
		if (Input.GetText().IsEmpty())
		{
			const FString Unsent = Take();
			if (!Unsent.IsEmpty())
			{
				Input.SetText(FText::FromString(Unsent));
			}
		}
	}

	/** Phoenix's exact points with a decimal comma; never parsed, rounded or rescaled. */
	FText DisplayPoints(const FString& Points)
	{
		return FText::FromString(Points.Replace(TEXT("."), TEXT(",")));
	}
}

// The learner-facing copy is Brazilian Portuguese, matching the web station
// (web/src/features/station/i18n/pt-BR.json) where both say the same thing.

TSharedRef<SWidget> UStationMicrophoneWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UVerticalBox* Column = StationUi::MakeCenteredCard(*WidgetTree, 760.f, 900.f, false);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("MicrophoneTitle", "Microfone"), 32, true, StationUi::Ink, 0.f);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("MicrophoneBody",
			"No treino por voz você conversa com o paciente pelo microfone. Durante a estação, o seu áudio é enviado à Deepgram, que o transcreve, e a resposta do paciente é gerada em voz pela Cartesia."),
			18);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("MicrophoneRetention",
			"O microfone só fica ligado durante uma estação por voz. O ProyectoMed não guarda o seu áudio nem a transcrição depois da estação."),
			16, false, StationUi::Muted);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("MicrophoneTextOption",
			"Você também pode treinar por texto, sem microfone."), 16, false, StationUi::Muted);
		UButton* Allow = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("MicrophoneAllow", "Permitir microfone"));
		Allow->OnClicked.AddDynamic(this, &UStationMicrophoneWidget::HandleAllow);
		UButton* NotNow = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("MicrophoneNotNow", "Agora não"), 12.f);
		NotNow->OnClicked.AddDynamic(this, &UStationMicrophoneWidget::HandleNotNow);
	}
	return Super::RebuildWidget();
}

void UStationMicrophoneWidget::HandleAllow()
{
	OnAnswered.ExecuteIfBound(true);
}

void UStationMicrophoneWidget::HandleNotNow()
{
	OnAnswered.ExecuteIfBound(false);
}

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
			"No treino por voz, a Deepgram transcreve o seu áudio e a Cartesia gera a voz do paciente."),
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
	VoiceNote->SetText(Flow->GetMicrophonePermission() == EStationMicPermission::Denied
		? LOCTEXT("VoiceBlocked", "O microfone está bloqueado. Para treinar por voz, libere o acesso nos ajustes de privacidade do sistema e abra o app de novo.")
		: LOCTEXT("VoiceNote", "No treino por voz, a Deepgram transcreve o seu áudio e a Cartesia gera a voz do paciente."));
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
		VoiceStatusText = StationUi::AddText(*WidgetTree, *Column, FText::GetEmpty(), 14, false, StationUi::Muted, 4.f);
		ModeText->SetJustification(ETextJustify::Center);
		TimerText->SetJustification(ETextJustify::Center);
		FallbackText->SetJustification(ETextJustify::Center);
		VoiceStatusText->SetJustification(ETextJustify::Center);

		FinishButton = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("FinishStation", "Finalizar estação"), 8.f);
		FinishButton->OnClicked.AddDynamic(this, &UStationHudWidget::HandleFinish);

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
	// The spoken turn in progress: the learner's live caption, the examiner's note
	// and the patient's reply while it is spoken.
	const FStationVoiceView& Voice = Flow->GetVoice();
	if (!Voice.LearnerText.IsEmpty())
	{
		AddTranscriptLine(FText::Format(LOCTEXT("LearnerLine", "Você: {0}"), FText::FromString(Voice.LearnerText)),
			StationUi::Muted);
	}
	if (Voice.bExaminerNoted)
	{
		AddTranscriptLine(LOCTEXT("ExaminerNoted", "Examinador: Anotado."), StationUi::Muted);
	}
	if (!Voice.PatientText.IsEmpty())
	{
		AddTranscriptLine(FText::Format(LOCTEXT("PatientLine", "Paciente: {0}"), FText::FromString(Voice.PatientText)),
			StationUi::Ink);
	}
	TranscriptScroll->ScrollToEnd();

	StationUi::SetShown(TurnErrorText, !Flow->GetErrorText().IsEmpty());
	TurnErrorText->SetText(Flow->GetErrorText());
	SendButton->SetIsEnabled(Flow->CanSendTurn());

	RestoreUnsent(*TurnInput, [this]() { return Flow->TakeUnsentTurn(); });
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
		const FLinearColor Color = Reply.Decision == EStationImpressoDecision::Unavailable ? StationUi::Caution
			: Reply.Decision == EStationImpressoDecision::AlreadyReleased ? StationUi::Muted
			: StationUi::Ink;
		StationUi::AddText(*WidgetTree, *ExamRequestBox,
			FText::Format(LOCTEXT("ExamRequestLine", "Você solicitou: {0}"), FText::FromString(Request.Text)),
			15, false, StationUi::Muted, 12.f);
		StationUi::AddText(*WidgetTree, *ExamRequestBox,
			FText::FromString(Reply.FeedbackMessage), 15, true, Color, 2.f);
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
	RestoreUnsent(*ExamInput, [this]() { return Flow->TakeUnsentExamRequest(); });
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
	StationUi::SetShown(ExamPanel, ExamPanel->GetVisibility() == ESlateVisibility::Collapsed);
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

void UStationHudWidget::HandleFinish()
{
	if (Flow)
	{
		Flow->Finish();
	}
}

void UStationHudWidget::Refresh()
{
	if (!Flow || !ModeText)
	{
		return;
	}
	FinishButton->SetIsEnabled(Flow->CanFinish());
	ModeText->SetText(Flow->GetMode() == EStationTrainingMode::Voice
		? LOCTEXT("VoiceTrainingLabel", "Treino por voz · Tempo restante")
		: LOCTEXT("TextTrainingLabel", "Treino por texto · Tempo restante"));
	StationUi::SetShown(FallbackText, Flow->IsVoiceFallback());

	const FStationVoiceView& Voice = Flow->GetVoice();
	const bool bVoiceRun = Flow->GetMode() == EStationTrainingMode::Voice && !Flow->IsVoiceFallback();
	FText Status;
	if (Voice.bLost)
	{
		Status = LOCTEXT("VoiceLost", "A voz caiu. O tempo da estação continua.");
	}
	else if (Voice.State == EStationVoiceState::Ready)
	{
		Status = LOCTEXT("MicrophoneOn", "Microfone ativo");
	}
	else if (Voice.State == EStationVoiceState::Reconnecting)
	{
		Status = LOCTEXT("VoiceReconnecting", "Reconectando a voz...");
	}
	else if (Voice.State != EStationVoiceState::Disconnected)
	{
		Status = LOCTEXT("VoiceConnecting", "Conectando a voz...");
	}
	StationUi::SetShown(VoiceStatusText, bVoiceRun && !Status.IsEmpty());
	VoiceStatusText->SetText(Status);
	VoiceStatusText->SetColorAndOpacity(Voice.bLost ? StationUi::Caution : StationUi::Muted);

	RefreshConversation();
	RefreshExams();
}

void UStationHudWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);
	if (Flow && Flow->GetClient() && TimerText)
	{
		TimerText->SetText(FormatStationTimer(Flow->GetClient()->GetRemainingTime()));
		Flow->CheckStationTimer();
	}
}

TSharedRef<SWidget> UStationFeedbackWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UVerticalBox* Column = StationUi::MakeCenteredCard(*WidgetTree, 920.f, 960.f, true);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("ResultTitle", "Resultado educacional da estação"), 30, true,
			StationUi::Ink, 0.f);
		// Every state of this screen says what the result is not.
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("ResultDisclaimer",
			"Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica aprovação, reprovação, certificação ou prontidão para o exame."),
			16, false, StationUi::Muted);

		LoadingBox = WidgetTree->ConstructWidget<UVerticalBox>();
		Column->AddChild(LoadingBox);
		StationUi::AddText(*WidgetTree, *LoadingBox, LOCTEXT("LoadingResult", "Gerando o resultado da estação..."), 18);
		StationUi::AddText(*WidgetTree, *LoadingBox, LOCTEXT("LoadingResultWait",
			"Gerando feedback da estação… isso pode levar até um minuto."), 15, false, StationUi::Muted, 4.f);

		ErrorText = StationUi::AddText(*WidgetTree, *Column, FText::GetEmpty(), 18, false, StationUi::Caution);
		RestartNote = StationUi::AddText(*WidgetTree, *Column, LOCTEXT("RestartDiscards",
			"Ao reiniciar, esta tentativa é descartada e não poderá ser recuperada."), 15, false, StationUi::Muted, 4.f);

		ResultBox = WidgetTree->ConstructWidget<UVerticalBox>();
		Column->AddChild(ResultBox);

		SessionNote = StationUi::AddText(*WidgetTree, *Column, LOCTEXT("SessionOnly",
			"Evidências apenas desta sessão. Ao reiniciar, os dados são descartados; não há histórico pessoal."),
			15, false, StationUi::Muted, 24.f);
		RestartButton = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("RestartStation", "Reiniciar estação"));
		RestartButton->OnClicked.AddDynamic(this, &UStationFeedbackWidget::HandleRestart);
	}
	return Super::RebuildWidget();
}

void UStationFeedbackWidget::Refresh()
{
	if (!Flow || !ResultBox)
	{
		return;
	}

	const bool bFeedback = Flow->GetStep() == EStationRunStep::Feedback;
	const FStationResult* Result = Flow->GetResult();

	StationUi::SetShown(LoadingBox, Flow->GetStep() == EStationRunStep::Finishing);
	StationUi::SetShown(ErrorText, !Flow->GetErrorText().IsEmpty());
	ErrorText->SetText(Flow->GetErrorText());
	StationUi::SetShown(RestartNote, bFeedback && !Result);
	StationUi::SetShown(SessionNote, Result != nullptr);
	StationUi::SetShown(RestartButton, bFeedback);
	RestartButton->SetIsEnabled(Flow->CanDiscard());

	ResultBox->ClearChildren();
	StationUi::SetShown(ResultBox, Result != nullptr);
	if (!Result)
	{
		return;
	}

	if (Result->bPlaceholder)
	{
		StationUi::AddText(*WidgetTree, *ResultBox, LOCTEXT("FictionalResult", "Exemplo — dados fictícios"), 15, true,
			StationUi::Caution);
	}

	auto Count = [Result](EStationCriterionStatus Status)
	{
		return Result->Criteria.FilterByPredicate(
			[Status](const FStationCriterionResult& Criterion) { return Criterion.Status == Status; }).Num();
	};
	StationUi::AddText(*WidgetTree, *ResultBox, LOCTEXT("Coverage", "Cobertura dos critérios"), 20, true, StationUi::Ink, 24.f);
	StationUi::AddText(*WidgetTree, *ResultBox, FText::Format(LOCTEXT("CoverageCounts",
		"Avaliados: {0} · Incertos: {1} · Não observáveis: {2} · Excluídos: {3}"),
		Count(EStationCriterionStatus::Assessed), Count(EStationCriterionStatus::Uncertain),
		Count(EStationCriterionStatus::NotObservable), Count(EStationCriterionStatus::NotApplicable)),
		16, false, StationUi::Ink, 8.f);
	StationUi::AddText(*WidgetTree, *ResultBox, FText::Format(LOCTEXT("ScoredPoints",
		"Pontos obtidos nos critérios avaliados: {0} de {1}"),
		DisplayPoints(Result->ScoredSubtotal), DisplayPoints(Result->ScoredMax)), 16, false, StationUi::Ink, 8.f);
	StationUi::AddText(*WidgetTree, *ResultBox, FText::Format(LOCTEXT("EligibleMax",
		"Máximo da estação (todos os critérios elegíveis): {0}"), DisplayPoints(Result->EligibleMax)), 16, false,
		StationUi::Ink, 4.f);
	const bool bNoneEligible = Result->Criteria.Num() == Count(EStationCriterionStatus::NotApplicable);
	StationUi::AddText(*WidgetTree, *ResultBox, !Result->EstimatedTotal.IsEmpty()
		? FText::Format(LOCTEXT("Total", "Total educacional: {0}"), DisplayPoints(Result->EstimatedTotal))
		: bNoneEligible
		? LOCTEXT("NoEligible", "Nenhum critério elegível — não há estimativa total.")
		: LOCTEXT("OpenTotal",
			"Total indisponível — há critérios não resolvidos. Os pontos acima contam apenas os critérios avaliados e não representam a estação inteira."),
		16, true, StationUi::Ink, 4.f);

	for (int32 Index = 0; Index < Result->Criteria.Num(); ++Index)
	{
		AddCriterion(Index + 1, Result->Criteria[Index]);
	}
}

void UStationFeedbackWidget::AddCriterion(int32 Ordinal, const FStationCriterionResult& Criterion)
{
	FText Status;
	switch (Criterion.Status)
	{
	case EStationCriterionStatus::Assessed:
		Status = LOCTEXT("CriterionAssessed", "Avaliado");
		break;
	case EStationCriterionStatus::Uncertain:
		Status = LOCTEXT("CriterionUncertain", "Incerto — sem pontos atribuídos");
		break;
	case EStationCriterionStatus::NotObservable:
		Status = LOCTEXT("CriterionNotObservable", "Não observável — modalidade indisponível; sem pontos atribuídos");
		break;
	case EStationCriterionStatus::NotApplicable:
		Status = LOCTEXT("CriterionExcluded", "Excluído pelo autor — fora dos máximos; sem pontos atribuídos");
		break;
	}

	StationUi::AddText(*WidgetTree, *ResultBox,
		FText::Format(LOCTEXT("CriterionHeading", "Critério {0} · {1}"), Ordinal, Status), 18, true, StationUi::Ink, 28.f);
	StationUi::AddText(*WidgetTree, *ResultBox, FText::FromString(Criterion.Description), 16, false, StationUi::Ink, 6.f);
	if (Criterion.Status == EStationCriterionStatus::Assessed)
	{
		if (!Criterion.LevelDescription.TrimStartAndEnd().IsEmpty())
		{
			StationUi::AddText(*WidgetTree, *ResultBox, FText::Format(LOCTEXT("CriterionLevel", "Nível autoral: {0}"),
				FText::FromString(Criterion.LevelDescription)), 15, false, StationUi::Muted, 4.f);
		}
		StationUi::AddText(*WidgetTree, *ResultBox, FText::Format(LOCTEXT("CriterionPoints", "Pontos: {0} de {1}"),
			DisplayPoints(Criterion.Points), DisplayPoints(Criterion.MaxPoints)), 15, false, StationUi::Muted, 4.f);
	}

	if (Criterion.Evidence.Num() > 0)
	{
		StationUi::AddText(*WidgetTree, *ResultBox, LOCTEXT("EvidenceHeading", "Evidências"), 16, true, StationUi::Ink, 12.f);
		for (const FStationEvidence& Excerpt : Criterion.Evidence)
		{
			StationUi::AddText(*WidgetTree, *ResultBox, FText::Format(Excerpt.Speaker == EStationSpeaker::Learner
				? LOCTEXT("EvidenceLearner", "Você: “{0}”")
				: LOCTEXT("EvidencePatient", "Paciente: “{0}”"), FText::FromString(Excerpt.Text)),
				15, false, StationUi::Ink, 4.f);
		}
	}

	StationUi::AddText(*WidgetTree, *ResultBox, LOCTEXT("RecommendationHeading", "Recomendação"), 16, true, StationUi::Ink, 12.f);
	StationUi::AddText(*WidgetTree, *ResultBox, FText::FromString(Criterion.Recommendation), 15, false, StationUi::Ink, 4.f);
}

void UStationFeedbackWidget::HandleRestart()
{
	if (Flow)
	{
		Flow->Discard();
	}
}

#undef LOCTEXT_NAMESPACE
