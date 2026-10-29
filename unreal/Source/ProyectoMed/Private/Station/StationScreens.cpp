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
#include "Components/ScrollBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Station/StationRunFlow.h"
#include "Station/StationUi.h"
#include "StationClient.h"
#include "Styling/CoreStyle.h"

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

	// The side panels' layout, shared by the conversation and the exam requests.
	constexpr float SidePanelWidth = 440.f;
	constexpr float SidePanelPadding = 20.f;
	/** How far a bubble stays from the other side, so the two speakers read apart. */
	constexpr float BubbleIndent = 48.f;
	constexpr float BubblePadding = 12.f;
	/** Room the conversation's scroll bar takes once it shows. */
	constexpr float ScrollBarAllowance = 12.f;
	/** The widest a chat bubble's text runs, so it wraps inside the panel. */
	constexpr float BubbleWrapWidth =
		SidePanelWidth - 2.f * SidePanelPadding - BubbleIndent - 2.f * BubblePadding - ScrollBarAllowance;

	/** Phoenix's category of a released document, as the learner reads it. */
	FText DocumentCategoryName(const FString& Category)
	{
		if (Category == TEXT("exame-fisico"))
		{
			return LOCTEXT("CategoryPhysical", "Exame físico");
		}
		if (Category == TEXT("laboratorio"))
		{
			return LOCTEXT("CategoryLab", "Exames laboratoriais");
		}
		if (Category == TEXT("imagem"))
		{
			return LOCTEXT("CategoryImaging", "Exame de imagem");
		}
		return FText::FromString(Category);
	}

	/**
	 * A released document's Markdown as the learner reads it: a `- **Label:** text`
	 * item shows its label over its text, a `**Heading:**` line as a heading, and a
	 * plain item with a bullet. Nothing is reworded or reordered.
	 */
	void AddDocumentLines(UWidgetTree& Tree, UVerticalBox& Body, const FString& Markdown)
	{
		TArray<FString> Lines;
		Markdown.ParseIntoArrayLines(Lines, true);
		for (FString Line : Lines)
		{
			Line.TrimStartAndEndInline();
			if (Line.IsEmpty())
			{
				continue;
			}
			const float Space = Body.GetChildrenCount() > 0 ? 12.f : 0.f;
			const bool bItem = Line.StartsWith(TEXT("- ")) || Line.StartsWith(TEXT("* "));
			if (bItem)
			{
				Line.RightChopInline(2);
				Line.TrimStartInline();
			}
			if (Line.StartsWith(TEXT("**")))
			{
				const int32 Close = Line.Find(TEXT("**"), ESearchCase::CaseSensitive, ESearchDir::FromStart, 2);
				if (Close != INDEX_NONE)
				{
					const FString Label = Line.Mid(2, Close - 2).TrimStartAndEnd();
					const FString Rest = Line.Mid(Close + 2).TrimStartAndEnd().Replace(TEXT("**"), TEXT(""));
					StationUi::AddText(Tree, Body, FText::FromString(Label), bItem ? 15 : 17, true,
						bItem ? StationUi::PaperMuted : StationUi::PaperInk, Space);
					if (!Rest.IsEmpty())
					{
						StationUi::AddText(Tree, Body, FText::FromString(Rest), 17, false, StationUi::PaperInk, 2.f);
					}
					continue;
				}
			}
			const FString Text = Line.Replace(TEXT("**"), TEXT(""));
			StationUi::AddText(Tree, Body, FText::FromString(bItem ? TEXT("•  ") + Text : Text), 17, false,
				StationUi::PaperInk, Space);
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

		UBorder* Panel = StationUi::MakeRounded(*WidgetTree, StationUi::Panel, 12.f, FMargin(28.f, 14.f, 28.f, 18.f),
			StationUi::PanelEdge, 1.f);
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

		FinishButton = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("FinishStation", "Finalizar estação"), 12.f);
		FinishButton->OnClicked.AddDynamic(this, &UStationHudWidget::HandleFinish);
		StationUi::MakeDanger(*FinishButton);
		if (UVerticalBoxSlot* FinishSlot = Cast<UVerticalBoxSlot>(FinishButton->Slot))
		{
			FinishSlot->SetHorizontalAlignment(HAlign_Center);
		}

		BuildConversation(*Root);
		BuildExamTab(*Root);
		BuildExamDrawer(*Root);
		BuildDocumentViewer(*Root);
	}
	return Super::RebuildWidget();
}

void UStationHudWidget::BuildConversation(UOverlay& Root)
{
	// The conversation runs down the left edge, as the exam panel does on the
	// right. The typed Station Input stays available for the whole run, in either
	// training, so the station can be completed without a microphone.
	USizeBox* Size = WidgetTree->ConstructWidget<USizeBox>();
	Size->SetWidthOverride(SidePanelWidth);
	if (UOverlaySlot* Slot = Root.AddChildToOverlay(Size))
	{
		Slot->SetHorizontalAlignment(HAlign_Left);
		Slot->SetVerticalAlignment(VAlign_Fill);
		Slot->SetPadding(FMargin(24.f, 24.f, 0.f, 24.f));
	}

	UBorder* Panel = StationUi::MakeRounded(*WidgetTree, StationUi::Panel, 12.f, FMargin(SidePanelPadding, 18.f),
		StationUi::PanelEdge, 1.f);
	Size->SetContent(Panel);
	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>();
	Panel->SetContent(Column);
	StationUi::AddText(*WidgetTree, *Column, LOCTEXT("ConversationTitle", "Conversa"), 20, true, StationUi::Ink, 0.f);

	TranscriptScroll = WidgetTree->ConstructWidget<UScrollBox>();
	if (UVerticalBoxSlot* ScrollSlot = Column->AddChildToVerticalBox(TranscriptScroll))
	{
		ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		ScrollSlot->SetPadding(FMargin(0.f, 14.f, 0.f, 0.f));
	}
	TranscriptBox = WidgetTree->ConstructWidget<UVerticalBox>();
	TranscriptScroll->AddChild(TranscriptBox);

	TurnErrorText = StationUi::AddText(*WidgetTree, *Column, FText::GetEmpty(), 15, false, StationUi::Caution, 8.f);

	UBorder* Rule = WidgetTree->ConstructWidget<UBorder>();
	Rule->SetBrushColor(StationUi::PanelEdge);
	Rule->SetPadding(FMargin(0.f, 0.5f));
	if (UVerticalBoxSlot* RuleSlot = Column->AddChildToVerticalBox(Rule))
	{
		RuleSlot->SetPadding(FMargin(0.f, 12.f, 0.f, 0.f));
	}

	UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>();
	if (UVerticalBoxSlot* RowSlot = Column->AddChildToVerticalBox(Row))
	{
		RowSlot->SetPadding(FMargin(0.f, 14.f, 0.f, 0.f));
	}

	TurnInput = WidgetTree->ConstructWidget<UEditableTextBox>();
	TurnInput->SetHintText(LOCTEXT("TurnHint", "Mensagem ao paciente"));
	TurnInput->OnTextCommitted.AddDynamic(this, &UStationHudWidget::HandleTurnCommitted);
	if (UHorizontalBoxSlot* InputSlot = Row->AddChildToHorizontalBox(TurnInput))
	{
		InputSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		InputSlot->SetVerticalAlignment(VAlign_Center);
	}

	SendButton = StationUi::AddButton(*WidgetTree, *Row, LOCTEXT("SendTurn", "Enviar"));
	SendButton->OnClicked.AddDynamic(this, &UStationHudWidget::HandleSend);
	StationUi::MakePrimary(*SendButton);
	StationUi::StyleInput(*TurnInput);
	if (UHorizontalBoxSlot* ButtonSlot = Cast<UHorizontalBoxSlot>(SendButton->Slot))
	{
		ButtonSlot->SetPadding(FMargin(10.f, 0.f, 0.f, 0.f));
		ButtonSlot->SetVerticalAlignment(VAlign_Center);
	}
}

void UStationHudWidget::RefreshConversation()
{
	StationUi::SetShown(TurnErrorText, !Flow->GetErrorText().IsEmpty());
	TurnErrorText->SetText(Flow->GetErrorText());
	SendButton->SetIsEnabled(Flow->CanSendTurn());
	RestoreUnsent(*TurnInput, [this]() { return Flow->TakeUnsentTurn(); });

	// Rebuilt only when what it shows changed: a rebuild on every voice event
	// would move the scroll and lay every bubble out again while the learner reads.
	const FStationVoiceView& Voice = Flow->GetVoice();
	FString Key;
	for (const FStationMessage& Line : Flow->GetTranscript())
	{
		Key += FString::Printf(TEXT("%d:%s\n"), static_cast<int32>(Line.Speaker), *Line.Text);
	}
	Key += FString::Printf(TEXT("|%s|%s|%d|%s"), Flow->IsTurnInFlight() ? *Flow->GetPendingTurnText() : TEXT(""),
		*Voice.LearnerText, Voice.bExaminerNoted ? 1 : 0, *Voice.PatientText);
	if (Key == ConversationKey)
	{
		return;
	}
	ConversationKey = Key;

	TranscriptBox->ClearChildren();
	for (const FStationMessage& Line : Flow->GetTranscript())
	{
		AddMessage(Line.Speaker, Line.Text, false);
	}
	if (Flow->IsTurnInFlight())
	{
		AddMessage(EStationSpeaker::Learner, FText::Format(LOCTEXT("PendingTurn", "{0} (enviando...)"),
			FText::FromString(Flow->GetPendingTurnText())).ToString(), true);
	}
	// The spoken turn in progress: the learner's live caption, the examiner's note
	// and the patient's reply while it is spoken.
	if (!Voice.LearnerText.IsEmpty())
	{
		AddMessage(EStationSpeaker::Learner, Voice.LearnerText, true);
	}
	if (Voice.bExaminerNoted)
	{
		UTextBlock* Noted = StationUi::AddText(*WidgetTree, *TranscriptBox, LOCTEXT("ExaminerNoted", "Examinador: Anotado."),
			14, false, StationUi::Muted, 10.f);
		Noted->SetJustification(ETextJustify::Center);
	}
	if (!Voice.PatientText.IsEmpty())
	{
		AddMessage(EStationSpeaker::Patient, Voice.PatientText, false);
	}
	TranscriptScroll->ScrollToEnd();
}

void UStationHudWidget::AddMessage(EStationSpeaker Speaker, const FString& Text, bool bInProgress)
{
	// A chat bubble: the learner's on the right, the patient's on the left.
	const bool bLearner = Speaker == EStationSpeaker::Learner;
	UVerticalBox* Message = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UVerticalBoxSlot* MessageSlot = TranscriptBox->AddChildToVerticalBox(Message))
	{
		MessageSlot->SetPadding(FMargin(bLearner ? BubbleIndent : 0.f, TranscriptBox->GetChildrenCount() > 1 ? 12.f : 0.f,
			bLearner ? 0.f : BubbleIndent, 0.f));
		MessageSlot->SetHorizontalAlignment(bLearner ? HAlign_Right : HAlign_Left);
	}
	UTextBlock* Who = StationUi::AddText(*WidgetTree, *Message,
		bLearner ? LOCTEXT("LearnerSpeaker", "Você") : LOCTEXT("PatientSpeaker", "Paciente"), 13, true, StationUi::Muted, 0.f);
	if (UVerticalBoxSlot* WhoSlot = Cast<UVerticalBoxSlot>(Who->Slot))
	{
		WhoSlot->SetHorizontalAlignment(bLearner ? HAlign_Right : HAlign_Left);
	}
	UBorder* Bubble = StationUi::MakeRounded(*WidgetTree, bLearner ? StationUi::LearnerBubble : StationUi::Raised, 10.f,
		FMargin(BubblePadding, 8.f));
	if (UVerticalBoxSlot* BubbleSlot = Message->AddChildToVerticalBox(Bubble))
	{
		BubbleSlot->SetPadding(FMargin(0.f, 4.f, 0.f, 0.f));
		BubbleSlot->SetHorizontalAlignment(bLearner ? HAlign_Right : HAlign_Left);
	}
	UTextBlock* Body = WidgetTree->ConstructWidget<UTextBlock>();
	Body->SetText(FText::FromString(Text));
	Body->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 16));
	Body->SetColorAndOpacity(FSlateColor(bInProgress ? StationUi::Muted : StationUi::Ink));
	// A fixed wrap width: auto wrap lays a new block out unwrapped for one frame,
	// wider than the panel, before it wraps.
	Body->SetWrapTextAt(BubbleWrapWidth);
	Bubble->SetContent(Body);
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

void UStationDocumentLink::HandleClicked()
{
	if (UStationHudWidget* Owner = Hud.Get())
	{
		Owner->OpenDocument(ImpressoId);
	}
}

void UStationHudWidget::BuildExamTab(UOverlay& Root)
{
	ExamTab = WidgetTree->ConstructWidget<UButton>();
	FButtonStyle Style;
	Style.SetNormal(StationUi::RoundedBrush(StationUi::Panel, 10.f, StationUi::PanelEdge, 1.f));
	Style.SetHovered(StationUi::RoundedBrush(StationUi::Raised, 10.f, StationUi::PanelEdge, 1.f));
	Style.SetPressed(StationUi::RoundedBrush(StationUi::Raised, 10.f, StationUi::PanelEdge, 1.f));
	ExamTab->SetStyle(Style);
	ExamTab->OnClicked.AddDynamic(this, &UStationHudWidget::HandleOpenExams);
	ExamTabText = WidgetTree->ConstructWidget<UTextBlock>();
	ExamTabText->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 17));
	ExamTabText->SetColorAndOpacity(FSlateColor(StationUi::Ink));
	ExamTabText->SetMargin(FMargin(18.f, 12.f));
	ExamTab->AddChild(ExamTabText);
	if (UOverlaySlot* Slot = Root.AddChildToOverlay(ExamTab))
	{
		Slot->SetHorizontalAlignment(HAlign_Right);
		Slot->SetVerticalAlignment(VAlign_Top);
		Slot->SetPadding(FMargin(0.f, 24.f, 24.f, 0.f));
	}
}

void UStationHudWidget::BuildExamDrawer(UOverlay& Root)
{
	// Exam and impresso requests have their own control and their own Phoenix
	// route (ADR-008): what is asked here never reaches the patient.
	USizeBox* Size = WidgetTree->ConstructWidget<USizeBox>();
	Size->SetWidthOverride(SidePanelWidth);
	ExamDrawer = Size;
	StationUi::SetShown(ExamDrawer, false);
	if (UOverlaySlot* Slot = Root.AddChildToOverlay(Size))
	{
		Slot->SetHorizontalAlignment(HAlign_Right);
		Slot->SetVerticalAlignment(VAlign_Fill);
		Slot->SetPadding(FMargin(0.f, 24.f, 24.f, 24.f));
	}

	UBorder* Panel = StationUi::MakeRounded(*WidgetTree, StationUi::Panel, 12.f, FMargin(SidePanelPadding, 18.f),
		StationUi::PanelEdge, 1.f);
	Size->SetContent(Panel);
	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>();
	Panel->SetContent(Column);

	UHorizontalBox* Header = WidgetTree->ConstructWidget<UHorizontalBox>();
	Column->AddChild(Header);
	UTextBlock* Title = WidgetTree->ConstructWidget<UTextBlock>();
	Title->SetText(LOCTEXT("ExamsTitle", "Exames solicitados"));
	Title->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 20));
	Title->SetColorAndOpacity(FSlateColor(StationUi::Ink));
	if (UHorizontalBoxSlot* TitleSlot = Header->AddChildToHorizontalBox(Title))
	{
		TitleSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		TitleSlot->SetVerticalAlignment(VAlign_Center);
	}
	UButton* Close = StationUi::MakeFlatButton(*WidgetTree, FText::FromString(TEXT("×")), 26, StationUi::Ink);
	Close->SetToolTipText(LOCTEXT("CloseExams", "Fechar"));
	Close->OnClicked.AddDynamic(this, &UStationHudWidget::HandleCloseExams);
	if (UHorizontalBoxSlot* CloseSlot = Header->AddChildToHorizontalBox(Close))
	{
		CloseSlot->SetVerticalAlignment(VAlign_Center);
	}

	UScrollBox* Scroll = WidgetTree->ConstructWidget<UScrollBox>();
	if (UVerticalBoxSlot* ScrollSlot = Column->AddChildToVerticalBox(Scroll))
	{
		ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		ScrollSlot->SetPadding(FMargin(0.f, 14.f, 0.f, 0.f));
	}
	ExamCardBox = WidgetTree->ConstructWidget<UVerticalBox>();
	Scroll->AddChild(ExamCardBox);

	// The footer: hold the microphone in a voice training, type in a text one.
	UBorder* Rule = WidgetTree->ConstructWidget<UBorder>();
	Rule->SetBrushColor(StationUi::PanelEdge);
	Rule->SetPadding(FMargin(0.f, 0.5f));
	if (UVerticalBoxSlot* RuleSlot = Column->AddChildToVerticalBox(Rule))
	{
		RuleSlot->SetPadding(FMargin(0.f, 12.f, 0.f, 0.f));
	}
	UVerticalBox* Footer = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UVerticalBoxSlot* FooterSlot = Column->AddChildToVerticalBox(Footer))
	{
		FooterSlot->SetPadding(FMargin(0.f, 14.f, 0.f, 0.f));
	}
	BuildMicrophone(*Footer);

	UHorizontalBox* Typed = WidgetTree->ConstructWidget<UHorizontalBox>();
	ExamTypedRow = Typed;
	Footer->AddChild(Typed);
	ExamInput = WidgetTree->ConstructWidget<UEditableTextBox>();
	ExamInput->SetHintText(LOCTEXT("ExamHint", "Ex.: hemograma completo"));
	ExamInput->OnTextCommitted.AddDynamic(this, &UStationHudWidget::HandleExamCommitted);
	if (UHorizontalBoxSlot* InputSlot = Typed->AddChildToHorizontalBox(ExamInput))
	{
		InputSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		InputSlot->SetVerticalAlignment(VAlign_Center);
	}
	ExamButton = StationUi::AddButton(*WidgetTree, *Typed, LOCTEXT("ExamSubmit", "Solicitar"));
	ExamButton->OnClicked.AddDynamic(this, &UStationHudWidget::HandleRequestExam);
	StationUi::MakePrimary(*ExamButton);
	StationUi::StyleInput(*ExamInput);
	if (UHorizontalBoxSlot* ButtonSlot = Cast<UHorizontalBoxSlot>(ExamButton->Slot))
	{
		ButtonSlot->SetPadding(FMargin(10.f, 0.f, 0.f, 0.f));
		ButtonSlot->SetVerticalAlignment(VAlign_Center);
	}
	ExamErrorText = StationUi::AddText(*WidgetTree, *Footer, FText::GetEmpty(), 15, false, StationUi::Caution, 8.f);
}

void UStationHudWidget::BuildMicrophone(UVerticalBox& Footer)
{
	// In a voice training the request is said aloud while this button is held
	// (#364); releasing it goes back to the dialogue. It looks like a recorder's.
	UVerticalBox* Box = WidgetTree->ConstructWidget<UVerticalBox>();
	MicrophoneBox = Box;
	if (UVerticalBoxSlot* BoxSlot = Footer.AddChildToVerticalBox(Box))
	{
		BoxSlot->SetHorizontalAlignment(HAlign_Center);
	}

	USizeBox* Area = WidgetTree->ConstructWidget<USizeBox>();
	Area->SetWidthOverride(112.f);
	Area->SetHeightOverride(112.f);
	if (UVerticalBoxSlot* AreaSlot = Box->AddChildToVerticalBox(Area))
	{
		AreaSlot->SetHorizontalAlignment(HAlign_Center);
	}
	UOverlay* Stack = WidgetTree->ConstructWidget<UOverlay>();
	Area->SetContent(Stack);

	// The pulse around the button while it records (`NativeTick`).
	USizeBox* RingSize = WidgetTree->ConstructWidget<USizeBox>();
	RingSize->SetWidthOverride(96.f);
	RingSize->SetHeightOverride(96.f);
	if (UOverlaySlot* RingSlot = Stack->AddChildToOverlay(RingSize))
	{
		RingSlot->SetHorizontalAlignment(HAlign_Center);
		RingSlot->SetVerticalAlignment(VAlign_Center);
	}
	MicrophoneRing = StationUi::MakeRounded(*WidgetTree, FLinearColor::Transparent, 48.f, FMargin(0.f),
		StationUi::RecordingInk, 3.f);
	MicrophoneRing->SetVisibility(ESlateVisibility::Hidden);
	RingSize->SetContent(MicrophoneRing);

	USizeBox* ButtonSize = WidgetTree->ConstructWidget<USizeBox>();
	ButtonSize->SetWidthOverride(84.f);
	ButtonSize->SetHeightOverride(84.f);
	if (UOverlaySlot* ButtonSlot = Stack->AddChildToOverlay(ButtonSize))
	{
		ButtonSlot->SetHorizontalAlignment(HAlign_Center);
		ButtonSlot->SetVerticalAlignment(VAlign_Center);
	}
	AskAloudButton = WidgetTree->ConstructWidget<UButton>();
	AskAloudButton->OnPressed.AddDynamic(this, &UStationHudWidget::HandleAskExamAloud);
	AskAloudButton->OnReleased.AddDynamic(this, &UStationHudWidget::HandleReleaseExamAloud);
	ButtonSize->SetContent(AskAloudButton);

	// A microphone drawn from rounded boxes: the capsule, its stand and its base.
	UVerticalBox* Icon = WidgetTree->ConstructWidget<UVerticalBox>();
	AskAloudButton->AddChild(Icon);
	auto AddPart = [this, Icon](float Width, float Height, float Radius, bool bOutlined, float SpaceAbove)
	{
		USizeBox* PartSize = WidgetTree->ConstructWidget<USizeBox>();
		PartSize->SetWidthOverride(Width);
		PartSize->SetHeightOverride(Height);
		if (UVerticalBoxSlot* PartSlot = Icon->AddChildToVerticalBox(PartSize))
		{
			PartSlot->SetHorizontalAlignment(HAlign_Center);
			PartSlot->SetPadding(FMargin(0.f, SpaceAbove, 0.f, 0.f));
		}
		PartSize->SetContent(StationUi::MakeRounded(*WidgetTree, bOutlined ? FLinearColor::Transparent : StationUi::Ink,
			Radius, FMargin(0.f), StationUi::Ink, bOutlined ? 3.f : 0.f));
	};
	AddPart(18.f, 28.f, 9.f, true, 0.f);
	AddPart(3.f, 7.f, 1.5f, false, 2.f);
	AddPart(18.f, 3.f, 1.5f, false, 0.f);

	// A fixed height, so the panel never jumps as the status changes.
	USizeBox* StatusSize = WidgetTree->ConstructWidget<USizeBox>();
	StatusSize->SetHeightOverride(24.f);
	if (UVerticalBoxSlot* StatusSlot = Box->AddChildToVerticalBox(StatusSize))
	{
		StatusSlot->SetHorizontalAlignment(HAlign_Center);
		StatusSlot->SetPadding(FMargin(0.f, 6.f, 0.f, 0.f));
	}
	ExamAloudText = WidgetTree->ConstructWidget<UTextBlock>();
	ExamAloudText->SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 15));
	ExamAloudText->SetJustification(ETextJustify::Center);
	StatusSize->SetContent(ExamAloudText);
	MicrophoneLook = EMicrophoneLook::Recording; // forces the first `RefreshMicrophone` to style it
	RefreshMicrophone();
}

void UStationHudWidget::BuildDocumentViewer(UOverlay& Root)
{
	// A released document, read over the scene like a printed sheet.
	UBorder* Dim = WidgetTree->ConstructWidget<UBorder>();
	Dim->SetBrushColor(FLinearColor(0.f, 0.f, 0.f, 0.6f));
	Dim->SetHorizontalAlignment(HAlign_Center);
	Dim->SetVerticalAlignment(VAlign_Center);
	DocumentViewer = Dim;
	StationUi::SetShown(DocumentViewer, false);
	if (UOverlaySlot* Slot = Root.AddChildToOverlay(Dim))
	{
		Slot->SetHorizontalAlignment(HAlign_Fill);
		Slot->SetVerticalAlignment(VAlign_Fill);
	}

	USizeBox* Size = WidgetTree->ConstructWidget<USizeBox>();
	Size->SetWidthOverride(760.f);
	Size->SetMaxDesiredHeight(780.f);
	Dim->SetContent(Size);
	UBorder* Sheet = StationUi::MakeRounded(*WidgetTree, StationUi::Paper, 12.f, FMargin(0.f));
	Size->SetContent(Sheet);
	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>();
	Sheet->SetContent(Column);

	UHorizontalBox* Header = WidgetTree->ConstructWidget<UHorizontalBox>();
	if (UVerticalBoxSlot* HeaderSlot = Column->AddChildToVerticalBox(Header))
	{
		HeaderSlot->SetPadding(FMargin(28.f, 22.f, 18.f, 14.f));
	}
	UVerticalBox* Titles = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UHorizontalBoxSlot* TitlesSlot = Header->AddChildToHorizontalBox(Titles))
	{
		TitlesSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	}
	DocumentCategoryText = StationUi::AddText(*WidgetTree, *Titles, FText::GetEmpty(), 14, false, StationUi::PaperMuted, 0.f);
	DocumentTitleText = StationUi::AddText(*WidgetTree, *Titles, FText::GetEmpty(), 22, true, StationUi::PaperInk, 2.f);
	UButton* Close = StationUi::MakeFlatButton(*WidgetTree, FText::FromString(TEXT("×")), 28, StationUi::PaperInk);
	Close->SetToolTipText(LOCTEXT("CloseDocument", "Fechar documento"));
	Close->OnClicked.AddDynamic(this, &UStationHudWidget::HandleCloseDocument);
	if (UHorizontalBoxSlot* CloseSlot = Header->AddChildToHorizontalBox(Close))
	{
		CloseSlot->SetVerticalAlignment(VAlign_Top);
	}

	UBorder* Rule = WidgetTree->ConstructWidget<UBorder>();
	Rule->SetBrushColor(StationUi::PaperEdge);
	Rule->SetPadding(FMargin(0.f, 0.5f));
	Column->AddChild(Rule);

	DocumentScroll = WidgetTree->ConstructWidget<UScrollBox>();
	if (UVerticalBoxSlot* ScrollSlot = Column->AddChildToVerticalBox(DocumentScroll))
	{
		ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	}
	DocumentBody = WidgetTree->ConstructWidget<UVerticalBox>();
	DocumentScroll->AddChild(DocumentBody);
	if (UScrollBoxSlot* BodySlot = Cast<UScrollBoxSlot>(DocumentBody->Slot))
	{
		BodySlot->SetPadding(FMargin(28.f, 10.f, 28.f, 26.f));
	}
}

void UStationHudWidget::RefreshExams()
{
	const bool bAloud = Flow->ShouldRequestExamsAloud();
	StationUi::SetShown(MicrophoneBox, bAloud);
	StationUi::SetShown(ExamTypedRow, !bAloud);
	// Disabling a held button would lose its release, so it stays enabled while the run goes on.
	AskAloudButton->SetIsEnabled(Flow->CanFinish());
	if (!Flow->CanFinish())
	{
		bMicrophoneHeld = false;
		bMicrophoneAccepted = false;
	}
	RefreshMicrophone();

	const int32 Asked = Flow->GetExamRequests().Num() + (Flow->IsExamRequestInFlight() || Flow->IsSpokenExamInFlight() ? 1 : 0);
	ExamTabText->SetText(Asked > 0
		? FText::Format(LOCTEXT("ExamsTabCount", "Exames · {0}"), FText::AsNumber(Asked))
		: LOCTEXT("ExamsTab", "Exames"));
	RefreshExamCards();

	StationUi::SetShown(ExamErrorText, !Flow->GetExamErrorText().IsEmpty());
	ExamErrorText->SetText(Flow->GetExamErrorText());
	ExamButton->SetIsEnabled(Flow->CanRequestExam());
	RestoreUnsent(*ExamInput, [this]() { return Flow->TakeUnsentExamRequest(); });
}

void UStationHudWidget::RefreshExamCards()
{
	const TArray<FStationExamRequest>& Requests = Flow->GetExamRequests();
	const TArray<FStationImpresso>& Released = Flow->GetReleasedImpressos();
	// Everything the cards show: the requests, the documents, the pending request
	// and the control the empty panel names.
	const bool bAloud = Flow->ShouldRequestExamsAloud();
	FString Key = FString::Printf(TEXT("%d|%d|%d|"), Requests.Num(), Released.Num(), bAloud ? 1 : 0);
	if (Flow->IsExamRequestInFlight())
	{
		Key += TEXT("typed:") + Flow->GetPendingExamRequestText();
	}
	if (Flow->IsSpokenExamInFlight())
	{
		Key += TEXT("spoken:") + Flow->GetSpokenExamText();
	}
	if (Key == ExamCardsKey)
	{
		return;
	}
	ExamCardsKey = Key;
	ExamCardBox->ClearChildren();
	DocumentLinks.Reset();

	TSet<FString> Linked;
	for (const FStationExamRequest& Request : Requests)
	{
		AddExamCard(Request);
		for (const FStationImpresso& Impresso : Request.Reply.NewlyReleased)
		{
			Linked.Add(Impresso.Id);
		}
	}
	if (Flow->IsExamRequestInFlight())
	{
		AddPendingExamCard(Flow->GetPendingExamRequestText());
	}
	if (Flow->IsSpokenExamInFlight())
	{
		const FString& Heard = Flow->GetSpokenExamText();
		AddPendingExamCard(Heard.IsEmpty() ? FString(TEXT("...")) : Heard);
	}
	if (ExamCardBox->GetChildrenCount() == 0)
	{
		StationUi::AddText(*WidgetTree, *ExamCardBox, bAloud
			? LOCTEXT("NoExamsAloud", "Nenhum exame solicitado ainda. Segure o microfone e diga o que você solicita.")
			: LOCTEXT("NoExamsTyped", "Nenhum exame solicitado ainda. Descreva abaixo o que você solicita."),
			15, false, StationUi::Muted, 0.f);
	}

	// Documents released outside these requests, by a turn to the examiner.
	TArray<const FStationImpresso*> Others;
	for (const FStationImpresso& Impresso : Released)
	{
		if (!Linked.Contains(Impresso.Id))
		{
			Others.Add(&Impresso);
		}
	}
	if (Others.Num() > 0)
	{
		StationUi::AddText(*WidgetTree, *ExamCardBox, LOCTEXT("OtherDocuments", "Outros documentos liberados"), 15, true,
			StationUi::Muted, 10.f);
		for (const FStationImpresso* Impresso : Others)
		{
			AddDocumentLink(*ExamCardBox, *Impresso);
		}
	}
}

namespace
{
	/** The status of a request, as a small colored label. */
	UBorder* MakeChip(UWidgetTree& Tree, const FText& Label, const FLinearColor& Fill, const FLinearColor& Ink)
	{
		UBorder* Chip = StationUi::MakeRounded(Tree, Fill, 11.f, FMargin(10.f, 3.f));
		UTextBlock* Text = Tree.ConstructWidget<UTextBlock>();
		Text->SetText(Label);
		Text->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 13));
		Text->SetColorAndOpacity(FSlateColor(Ink));
		Chip->SetContent(Text);
		return Chip;
	}

	/** A card's column, with the request and its status label in the first row. */
	UVerticalBox* AddCard(UWidgetTree& Tree, UVerticalBox& Parent, const FString& Text, UBorder* Chip)
	{
		UBorder* Card = StationUi::MakeRounded(Tree, StationUi::Raised, 8.f, FMargin(14.f, 12.f));
		if (UVerticalBoxSlot* CardSlot = Parent.AddChildToVerticalBox(Card))
		{
			CardSlot->SetPadding(FMargin(0.f, Parent.GetChildrenCount() > 1 ? 10.f : 0.f, 0.f, 0.f));
		}
		UVerticalBox* Column = Tree.ConstructWidget<UVerticalBox>();
		Card->SetContent(Column);
		UHorizontalBox* Row = Tree.ConstructWidget<UHorizontalBox>();
		Column->AddChild(Row);
		UTextBlock* Title = Tree.ConstructWidget<UTextBlock>();
		Title->SetText(FText::FromString(Text));
		Title->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 16));
		Title->SetColorAndOpacity(FSlateColor(StationUi::Ink));
		Title->SetAutoWrapText(true);
		if (UHorizontalBoxSlot* TitleSlot = Row->AddChildToHorizontalBox(Title))
		{
			TitleSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		}
		if (UHorizontalBoxSlot* ChipSlot = Row->AddChildToHorizontalBox(Chip))
		{
			ChipSlot->SetPadding(FMargin(10.f, 0.f, 0.f, 0.f));
			ChipSlot->SetVerticalAlignment(VAlign_Top);
		}
		return Column;
	}

}

void UStationHudWidget::AddExamCard(const FStationExamRequest& Request)
{
	// Phoenix's feedback is the whole answer: a declined request shows that it
	// was declined and nothing else.
	const FStationImpressoReply& Reply = Request.Reply;
	UBorder* Chip = Reply.Decision == EStationImpressoDecision::Released
		? MakeChip(*WidgetTree, LOCTEXT("ExamReleased", "Liberado"), StationUi::ReleasedFill, StationUi::ReleasedInk)
		: Reply.Decision == EStationImpressoDecision::AlreadyReleased
		? MakeChip(*WidgetTree, LOCTEXT("ExamAlreadyReleased", "Já liberado"), StationUi::NeutralFill, StationUi::NeutralInk)
		: MakeChip(*WidgetTree, LOCTEXT("ExamUnavailable", "Não disponível"), StationUi::DeclinedFill, StationUi::DeclinedInk);
	UVerticalBox* Column = AddCard(*WidgetTree, *ExamCardBox, Request.Text, Chip);
	if (Reply.NewlyReleased.Num() == 1)
	{
		AddDocumentLink(*Column, Reply.NewlyReleased[0], LOCTEXT("OpenOneDocument", "Ver documento  ›"));
	}
	else
	{
		for (const FStationImpresso& Impresso : Reply.NewlyReleased)
		{
			AddDocumentLink(*Column, Impresso);
		}
	}
	if (Reply.NewlyReleased.Num() == 0 && !Reply.FeedbackMessage.IsEmpty())
	{
		StationUi::AddText(*WidgetTree, *Column, FText::FromString(Reply.FeedbackMessage), 14, false, StationUi::Muted, 6.f);
	}
}

void UStationHudWidget::AddPendingExamCard(const FString& Text)
{
	AddCard(*WidgetTree, *ExamCardBox, Text,
		MakeChip(*WidgetTree, LOCTEXT("ExamPending", "Solicitando..."), StationUi::NeutralFill, StationUi::NeutralInk));
}

void UStationHudWidget::AddDocumentLink(UVerticalBox& Parent, const FStationImpresso& Impresso, const FText& Label)
{
	UButton* Open = StationUi::MakeFlatButton(*WidgetTree,
		Label.IsEmpty() ? FText::Format(LOCTEXT("OpenDocumentLink", "{0}  ›"), FText::FromString(Impresso.Title)) : Label,
		15, StationUi::Link, true);
	if (UTextBlock* Text = Cast<UTextBlock>(Open->GetChildAt(0)))
	{
		Text->SetAutoWrapText(true);
	}
	if (UVerticalBoxSlot* LinkSlot = Parent.AddChildToVerticalBox(Open))
	{
		LinkSlot->SetPadding(FMargin(-6.f, 6.f, 0.f, 0.f));
		LinkSlot->SetHorizontalAlignment(HAlign_Left);
	}
	UStationDocumentLink* Link = NewObject<UStationDocumentLink>(this);
	Link->Hud = this;
	Link->ImpressoId = Impresso.Id;
	Open->OnClicked.AddDynamic(Link, &UStationDocumentLink::HandleClicked);
	DocumentLinks.Add(Link);
}

void UStationHudWidget::RefreshMicrophone()
{
	if (!AskAloudButton)
	{
		return;
	}
	const EMicrophoneLook Look = !bMicrophoneHeld ? EMicrophoneLook::Idle
		: !bMicrophoneAccepted ? EMicrophoneLook::Waiting
		: Flow && Flow->IsArmingExamAloud() ? EMicrophoneLook::Arming
		: Flow && (Flow->IsListeningForExam() || Flow->IsSpokenExamInFlight()) ? EMicrophoneLook::Recording
		: EMicrophoneLook::Idle;
	if (Look != MicrophoneLook)
	{
		MicrophoneLook = Look;
		if (Look == EMicrophoneLook::Recording)
		{
			RecordingSince = FPlatformTime::Seconds();
		}
		const FLinearColor Fill = Look == EMicrophoneLook::Recording ? StationUi::Recording : StationUi::Raised;
		const FLinearColor Edge = Look == EMicrophoneLook::Recording ? StationUi::RecordingInk
			: Look == EMicrophoneLook::Arming ? StationUi::Caution
			: Look == EMicrophoneLook::Waiting ? StationUi::PanelEdge
			: StationUi::Quiet;
		FButtonStyle Style;
		Style.SetNormal(StationUi::RoundedBrush(Fill, 42.f, Edge, 2.5f));
		Style.SetHovered(StationUi::RoundedBrush(Look == EMicrophoneLook::Idle ? StationUi::RaisedHover : Fill,
			42.f, Look == EMicrophoneLook::Idle ? StationUi::Ink : Edge, 2.5f));
		Style.SetPressed(StationUi::RoundedBrush(Fill, 42.f, Edge, 2.5f));
		Style.SetDisabled(StationUi::RoundedBrush(StationUi::Raised, 42.f, StationUi::PanelEdge, 2.5f));
		Style.SetNormalPadding(FMargin(0.f));
		Style.SetPressedPadding(FMargin(0.f));
		AskAloudButton->SetStyle(Style);
		MicrophoneRing->SetVisibility(Look == EMicrophoneLook::Recording ? ESlateVisibility::HitTestInvisible
			: ESlateVisibility::Hidden);
	}

	if (Look == EMicrophoneLook::Recording)
	{
		const int32 Seconds = FMath::FloorToInt32(FPlatformTime::Seconds() - RecordingSince);
		ExamAloudText->SetText(FText::Format(LOCTEXT("ExamAloudRecording", "Gravando {0}:{1} · solte para enviar"),
			FText::AsNumber(Seconds / 60), FText::FromString(FString::Printf(TEXT("%02d"), Seconds % 60))));
		ExamAloudText->SetColorAndOpacity(FSlateColor(StationUi::RecordingInk));
	}
	else if (Look == EMicrophoneLook::Arming)
	{
		ExamAloudText->SetText(LOCTEXT("ExamAloudArming", "Conectando..."));
		ExamAloudText->SetColorAndOpacity(FSlateColor(StationUi::Caution));
	}
	else if (Look == EMicrophoneLook::Waiting)
	{
		ExamAloudText->SetText(LOCTEXT("ExamAloudWaiting", "Aguarde a resposta do pedido anterior"));
		ExamAloudText->SetColorAndOpacity(FSlateColor(StationUi::NeutralInk));
	}
	else
	{
		ExamAloudText->SetText(LOCTEXT("ExamAloudIdle", "Segure para pedir um exame"));
		ExamAloudText->SetColorAndOpacity(FSlateColor(StationUi::Muted));
	}
}

void UStationHudWidget::OpenDocument(const FString& ImpressoId)
{
	if (!Flow || !DocumentViewer)
	{
		return;
	}
	const FStationImpresso* Impresso = Flow->GetReleasedImpressos().FindByPredicate(
		[&ImpressoId](const FStationImpresso& Each) { return Each.Id == ImpressoId; });
	if (!Impresso)
	{
		return;
	}
	DocumentCategoryText->SetText(DocumentCategoryName(Impresso->Category));
	DocumentTitleText->SetText(FText::FromString(Impresso->Title));
	DocumentBody->ClearChildren();
	AddDocumentLines(*WidgetTree, *DocumentBody, Impresso->Content);
	DocumentScroll->ScrollToStart();
	StationUi::SetShown(DocumentViewer, true);
}

void UStationHudWidget::OpenExams()
{
	StationUi::SetShown(ExamDrawer, true);
	StationUi::SetShown(ExamTab, false);
}

void UStationHudWidget::CloseExams()
{
	StationUi::SetShown(ExamDrawer, false);
	StationUi::SetShown(ExamTab, true);
}

void UStationHudWidget::RequestExam()
{
	if (Flow && ExamInput && Flow->RequestExam(ExamInput->GetText().ToString()))
	{
		ExamInput->SetText(FText::GetEmpty());
	}
}

void UStationHudWidget::HandleOpenExams()
{
	OpenExams();
}

void UStationHudWidget::HandleCloseExams()
{
	CloseExams();
}

void UStationHudWidget::HandleCloseDocument()
{
	StationUi::SetShown(DocumentViewer, false);
}

void UStationHudWidget::HandleAskExamAloud()
{
	bMicrophoneHeld = true;
	// Refused while the previous spoken request still waits for Phoenix.
	bMicrophoneAccepted = Flow && Flow->AskExamAloud();
	RefreshMicrophone();
}

void UStationHudWidget::HandleReleaseExamAloud()
{
	bMicrophoneHeld = false;
	// Only the press the flow took is released to it.
	if (Flow && bMicrophoneAccepted)
	{
		Flow->ReleaseExamAloud();
	}
	bMicrophoneAccepted = false;
	RefreshMicrophone();
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
	else if (Voice.bMicrophoneUnavailable)
	{
		Status = LOCTEXT("MicrophoneUnavailable", "Microfone indisponível. Continue por escrito.");
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
	if (MicrophoneRing && MicrophoneLook == EMicrophoneLook::Recording)
	{
		// The pulse: grows from the button and fades, about once a second.
		const float Phase = FMath::Fmod(static_cast<float>(FPlatformTime::Seconds() - RecordingSince), 1.1f) / 1.1f;
		MicrophoneRing->SetRenderScale(FVector2D(0.9f + 0.3f * Phase));
		MicrophoneRing->SetRenderOpacity(0.9f * (1.f - Phase));
		RefreshMicrophone();
	}
}

TSharedRef<SWidget> UStationInvalidatedWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UVerticalBox* Column = StationUi::MakeCenteredCard(*WidgetTree, 760.f, 900.f, false);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("InvalidatedTitle", "Treino invalidado"), 32, true,
			StationUi::Ink, 0.f);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("InvalidatedBody",
			"A conexão com o servidor caiu e o treino não pode continuar. Esta tentativa não tem resultado nem feedback."), 18);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("InvalidatedRestart",
			"Reinicie a estação para começar de novo."), 16, false, StationUi::Muted);
		UButton* Restart = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("RestartStation", "Reiniciar estação"));
		Restart->OnClicked.AddDynamic(this, &UStationInvalidatedWidget::HandleRestart);
	}
	return Super::RebuildWidget();
}

void UStationInvalidatedWidget::HandleRestart()
{
	OnRestart.ExecuteIfBound();
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
