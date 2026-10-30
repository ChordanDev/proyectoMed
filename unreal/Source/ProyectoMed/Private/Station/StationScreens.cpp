#include "Station/StationScreens.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/ButtonSlot.h"
#include "Components/EditableTextBox.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "Components/ScrollBox.h"
#include "Components/ScrollBoxSlot.h"
#include "Components/SizeBox.h"
#include "Components/Spacer.h"
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

	// The side panels' layout, shared by the conversation and the exam requests.
	constexpr float SidePanelWidth = 440.f;
	constexpr float SidePanelPadding = 24.f;
	/** How far the HUD stays from the screen's edges. */
	constexpr float HudEdge = 32.f;
	/** Wide enough for "+00:00", so the timer's panel holds still: Manrope's digits differ in width. */
	constexpr float TimerColumnWidth = 148.f;
	/** The voice's long notices wrap, so the timer's panel keeps clear of the panels beside it. */
	constexpr float VoiceStatusWrapWidth = 200.f;
	constexpr float VoiceStatusMinWidth = 190.f;
	/** "Tempo esgotado ·" on one line and "além do tempo" on the next, so the overtime stays as wide as the time left. */
	constexpr float TimerLabelWrapWidth = 125.f;
	constexpr float BriefReaderWidth = 600.f;
	/** The conversation's bubbles in the mockups; opaque, like everything read on a panel (#444). */
	const FLinearColor LearnerBubbleFill(FColor(0x22, 0x4A, 0x45));
	const FLinearColor PatientBubbleFill(FColor(0x24, 0x31, 0x3B));
	/** How far a bubble stays from the other side, so the two speakers read apart. */
	constexpr float BubbleIndent = 48.f;
	constexpr float BubblePadding = 14.f;
	/** Room the conversation's scroll bar takes once it shows. */
	constexpr float ScrollBarAllowance = 12.f;
	/** The widest a chat bubble's text runs, so it wraps inside the panel. */
	constexpr float BubbleWrapWidth =
		SidePanelWidth - 2.f * SidePanelPadding - BubbleIndent - 2.f * BubblePadding - ScrollBarAllowance;
	/** The widest a text runs in the exam panel's list, outside a card. */
	constexpr float ExamListWrapWidth = SidePanelWidth - 2.f * SidePanelPadding - ScrollBarAllowance;
	constexpr float CardPadding = 18.f;
	/** Over the document's dim, as the mockups' `.scrim-full` there. */
	const FLinearColor DocumentDim = StationUi::ScrimColor.CopyWithNewOpacity(0.7f);
	/** The sheet's place on screen: clear of the exam requests on the right. */
	const FMargin DocumentMargin(140.f, 72.f, 0.f, 72.f);
	constexpr float DocumentWidth = 760.f;
	constexpr float DocumentSidePadding = 48.f;
	/** The widest a text runs inside a request card. */
	constexpr float CardWrapWidth = ExamListWrapWidth - 2.f * CardPadding;
	/** A card's title leaves room beside it for the widest status label, "Não disponível". */
	constexpr float CardTitleWrapWidth = CardWrapWidth - 150.f;

	/**
	 * Wraps `Text` at a fixed width. Auto wrap lays a new text out unwrapped for
	 * one frame, so a list rebuilt with it jumps before it settles.
	 */
	void WrapAt(UTextBlock& Text, float Width)
	{
		Text.SetAutoWrapText(false);
		Text.SetWrapTextAt(Width);
	}

	/** A rule across a side panel's `Column`. */
	void AddRule(UWidgetTree& Tree, UVerticalBox& Column, const FLinearColor& Color, float SpaceAbove)
	{
		UBorder* Rule = Tree.ConstructWidget<UBorder>();
		Rule->SetBrushColor(Color);
		Rule->SetPadding(FMargin(0.f, 0.5f));
		if (UVerticalBoxSlot* RuleSlot = Column.AddChildToVerticalBox(Rule))
		{
			RuleSlot->SetPadding(FMargin(0.f, SpaceAbove, 0.f, 0.f));
		}
	}

	/** A microphone drawn from rounded boxes: the capsule, its stand and its base. */
	void AddMicrophoneIcon(UWidgetTree& Tree, UVerticalBox& Icon, const FLinearColor& Color, float Scale)
	{
		const auto AddPart = [&Tree, &Icon, &Color, Scale](float Width, float Height, float Radius, bool bOutlined, float SpaceAbove)
		{
			USizeBox* PartSize = Tree.ConstructWidget<USizeBox>();
			PartSize->SetWidthOverride(Width * Scale);
			PartSize->SetHeightOverride(Height * Scale);
			if (UVerticalBoxSlot* PartSlot = Icon.AddChildToVerticalBox(PartSize))
			{
				PartSlot->SetHorizontalAlignment(HAlign_Center);
				PartSlot->SetPadding(FMargin(0.f, SpaceAbove * Scale, 0.f, 0.f));
			}
			PartSize->SetContent(StationUi::MakeRounded(Tree, bOutlined ? FLinearColor::Transparent : Color,
				Radius * Scale, FMargin(0.f), Color, bOutlined ? 3.f * Scale : 0.f));
		};
		AddPart(18.f, 28.f, 9.f, true, 0.f);
		AddPart(3.f, 7.f, 1.5f, false, 2.f);
		AddPart(18.f, 3.f, 1.5f, false, 0.f);
	}

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

	/** One line of a document, wrapped to the sheet. */
	void AddSheetLine(UWidgetTree& Tree, UVerticalBox& Body, const FString& Text, FName Weight, float Pixels,
		const FLinearColor& Color, float SpaceAbove)
	{
		UTextBlock* Line = Tree.ConstructWidget<UTextBlock>();
		Line->SetText(FText::FromString(Text));
		Line->SetFont(StationUi::MockupFont(Weight, Pixels));
		Line->SetColorAndOpacity(FSlateColor(Color));
		Line->SetAutoWrapText(true);
		if (UVerticalBoxSlot* LineSlot = Body.AddChildToVerticalBox(Line))
		{
			LineSlot->SetPadding(FMargin(0.f, SpaceAbove, 0.f, 0.f));
		}
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
					AddSheetLine(Tree, Body, Label, StationUi::FontBold, bItem ? 13.f : 16.f,
						bItem ? StationUi::PaperMuted : StationUi::PaperInk, Space);
					if (!Rest.IsEmpty())
					{
						AddSheetLine(Tree, Body, Rest, StationUi::FontRegular, 16.f, StationUi::PaperInk, 2.f);
					}
					continue;
				}
			}
			const FString Text = Line.Replace(TEXT("**"), TEXT(""));
			AddSheetLine(Tree, Body, bItem ? TEXT("•  ") + Text : Text, StationUi::FontRegular, 16.f, StationUi::PaperInk, Space);
		}
	}

	/** Phoenix's exact points with a decimal comma; never parsed, rounded or rescaled. */
	FText DisplayPoints(const FString& Points)
	{
		return FText::FromString(Points.Replace(TEXT("."), TEXT(",")));
	}

	/** What every state of the result screen says it is not (ADR-012). */
	FText ResultDisclaimer()
	{
		return LOCTEXT("ResultDisclaimer",
			"Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica aprovação, reprovação, certificação ou prontidão para o exame.");
	}
}

// The learner-facing copy is Brazilian Portuguese, matching the web station
// (web/src/features/station/i18n/pt-BR.json) where both say the same thing.

TSharedRef<SWidget> UStationMicrophoneWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UVerticalBox* Column = StationUi::MakeCenteredCard(*WidgetTree, 760.f, 900.f);
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
		StationUi::MakePrimary(*Allow);
		UButton* NotNow = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("MicrophoneNotNow", "Agora não"), 12.f);
		NotNow->OnClicked.AddDynamic(this, &UStationMicrophoneWidget::HandleNotNow);
		StationUi::MakeSecondary(*NotNow);
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

namespace
{
	/** What the main menu says about a mode. */
	struct FMenuMode
	{
		FText Title;
		FText Description;
		TArray<FText> Chips;
		/** Beside the chips, when the mode has one. */
		FText Note;
		FLinearColor Accent;
	};

	/** The mode that is not selected, as in the mockups. */
	constexpr float DimmedModeOpacity = 0.45f;
	constexpr float ModeFadeSeconds = 0.25f;
	/** Around a mode, between its text and the keyboard's ring. */
	constexpr float ModeRingSpace = 10.f;
	/** How far a mode's lines sit in, past its mark. */
	constexpr float ModeIndent = 52.f;
	/** Off a title's box, above and below: the mockups' tight line, in Manrope's taller one. */
	constexpr float ModeTitleTrim = 10.f;

	/** Text that keeps to one line, `Pixels` tall as in the mockups. `LetterSpacing` is in thousandths of an em. */
	UTextBlock* MakeText(UWidgetTree& Tree, const FText& Text, FName Weight, float Pixels, const FLinearColor& Color,
		int32 LetterSpacing = 0)
	{
		UTextBlock* Block = Tree.ConstructWidget<UTextBlock>();
		Block->SetText(Text);
		FSlateFontInfo Font = StationUi::MockupFont(Weight, Pixels);
		Font.LetterSpacing = LetterSpacing;
		Block->SetFont(Font);
		Block->SetColorAndOpacity(FSlateColor(Color));
		return Block;
	}

	/** One row of the main menu: the mode's button, and beside it the arrow that enters it. */
	void AddMode(UWidgetTree& Tree, UVerticalBox& Parent, const FMenuMode& Mode, float SpaceAbove, UButton*& OutButton,
		UButton*& OutArrow)
	{
		UVerticalBox* Body = Tree.ConstructWidget<UVerticalBox>();

		UHorizontalBox* Heading = Tree.ConstructWidget<UHorizontalBox>();
		if (UVerticalBoxSlot* HeadingSlot = Body->AddChildToVerticalBox(Heading))
		{
			HeadingSlot->SetPadding(FMargin(0.f, -ModeTitleTrim, 0.f, -ModeTitleTrim));
		}
		if (UHorizontalBoxSlot* MarkSlot = Heading->AddChildToHorizontalBox(StationUi::MakeModeMark(Tree, Mode.Accent)))
		{
			MarkSlot->SetVerticalAlignment(VAlign_Center);
			MarkSlot->SetPadding(FMargin(0.f, 0.f, ModeIndent - 32.f, 0.f));
		}
		Heading->AddChild(MakeText(Tree, Mode.Title, StationUi::FontBold, 64.f, StationUi::InkTitle, -60));

		if (UVerticalBoxSlot* DescriptionSlot = Body->AddChildToVerticalBox(
				MakeText(Tree, Mode.Description, StationUi::FontMedium, 18.f, StationUi::InkBody)))
		{
			DescriptionSlot->SetPadding(FMargin(ModeIndent, 14.f, 0.f, 0.f));
		}

		UHorizontalBox* Chips = Tree.ConstructWidget<UHorizontalBox>();
		if (UVerticalBoxSlot* ChipsSlot = Body->AddChildToVerticalBox(Chips))
		{
			ChipsSlot->SetPadding(FMargin(ModeIndent, 14.f, 0.f, 0.f));
		}
		for (const FText& Chip : Mode.Chips)
		{
			if (UHorizontalBoxSlot* ChipSlot = Chips->AddChildToHorizontalBox(StationUi::MakeChip(Tree, Chip)))
			{
				ChipSlot->SetPadding(FMargin(0.f, 0.f, 8.f, 0.f));
			}
		}
		if (!Mode.Note.IsEmpty())
		{
			if (UHorizontalBoxSlot* NoteSlot = Chips->AddChildToHorizontalBox(
					MakeText(Tree, Mode.Note, StationUi::FontRegular, 13.f, StationUi::Muted)))
			{
				NoteSlot->SetVerticalAlignment(VAlign_Center);
				NoteSlot->SetPadding(FMargin(8.f, 0.f, 0.f, 0.f));
			}
		}

		UHorizontalBox* Row = Tree.ConstructWidget<UHorizontalBox>();
		if (UVerticalBoxSlot* RowSlot = Parent.AddChildToVerticalBox(Row))
		{
			RowSlot->SetPadding(FMargin(0.f, SpaceAbove, 0.f, 0.f));
		}
		OutButton = StationUi::MakeContentButton(Tree, *Body, FMargin(ModeRingSpace));
		Row->AddChild(OutButton);
		OutArrow = StationUi::MakeEnterArrow(Tree, Mode.Accent);
		if (UHorizontalBoxSlot* ArrowSlot = Row->AddChildToHorizontalBox(OutArrow))
		{
			ArrowSlot->SetVerticalAlignment(VAlign_Center);
			ArrowSlot->SetPadding(FMargin(24.f - ModeRingSpace, 0.f, 0.f, 0.f));
		}
	}
}

TSharedRef<SWidget> UStationMenuWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		// The menu takes the keys itself: nothing has to be focused for Enter and Esc to work.
		SetIsFocusable(true);

		UOverlay* Screen = WidgetTree->ConstructWidget<UOverlay>();
		WidgetTree->RootWidget = Screen;
		const auto Place = [Screen](UWidget* Widget, EHorizontalAlignment Horizontal, EVerticalAlignment Vertical, const FMargin& Padding)
		{
			if (UOverlaySlot* Slot = Screen->AddChildToOverlay(Widget))
			{
				Slot->SetHorizontalAlignment(Horizontal);
				Slot->SetVerticalAlignment(Vertical);
				Slot->SetPadding(Padding);
			}
		};

		// Until the doctor's office behind the menu exists (#431), a solid blue hides the
		// scene, patient included.
		Backdrop = WidgetTree->ConstructWidget<UBorder>();
		Backdrop->SetBrushColor(StationUi::MenuBackdrop);
		Place(Backdrop, HAlign_Fill, VAlign_Fill, FMargin(0.f));
		Place(StationUi::MakeScrim(*WidgetTree), HAlign_Fill, VAlign_Fill, FMargin(0.f));

		UVerticalBox* Brand = WidgetTree->ConstructWidget<UVerticalBox>();
		Place(Brand, HAlign_Left, VAlign_Top, FMargin(96.f, 80.f, 0.f, 0.f));
		UHorizontalBox* Wordmark = WidgetTree->ConstructWidget<UHorizontalBox>();
		Brand->AddChild(Wordmark);
		Wordmark->AddChild(MakeText(*WidgetTree, LOCTEXT("MenuTitleFirst", "Proyecto"), StationUi::FontExtraBold, 26.f, StationUi::InkTitle, -15));
		Wordmark->AddChild(MakeText(*WidgetTree, LOCTEXT("MenuTitleSecond", "Med"), StationUi::FontExtraBold, 26.f, StationUi::TreinoAccent, -15));
		if (UVerticalBoxSlot* TaglineSlot = Brand->AddChildToVerticalBox(MakeText(*WidgetTree,
				LOCTEXT("MenuTagline", "Estações práticas do Revalida"), StationUi::FontMedium, 14.f, StationUi::Muted)))
		{
			TaglineSlot->SetPadding(FMargin(0.f, 8.f, 0.f, 0.f));
		}

		UVerticalBox* Modes = WidgetTree->ConstructWidget<UVerticalBox>();
		Place(Modes, HAlign_Left, VAlign_Bottom, FMargin(96.f - ModeRingSpace, 0.f, 0.f, 96.f));

		UButton* Training = nullptr;
		UButton* TrainingEnter = nullptr;
		AddMode(*WidgetTree, *Modes, FMenuMode{
			LOCTEXT("MenuTraining", "Treino"),
			LOCTEXT("MenuTrainingNote", "Pratique a estação no seu ritmo, por texto ou por voz."),
			{LOCTEXT("MenuTrainingClock", "Relógio à vista"), LOCTEXT("MenuTrainingHelp", "Com ajuda")},
			FText::GetEmpty(),
			StationUi::TreinoAccent}, 0.f, Training, TrainingEnter);
		TrainingButton = Training;
		TrainingArrow = TrainingEnter;
		UButton* Exam = nullptr;
		UButton* ExamEnter = nullptr;
		AddMode(*WidgetTree, *Modes, FMenuMode{
			LOCTEXT("MenuSimulatedExam", "Prova simulada"),
			LOCTEXT("MenuSimulatedExamNote", "Uma estação completa, como no dia da prova prática."),
			{LOCTEXT("MenuExamVoiceOnly", "Só voz"), LOCTEXT("MenuExamNoHelp", "Sem ajuda"), LOCTEXT("MenuExamMinutes", "10 minutos")},
			LOCTEXT("MenuExamNotOfficial", "Não é nota oficial do Revalida."),
			StationUi::ProvaAccent}, 44.f - 2.f * ModeRingSpace, Exam, ExamEnter);
		SimulatedExamButton = Exam;
		SimulatedExamArrow = ExamEnter;

		TrainingButton->OnClicked.AddDynamic(this, &UStationMenuWidget::HandleSelectTraining);
		SimulatedExamButton->OnClicked.AddDynamic(this, &UStationMenuWidget::HandleSelectSimulatedExam);
		TrainingArrow->OnClicked.AddDynamic(this, &UStationMenuWidget::HandleTraining);
		SimulatedExamArrow->OnClicked.AddDynamic(this, &UStationMenuWidget::HandleSimulatedExam);
		// A button has one focus handler, and its ring is in it already.
		const auto SelectOnFocus = [this](UButton& Button, EStationSessionMode Mode)
		{
			Button.OnReceivedFocus.BindWeakLambda(this, [this, Ring = Button.OnReceivedFocus, Mode]()
			{
				Ring.ExecuteIfBound();
				SelectMode(Mode);
			});
		};
		SelectOnFocus(*TrainingButton, EStationSessionMode::Training);
		SelectOnFocus(*SimulatedExamButton, EStationSessionMode::SimulatedExam);

		UHorizontalBox* Footer = WidgetTree->ConstructWidget<UHorizontalBox>();
		if (UVerticalBoxSlot* FooterSlot = Modes->AddChildToVerticalBox(Footer))
		{
			FooterSlot->SetPadding(FMargin(ModeIndent + ModeRingSpace, 44.f - ModeRingSpace, 0.f, 0.f));
		}
		const auto AddGhost = [this, Footer](const FText& Label, float SpaceBefore)
		{
			UButton* Ghost = StationUi::AddButton(*WidgetTree, *Footer, Label);
			StationUi::MakeGhost(*Ghost);
			if (UHorizontalBoxSlot* GhostSlot = Cast<UHorizontalBoxSlot>(Ghost->Slot))
			{
				GhostSlot->SetPadding(FMargin(SpaceBefore, 0.f, 0.f, 0.f));
			}
			return Ghost;
		};
		HistoryButton = AddGhost(LOCTEXT("MenuHistory", "Histórico · em breve"), 0.f);
		HistoryButton->SetIsEnabled(false);
		SettingsButton = AddGhost(LOCTEXT("MenuSettings", "Ajustes · em breve"), 32.f);
		SettingsButton->SetIsEnabled(false);
		QuitButton = AddGhost(LOCTEXT("MenuQuit", "Sair"), 32.f);
		QuitButton->OnClicked.AddDynamic(this, &UStationMenuWidget::HandleQuit);

		UHorizontalBox* Hints = WidgetTree->ConstructWidget<UHorizontalBox>();
		Place(Hints, HAlign_Right, VAlign_Bottom, FMargin(0.f, 0.f, 48.f, 40.f));
		Hints->AddChild(StationUi::MakeKeyHint(*WidgetTree, FText::FromString(TEXT("↑↓")), LOCTEXT("MenuHintChoose", "Escolher")));
		for (const FText& Action : {LOCTEXT("MenuHintEnter", "Entrar"), LOCTEXT("MenuHintQuit", "Sair")})
		{
			const FText Key = FText::FromString(Hints->GetChildrenCount() == 1 ? TEXT("Enter") : TEXT("Esc"));
			if (UHorizontalBoxSlot* HintSlot = Hints->AddChildToHorizontalBox(StationUi::MakeKeyHint(*WidgetTree, Key, Action)))
			{
				HintSlot->SetPadding(FMargin(20.f, 0.f, 0.f, 0.f));
			}
		}

		SimulatedExamButton->SetRenderOpacity(DimmedModeOpacity);
		SimulatedExamArrow->SetRenderOpacity(0.f);
		SelectMode(EStationSessionMode::Training);
	}
	return Super::RebuildWidget();
}

void UStationMenuWidget::SetVisibility(ESlateVisibility InVisibility)
{
	const bool bOpens = GetVisibility() == ESlateVisibility::Collapsed && InVisibility != ESlateVisibility::Collapsed;
	Super::SetVisibility(InVisibility);
	if (bOpens)
	{
		SelectMode(EStationSessionMode::Training);
	}
}

void UStationMenuWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);

	// Nothing else takes the keyboard on this screen, and a click on the background drops it.
	if (!HasAnyUserFocus() && !HasFocusedDescendants())
	{
		SetKeyboardFocus();
	}

	const auto Fade = [InDeltaTime](UWidget& Widget, float Target)
	{
		Widget.SetRenderOpacity(FMath::FInterpConstantTo(Widget.GetRenderOpacity(), Target, InDeltaTime, 1.f / ModeFadeSeconds));
	};
	const bool bTraining = SelectedMode == EStationSessionMode::Training;
	Fade(*TrainingButton, bTraining ? 1.f : DimmedModeOpacity);
	Fade(*SimulatedExamButton, bTraining ? DimmedModeOpacity : 1.f);
	Fade(*TrainingArrow, bTraining ? 1.f : 0.f);
	Fade(*SimulatedExamArrow, bTraining ? 0.f : 1.f);
}

FReply UStationMenuWidget::NativeOnPreviewKeyDown(const FGeometry& InGeometry, const FKeyEvent& InKeyEvent)
{
	// Ahead of the focused button, which would only select its mode on Enter.
	const FKey Key = InKeyEvent.GetKey();
	if (Key == EKeys::Up || Key == EKeys::Down)
	{
		const bool bTraining = Key == EKeys::Up;
		SelectMode(bTraining ? EStationSessionMode::Training : EStationSessionMode::SimulatedExam);
		(bTraining ? TrainingButton : SimulatedExamButton)->SetKeyboardFocus();
		return FReply::Handled();
	}
	if (!InKeyEvent.IsRepeat() && Key == EKeys::Escape)
	{
		HandleQuit();
		return FReply::Handled();
	}
	// A focused "Sair" answers Enter itself.
	if (!InKeyEvent.IsRepeat() && Key == EKeys::Enter && !QuitButton->HasKeyboardFocus())
	{
		OnModeChosen.ExecuteIfBound(SelectedMode);
		return FReply::Handled();
	}
	return Super::NativeOnPreviewKeyDown(InGeometry, InKeyEvent);
}

void UStationMenuWidget::SelectMode(EStationSessionMode Mode)
{
	SelectedMode = Mode;
	const bool bTraining = Mode == EStationSessionMode::Training;
	// Hidden keeps an arrow's place, so nothing moves when the selection changes.
	if (TrainingArrow && SimulatedExamArrow)
	{
		TrainingArrow->SetVisibility(bTraining ? ESlateVisibility::Visible : ESlateVisibility::Hidden);
		SimulatedExamArrow->SetVisibility(bTraining ? ESlateVisibility::Hidden : ESlateVisibility::Visible);
	}
}

void UStationMenuWidget::HandleSelectTraining()
{
	SelectMode(EStationSessionMode::Training);
}

void UStationMenuWidget::HandleSelectSimulatedExam()
{
	SelectMode(EStationSessionMode::SimulatedExam);
}

void UStationMenuWidget::HandleTraining()
{
	OnModeChosen.ExecuteIfBound(EStationSessionMode::Training);
}

void UStationMenuWidget::HandleSimulatedExam()
{
	OnModeChosen.ExecuteIfBound(EStationSessionMode::SimulatedExam);
}

void UStationMenuWidget::HandleQuit()
{
	OnQuit.ExecuteIfBound();
}

TSharedRef<SWidget> UStationNoticeWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UVerticalBox* Column = StationUi::MakeCenteredCard(*WidgetTree, 760.f, 900.f);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("NoticeTitle", "Ferramenta Educacional"), 32, true,
			StationUi::Ink, 0.f);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("NoticeBody",
			"Ferramenta educacional independente para treino de habilidades clínicas. Não insira dados de pacientes reais."), 18);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("NoticeDisclaimer",
			"Estimativa educacional gerada por IA. Não é nota oficial do Revalida. Não indica aprovação, reprovação, certificação ou prontidão para o exame."),
			16, false, StationUi::Muted);
		UButton* Acknowledge = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("NoticeButton", "Entendi"));
		Acknowledge->OnClicked.AddDynamic(this, &UStationNoticeWidget::HandleAcknowledge);
		StationUi::MakePrimary(*Acknowledge);
	}
	return Super::RebuildWidget();
}

void UStationNoticeWidget::HandleAcknowledge()
{
	OnAcknowledged.ExecuteIfBound();
}

namespace
{
	/** What cannot be chosen right now, in the mockups: faded, as a disabled button fades its own label. */
	constexpr float UnavailableOpacity = 0.45f;
	/** The brief's edges, in the mockups: past the way back on top, and at the screen's sides. */
	const FMargin BriefPadding(96.f, 144.f, 96.f, 64.f);
	constexpr float TrainingsPanelWidth = 460.f;
	constexpr float ExamColumnWidth = 700.f;
	/** The mockups' tight title, as a share of Manrope's own line. */
	constexpr float BriefTitleLineHeight = 0.8f;

	/** Text that wraps under what `Parent` already holds. */
	UTextBlock* AddLine(UWidgetTree& Tree, UVerticalBox& Parent, const FText& Text, FName Weight, float Pixels,
		const FLinearColor& Color, float SpaceAbove, int32 LetterSpacing = 0)
	{
		UTextBlock* Line = MakeText(Tree, Text, Weight, Pixels, Color, LetterSpacing);
		Line->SetAutoWrapText(true);
		if (UVerticalBoxSlot* Slot = Parent.AddChildToVerticalBox(Line))
		{
			Slot->SetPadding(FMargin(0.f, SpaceAbove, 0.f, 0.f));
		}
		return Line;
	}

	/** A way into a training: its name, then an arrow, in an outlined box. */
	UButton* AddTrainingOption(UWidgetTree& Tree, UVerticalBox& Parent, const FText& Title)
	{
		UHorizontalBox* Row = Tree.ConstructWidget<UHorizontalBox>();
		if (UHorizontalBoxSlot* TitleSlot = Row->AddChildToHorizontalBox(
				MakeText(Tree, Title, StationUi::FontBold, 20.f, StationUi::InkTitle)))
		{
			TitleSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
			TitleSlot->SetVerticalAlignment(VAlign_Center);
		}
		if (UHorizontalBoxSlot* ArrowSlot = Row->AddChildToHorizontalBox(
				MakeText(Tree, FText::FromString(TEXT("→")), StationUi::FontBold, 22.f, StationUi::Ink)))
		{
			ArrowSlot->SetVerticalAlignment(VAlign_Center);
			ArrowSlot->SetPadding(FMargin(16.f, 0.f, 0.f, 0.f));
		}

		UBorder* Box = StationUi::MakeRounded(Tree, FLinearColor::Transparent, 12.f, FMargin(24.f), StationUi::ChipEdge, 1.f);
		Box->SetContent(Row);
		UButton* Button = StationUi::MakeContentButton(Tree, *Box, FMargin(0.f));
		if (UVerticalBoxSlot* Slot = Parent.AddChildToVerticalBox(Button))
		{
			Slot->SetPadding(FMargin(0.f, 18.f, 0.f, 0.f));
		}
		return Button;
	}

	/** One rule of a simulated exam, marked in its accent, in half of `Row`. */
	void AddExamRule(UWidgetTree& Tree, UHorizontalBox& Row, const FText& Rule, float SpaceBefore)
	{
		USizeBox* DotSize = Tree.ConstructWidget<USizeBox>();
		DotSize->SetWidthOverride(10.f);
		DotSize->SetHeightOverride(10.f);
		DotSize->SetContent(StationUi::MakeRounded(Tree, StationUi::ProvaAccent, 5.f, FMargin(0.f)));

		UHorizontalBox* Cell = Tree.ConstructWidget<UHorizontalBox>();
		if (UHorizontalBoxSlot* DotSlot = Cell->AddChildToHorizontalBox(DotSize))
		{
			DotSlot->SetVerticalAlignment(VAlign_Top);
			DotSlot->SetPadding(FMargin(0.f, 6.f, 14.f, 0.f));
		}
		UTextBlock* Text = MakeText(Tree, Rule, StationUi::FontMedium, 15.f, StationUi::InkBody);
		Text->SetAutoWrapText(true);
		if (UHorizontalBoxSlot* TextSlot = Cell->AddChildToHorizontalBox(Text))
		{
			TextSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		}

		if (UHorizontalBoxSlot* CellSlot = Row.AddChildToHorizontalBox(Cell))
		{
			CellSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
			CellSlot->SetPadding(FMargin(SpaceBefore, 0.f, 0.f, 0.f));
		}
	}
}

TSharedRef<SWidget> UStationBriefWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UOverlay* Screen = WidgetTree->ConstructWidget<UOverlay>();
		WidgetTree->RootWidget = Screen;
		const auto Place = [Screen](UWidget* Widget, EHorizontalAlignment Horizontal, EVerticalAlignment Vertical, const FMargin& Padding)
		{
			if (UOverlaySlot* Slot = Screen->AddChildToOverlay(Widget))
			{
				Slot->SetHorizontalAlignment(Horizontal);
				Slot->SetVerticalAlignment(Vertical);
				Slot->SetPadding(Padding);
			}
		};

		FullScrim = WidgetTree->ConstructWidget<UBorder>();
		FullScrim->SetBrushColor(StationUi::Backdrop);
		Place(FullScrim, HAlign_Fill, VAlign_Fill, FMargin(0.f));
		LeftScrim = StationUi::MakeScrim(*WidgetTree);
		Place(LeftScrim, HAlign_Fill, VAlign_Fill, FMargin(0.f));

		// "Escolher outra estação" leads to the menu until the catalog exists (#459).
		MenuButton = StationUi::AddButton(*WidgetTree, *Screen, LOCTEXT("ChooseAnotherStation", "‹ Escolher outra estação"));
		MenuButton->OnClicked.AddDynamic(this, &UStationBriefWidget::HandleBackToMenu);
		StationUi::MakeGhost(*MenuButton);
		if (UOverlaySlot* MenuSlot = Cast<UOverlaySlot>(MenuButton->Slot))
		{
			MenuSlot->SetHorizontalAlignment(HAlign_Left);
			MenuSlot->SetVerticalAlignment(VAlign_Top);
			MenuSlot->SetPadding(FMargin(96.f, 64.f, 0.f, 0.f));
		}

		UHorizontalBox* Columns = WidgetTree->ConstructWidget<UHorizontalBox>();
		Place(Columns, HAlign_Fill, VAlign_Fill, BriefPadding);
		BriefColumn = WidgetTree->ConstructWidget<UVerticalBox>();
		if (UHorizontalBoxSlot* ColumnSlot = Columns->AddChildToHorizontalBox(BriefColumn))
		{
			ColumnSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		}

		UHorizontalBox* Eyebrow = WidgetTree->ConstructWidget<UHorizontalBox>();
		BriefColumn->AddChild(Eyebrow);
		for (UWidget* Mark : {TrainingMark = StationUi::MakeModeMark(*WidgetTree, StationUi::TreinoAccent),
				 ExamMark = StationUi::MakeModeMark(*WidgetTree, StationUi::ProvaAccent)})
		{
			if (UHorizontalBoxSlot* MarkSlot = Eyebrow->AddChildToHorizontalBox(Mark))
			{
				MarkSlot->SetVerticalAlignment(VAlign_Center);
				MarkSlot->SetPadding(FMargin(0.f, 0.f, 12.f, 0.f));
			}
		}
		HeadingText = MakeText(*WidgetTree, LOCTEXT("BriefHeading", "Antes de entrar na estação"), StationUi::FontBold, 13.f,
			StationUi::TreinoAccent, 120);
		HeadingText->SetTextTransformPolicy(ETextTransformPolicy::ToUpper);
		Eyebrow->AddChild(HeadingText);

		StatusText = AddLine(*WidgetTree, *BriefColumn, LOCTEXT("BriefLoading", "Carregando cenário e tarefas..."),
			StationUi::FontMedium, 18.f, StationUi::InkBody, 26.f);
		ErrorText = AddLine(*WidgetTree, *BriefColumn, FText::GetEmpty(), StationUi::FontMedium, 18.f, StationUi::Caution, 26.f);
		RetryButton = StationUi::AddButton(*WidgetTree, *BriefColumn, LOCTEXT("Retry", "Tentar novamente"));
		RetryButton->OnClicked.AddDynamic(this, &UStationBriefWidget::HandleRetry);
		StationUi::MakePrimary(*RetryButton);

		// Scrolls, so the way in and the note stay in view however long the case runs.
		UScrollBox* Scroll = WidgetTree->ConstructWidget<UScrollBox>();
		if (UVerticalBoxSlot* ScrollSlot = BriefColumn->AddChildToVerticalBox(Scroll))
		{
			ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
			ScrollSlot->SetPadding(FMargin(0.f, 26.f, 0.f, 0.f));
		}
		BriefBox = WidgetTree->ConstructWidget<UVerticalBox>();
		Scroll->AddChild(BriefBox);
		TitleText = AddLine(*WidgetTree, *BriefBox, FText::GetEmpty(), StationUi::FontBold, 48.f, StationUi::InkTitle, 0.f, -60);
		TitleText->SetLineHeightPercentage(BriefTitleLineHeight);
		AddLine(*WidgetTree, *BriefBox, LOCTEXT("ScenarioHeading", "Cenário de atuação"), StationUi::FontBold, 18.f, StationUi::InkTitle, 26.f);
		ScenarioText = AddLine(*WidgetTree, *BriefBox, FText::GetEmpty(), StationUi::FontMedium, 18.f, StationUi::InkBody, 10.f);
		AddLine(*WidgetTree, *BriefBox, LOCTEXT("TasksHeading", "Tarefas"), StationUi::FontBold, 18.f, StationUi::InkTitle, 26.f);
		TaskList = WidgetTree->ConstructWidget<UVerticalBox>();
		BriefBox->AddChild(TaskList);

		// A simulated exam's rules and way in, instead of the brief it keeps for its start (#425).
		USizeBox* ExamSize = WidgetTree->ConstructWidget<USizeBox>();
		ExamSize->SetWidthOverride(ExamColumnWidth);
		if (UVerticalBoxSlot* ExamSlot = BriefColumn->AddChildToVerticalBox(ExamSize))
		{
			ExamSlot->SetHorizontalAlignment(HAlign_Left);
		}
		ExamBox = WidgetTree->ConstructWidget<UVerticalBox>();
		ExamSize->SetContent(ExamBox);
		AddLine(*WidgetTree, *ExamBox, LOCTEXT("SimulatedExamTitle", "Como no dia da prova"), StationUi::FontBold, 56.f,
			StationUi::InkTitle, 0.f, -60);
		ExamLeadText = AddLine(*WidgetTree, *ExamBox, LOCTEXT("SimulatedExamTimerNote",
			"O cenário e as tarefas aparecem quando a prova começar, com o tempo já correndo."),
			StationUi::FontMedium, 18.f, StationUi::InkBody, 20.f);
		ExamRules = WidgetTree->ConstructWidget<UVerticalBox>();
		if (UVerticalBoxSlot* RulesSlot = ExamBox->AddChildToVerticalBox(ExamRules))
		{
			RulesSlot->SetPadding(FMargin(0.f, 28.f, 0.f, 0.f));
		}
		UHorizontalBox* RulesAbove = WidgetTree->ConstructWidget<UHorizontalBox>();
		ExamRules->AddChild(RulesAbove);
		AddExamRule(*WidgetTree, *RulesAbove, LOCTEXT("ExamRuleVoice", "Só por voz e sem ajuda."), 0.f);
		AddExamRule(*WidgetTree, *RulesAbove, LOCTEXT("ExamRuleMinutes", "10 minutos, incluindo a leitura do cenário."), 32.f);
		UHorizontalBox* RulesBelow = WidgetTree->ConstructWidget<UHorizontalBox>();
		if (UVerticalBoxSlot* BelowSlot = ExamRules->AddChildToVerticalBox(RulesBelow))
		{
			BelowSlot->SetPadding(FMargin(0.f, 18.f, 0.f, 0.f));
		}
		AddExamRule(*WidgetTree, *RulesBelow, LOCTEXT("ExamRuleClock", "O relógio fica na mesa. Não há contagem na tela."), 0.f);
		AddExamRule(*WidgetTree, *RulesBelow, LOCTEXT("ExamRuleSignals", "Um sinal sonoro marca o início e o fim."), 32.f);

		SimulatedExamNote = AddLine(*WidgetTree, *ExamBox, FText::GetEmpty(), StationUi::FontMedium, 15.f, StationUi::Caution, 28.f);
		UHorizontalBox* ExamActions = WidgetTree->ConstructWidget<UHorizontalBox>();
		if (UVerticalBoxSlot* ActionsSlot = ExamBox->AddChildToVerticalBox(ExamActions))
		{
			ActionsSlot->SetPadding(FMargin(0.f, 28.f, 0.f, 0.f));
		}
		// A simulated exam's one way in, by voice (#421).
		SimulatedExamButton = StationUi::AddButton(*WidgetTree, *ExamActions, LOCTEXT("StartSimulatedExam", "Iniciar prova simulada"));
		SimulatedExamButton->OnClicked.AddDynamic(this, &UStationBriefWidget::HandleSimulatedExam);
		StationUi::MakeExam(*SimulatedExamButton);
		TrainingInsteadButton = StationUi::AddButton(*WidgetTree, *ExamActions, LOCTEXT("TrainingInstead", "Fazer um treino"));
		TrainingInsteadButton->OnClicked.AddDynamic(this, &UStationBriefWidget::HandleTrainingInstead);
		StationUi::MakeSecondary(*TrainingInsteadButton);
		if (UHorizontalBoxSlot* InsteadSlot = Cast<UHorizontalBoxSlot>(TrainingInsteadButton->Slot))
		{
			InsteadSlot->SetPadding(FMargin(20.f, 0.f, 0.f, 0.f));
		}
		SimulatedExamFine = AddLine(*WidgetTree, *ExamBox, LOCTEXT("MenuExamNotOfficial", "Não é nota oficial do Revalida."),
			StationUi::FontRegular, 13.f, StationUi::Muted, 28.f);

		// A running simulated exam shows this brief over the room (#425).
		CloseButton = StationUi::AddButton(*WidgetTree, *BriefColumn, LOCTEXT("CloseBrief", "Voltar ao consultório"), 18.f);
		CloseButton->OnClicked.AddDynamic(this, &UStationBriefWidget::HandleCloseBrief);
		StationUi::MakePrimary(*CloseButton);
		FictionalNote = AddLine(*WidgetTree, *BriefColumn, LOCTEXT("FictionalNote",
			"Caso clínico fictício, criado para treino educacional. Não corresponde a um paciente real."),
			StationUi::FontRegular, 13.f, StationUi::Muted, 18.f);

		USizeBox* PanelSize = WidgetTree->ConstructWidget<USizeBox>();
		PanelSize->SetWidthOverride(TrainingsPanelWidth);
		TrainingsPanel = PanelSize;
		if (UHorizontalBoxSlot* PanelSlot = Columns->AddChildToHorizontalBox(PanelSize))
		{
			PanelSlot->SetVerticalAlignment(VAlign_Top);
			PanelSlot->SetPadding(FMargin(72.f, 0.f, 0.f, 0.f));
		}
		UBorder* Panel = StationUi::MakePanel(*WidgetTree, FMargin(32.f));
		PanelSize->SetContent(Panel);
		UVerticalBox* Trainings = WidgetTree->ConstructWidget<UVerticalBox>();
		Panel->SetContent(Trainings);
		AddLine(*WidgetTree, *Trainings, LOCTEXT("TrainingsTitle", "Como você quer treinar?"), StationUi::FontBold, 28.f,
			StationUi::InkTitle, 0.f, -15);
		VoiceButton = AddTrainingOption(*WidgetTree, *Trainings, LOCTEXT("VoiceTraining", "Por voz"));
		VoiceButton->OnClicked.AddDynamic(this, &UStationBriefWidget::HandleVoiceTraining);
		TextButton = AddTrainingOption(*WidgetTree, *Trainings, LOCTEXT("TextTraining", "Por texto"));
		TextButton->OnClicked.AddDynamic(this, &UStationBriefWidget::HandleTextTraining);
		VoiceBlockedNote = AddLine(*WidgetTree, *Trainings, LOCTEXT("VoiceBlocked",
			"O microfone está bloqueado. Para treinar por voz, libere o acesso nos ajustes de privacidade do sistema e abra o app de novo."),
			StationUi::FontMedium, 15.f, StationUi::Caution, 18.f);
		VoiceNote = AddLine(*WidgetTree, *Trainings, LOCTEXT("VoiceNote",
			"No treino por voz, a Deepgram transcreve o seu áudio e a Cartesia gera a voz do paciente."),
			StationUi::FontRegular, 13.f, StationUi::Muted, 18.f);
		UBorder* Rule = WidgetTree->ConstructWidget<UBorder>();
		Rule->SetBrushColor(StationUi::PanelEdge);
		Rule->SetPadding(FMargin(0.f, 0.5f));
		if (UVerticalBoxSlot* RuleSlot = Trainings->AddChildToVerticalBox(Rule))
		{
			RuleSlot->SetPadding(FMargin(0.f, 18.f, 0.f, 0.f));
		}
		TimerNote = AddLine(*WidgetTree, *Trainings, LOCTEXT("TimerNote",
			"O tempo da estação começa a contar quando você entrar."), StationUi::FontMedium, 15.f, StationUi::InkBody, 18.f);
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
	const bool bExam = Flow->GetSessionMode() == EStationSessionMode::SimulatedExam;
	const bool bRunning = Flow->GetStep() == EStationRunStep::Running;
	// Before it starts, a simulated exam shows its rules over the room, not its brief.
	const bool bExamStart = bExam && !bRunning && Station != nullptr;

	StationUi::SetShown(FullScrim, !bExamStart);
	LeftScrim->SetVisibility(bExamStart ? ESlateVisibility::HitTestInvisible : ESlateVisibility::Collapsed);
	if (UHorizontalBoxSlot* ColumnSlot = Cast<UHorizontalBoxSlot>(BriefColumn->Slot))
	{
		ColumnSlot->SetVerticalAlignment(bExamStart ? VAlign_Bottom : VAlign_Fill);
	}
	StationUi::SetShown(TrainingMark, !bExam);
	StationUi::SetShown(ExamMark, bExam);
	HeadingText->SetColorAndOpacity(FSlateColor(bExam ? StationUi::ProvaAccent : StationUi::TreinoAccent));

	StationUi::SetShown(StatusText, Flow->IsStationLoading() || bStarting);
	StatusText->SetText(bStarting
		? LOCTEXT("Starting", "Iniciando a estação...")
		: LOCTEXT("BriefLoading", "Carregando cenário e tarefas..."));

	StationUi::SetShown(ErrorText, !Flow->GetErrorText().IsEmpty());
	ErrorText->SetText(Flow->GetErrorText());
	StationUi::SetShown(RetryButton, !Station && !Flow->IsStationLoading());

	// A simulated exam's scenario and tasks show only once its time runs (#425, #318 T3).
	const bool bBriefShown = Station != nullptr && Flow->CanReadBrief();
	StationUi::SetShown(BriefBox, bBriefShown);
	StationUi::SetShown(FictionalNote, bBriefShown);
	StationUi::SetShown(ExamBox, bExamStart);
	StationUi::SetShown(TrainingsPanel, Station != nullptr && !bExam);
	StationUi::SetShown(CloseButton, Station != nullptr && bRunning);
	if (!Station)
	{
		return;
	}

	HeadingText->SetText(bExam && bRunning ? LOCTEXT("SimulatedExamRunningHeading", "Prova simulada · Cenário e tarefas")
		: bExam ? LOCTEXT("SimulatedExamHeading", "Prova simulada · Antes de entrar na estação")
		: LOCTEXT("TrainingHeading", "Treino · Antes de entrar na estação"));
	StationUi::SetShown(MenuButton, !bRunning);
	StationUi::SetShown(TimerNote, !bRunning);
	TitleText->SetText(FText::FromString(Station->DisplayTitle));
	ScenarioText->SetText(FText::FromString(Station->Scenario));
	TaskList->ClearChildren();
	for (const FString& Task : Station->Tasks)
	{
		AddLine(*WidgetTree, *TaskList, FText::FromString(TEXT("•  ") + Task), StationUi::FontRegular, 17.f, StationUi::InkBody, 8.f);
	}

	const auto SetAvailable = [](UButton& Button, bool bAvailable)
	{
		Button.SetIsEnabled(bAvailable);
		Button.SetRenderOpacity(bAvailable ? 1.f : UnavailableOpacity);
	};
	SetAvailable(*TextButton, Flow->CanEnter(EStationTrainingMode::Text));
	SetAvailable(*VoiceButton, Flow->CanEnter(EStationTrainingMode::Voice));
	const bool bVoiceOffered = IsVoiceTrainingAvailable(*Station);
	StationUi::SetShown(VoiceButton, bVoiceOffered);
	StationUi::SetShown(VoiceNote, !bExam && bVoiceOffered);
	StationUi::SetShown(VoiceBlockedNote, !bExam && bVoiceOffered
		&& Flow->GetMicrophonePermission() == EStationMicPermission::Denied);

	// The simulated exam stays in view when it cannot start, so the learner reads why.
	const FText ExamUnavailable = SimulatedExamUnavailableText(*Station, Flow->GetMicrophonePermission());
	StationUi::SetShown(SimulatedExamButton, bExamStart);
	SimulatedExamButton->SetIsEnabled(Flow->CanEnterSimulatedExam());
	StationUi::SetShown(SimulatedExamNote, bExamStart && !ExamUnavailable.IsEmpty());
	SimulatedExamNote->SetText(ExamUnavailable);
	StationUi::SetShown(TrainingInsteadButton, bExamStart && !ExamUnavailable.IsEmpty());
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

void UStationBriefWidget::HandleSimulatedExam()
{
	if (Flow)
	{
		Flow->EnterSimulatedExam();
	}
}

void UStationBriefWidget::HandleCloseBrief()
{
	if (Flow)
	{
		Flow->CloseBrief();
	}
}

void UStationBriefWidget::HandleTrainingInstead()
{
	if (Flow)
	{
		Flow->BackToMenu();
		Flow->ChooseMode(EStationSessionMode::Training);
	}
}

void UStationBriefWidget::HandleBackToMenu()
{
	if (Flow)
	{
		Flow->BackToMenu();
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

		BuildBriefReader(*Root);
		BuildConversation(*Root);
		BuildSideActions(*Root);
		BuildTimerPanel(*Root);
		BuildDocumentViewer(*Root);
		// Over the document's dim: the other requests stay in reach beside the sheet.
		BuildExamDrawer(*Root);
	}
	return Super::RebuildWidget();
}

void UStationHudWidget::BuildTimerPanel(UOverlay& Root)
{
	UBorder* Panel = StationUi::MakeRounded(*WidgetTree, StationUi::HudPanel, 12.f, FMargin(26.f, 14.f, 18.f, 14.f),
		StationUi::PanelEdge, 1.f);
	TimerPanel = Panel;
	if (UOverlaySlot* Slot = Root.AddChildToOverlay(Panel))
	{
		Slot->SetHorizontalAlignment(HAlign_Center);
		Slot->SetVerticalAlignment(VAlign_Top);
		Slot->SetPadding(FMargin(0.f, HudEdge, 0.f, 0.f));
	}
	UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>();
	Panel->SetContent(Row);

	USizeBox* TimeSize = WidgetTree->ConstructWidget<USizeBox>();
	TimeSize->SetWidthOverride(TimerColumnWidth);
	TimerColumn = TimeSize;
	if (UHorizontalBoxSlot* TimeSlot = Row->AddChildToHorizontalBox(TimeSize))
	{
		TimeSlot->SetVerticalAlignment(VAlign_Center);
	}
	UVerticalBox* Time = WidgetTree->ConstructWidget<UVerticalBox>();
	TimeSize->SetContent(Time);
	TimerLabelText = MakeText(*WidgetTree, LOCTEXT("TimeLeft", "Tempo restante"), StationUi::FontBold, 11.f, StationUi::Muted, 120);
	TimerLabelText->SetTextTransformPolicy(ETextTransformPolicy::ToUpper);
	WrapAt(*TimerLabelText, TimerLabelWrapWidth);
	Time->AddChild(TimerLabelText);
	TimerText = MakeText(*WidgetTree, FormatStationTimer(FTimespan::Zero()), StationUi::FontExtraBold, 40.f, StationUi::InkTitle, 20);
	if (UVerticalBoxSlot* TimerSlot = Time->AddChildToVerticalBox(TimerText))
	{
		TimerSlot->SetPadding(FMargin(0.f, 2.f, 0.f, 0.f));
	}

	USizeBox* DividerSize = WidgetTree->ConstructWidget<USizeBox>();
	DividerSize->SetWidthOverride(1.f);
	TimerDivider = DividerSize;
	UBorder* Divider = WidgetTree->ConstructWidget<UBorder>();
	Divider->SetBrushColor(StationUi::PanelEdge);
	DividerSize->SetContent(Divider);
	if (UHorizontalBoxSlot* DividerSlot = Row->AddChildToHorizontalBox(DividerSize))
	{
		DividerSlot->SetPadding(FMargin(24.f, 0.f, 24.f, 0.f));
	}

	USizeBox* StatusSize = WidgetTree->ConstructWidget<USizeBox>();
	StatusSize->SetMinDesiredWidth(VoiceStatusMinWidth);
	if (UHorizontalBoxSlot* StatusSlot = Row->AddChildToHorizontalBox(StatusSize))
	{
		StatusSlot->SetVerticalAlignment(VAlign_Center);
	}
	UVerticalBox* Status = WidgetTree->ConstructWidget<UVerticalBox>();
	StatusSize->SetContent(Status);

	UHorizontalBox* Voice = WidgetTree->ConstructWidget<UHorizontalBox>();
	VoiceRow = Voice;
	Status->AddChild(Voice);
	USizeBox* DotSize = WidgetTree->ConstructWidget<USizeBox>();
	DotSize->SetWidthOverride(10.f);
	DotSize->SetHeightOverride(10.f);
	VoiceDot = StationUi::MakeRounded(*WidgetTree, FLinearColor::White, 5.f, FMargin(0.f));
	DotSize->SetContent(VoiceDot);
	if (UHorizontalBoxSlot* DotSlot = Voice->AddChildToHorizontalBox(DotSize))
	{
		DotSlot->SetVerticalAlignment(VAlign_Top);
		DotSlot->SetPadding(FMargin(0.f, 5.f, 8.f, 0.f));
	}
	VoiceStatusText = MakeText(*WidgetTree, FText::GetEmpty(), StationUi::FontSemiBold, 14.f, StationUi::Ink);
	WrapAt(*VoiceStatusText, VoiceStatusWrapWidth);
	Voice->AddChild(VoiceStatusText);

	FallbackText = MakeText(*WidgetTree, LOCTEXT("VoiceFallback", "Voz indisponível — usando texto."), StationUi::FontSemiBold, 14.f,
		StationUi::Caution);
	WrapAt(*FallbackText, VoiceStatusWrapWidth);
	Status->AddChild(FallbackText);

	ModeText = MakeText(*WidgetTree, FText::GetEmpty(), StationUi::FontRegular, 13.f, StationUi::Muted);
	if (UVerticalBoxSlot* ModeSlot = Status->AddChildToVerticalBox(ModeText))
	{
		ModeSlot->SetPadding(FMargin(0.f, 6.f, 0.f, 0.f));
	}

	FinishButton = StationUi::AddButton(*WidgetTree, *Row, LOCTEXT("FinishStation", "Finalizar estação"));
	FinishButton->OnClicked.AddDynamic(this, &UStationHudWidget::HandleFinish);
	StationUi::MakeDanger(*FinishButton);
	// The mockups' smaller button, 44 px tall, to sit in the panel.
	if (UTextBlock* Label = Cast<UTextBlock>(FinishButton->GetChildAt(0)))
	{
		Label->SetFont(StationUi::MockupFont(StationUi::FontBold, 14.f));
		Label->SetMargin(FMargin(18.f, 12.5f));
	}
	if (UHorizontalBoxSlot* FinishSlot = Cast<UHorizontalBoxSlot>(FinishButton->Slot))
	{
		FinishSlot->SetPadding(FMargin(24.f, 0.f, 0.f, 0.f));
		FinishSlot->SetVerticalAlignment(VAlign_Center);
	}
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
		Slot->SetPadding(FMargin(HudEdge, HudEdge, 0.f, HudEdge));
	}

	UBorder* Panel = StationUi::MakeRounded(*WidgetTree, StationUi::HudPanel, 12.f, FMargin(0.f), StationUi::PanelEdge, 1.f);
	Size->SetContent(Panel);
	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>();
	Panel->SetContent(Column);
	if (UVerticalBoxSlot* TitleSlot = Column->AddChildToVerticalBox(
			MakeText(*WidgetTree, LOCTEXT("ConversationTitle", "Conversa"), StationUi::FontBold, 18.f, StationUi::InkTitle)))
	{
		TitleSlot->SetPadding(FMargin(SidePanelPadding, 20.f));
	}
	AddRule(*WidgetTree, *Column, StationUi::PanelEdge, 0.f);

	// The newest line sits above the footer, and a short conversation stays down there with it.
	TranscriptScroll = WidgetTree->ConstructWidget<UScrollBox>();
	TranscriptScroll->SetScrollBarVisibility(ESlateVisibility::Collapsed);
	if (UVerticalBoxSlot* ScrollSlot = Column->AddChildToVerticalBox(TranscriptScroll))
	{
		ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		ScrollSlot->SetVerticalAlignment(VAlign_Bottom);
		ScrollSlot->SetPadding(FMargin(SidePanelPadding, 20.f, SidePanelPadding, 0.f));
	}
	TranscriptBox = WidgetTree->ConstructWidget<UVerticalBox>();
	TranscriptScroll->AddChild(TranscriptBox);

	UHorizontalBox* Talking = WidgetTree->ConstructWidget<UHorizontalBox>();
	PatientTalkingRow = Talking;
	if (UVerticalBoxSlot* TalkingSlot = Column->AddChildToVerticalBox(Talking))
	{
		TalkingSlot->SetPadding(FMargin(SidePanelPadding, 12.f, SidePanelPadding, 0.f));
	}
	if (UHorizontalBoxSlot* LabelSlot = Talking->AddChildToHorizontalBox(
			MakeText(*WidgetTree, LOCTEXT("PatientTalking", "Paciente falando"), StationUi::FontRegular, 13.f, StationUi::Muted)))
	{
		LabelSlot->SetVerticalAlignment(VAlign_Center);
		LabelSlot->SetPadding(FMargin(0.f, 0.f, 7.f, 0.f));
	}
	for (const float Height : {10.f, 18.f, 12.f, 20.f})
	{
		USizeBox* Bar = WidgetTree->ConstructWidget<USizeBox>();
		Bar->SetWidthOverride(3.f);
		Bar->SetHeightOverride(Height);
		Bar->SetContent(StationUi::MakeRounded(*WidgetTree, StationUi::Muted, 1.5f, FMargin(0.f)));
		if (UHorizontalBoxSlot* BarSlot = Talking->AddChildToHorizontalBox(Bar))
		{
			BarSlot->SetVerticalAlignment(VAlign_Center);
			BarSlot->SetPadding(FMargin(3.f, 0.f, 0.f, 0.f));
		}
	}

	TurnErrorText = StationUi::AddText(*WidgetTree, *Column, FText::GetEmpty(), 15, false, StationUi::Caution, 0.f);
	if (UVerticalBoxSlot* ErrorSlot = Cast<UVerticalBoxSlot>(TurnErrorText->Slot))
	{
		ErrorSlot->SetPadding(FMargin(SidePanelPadding, 8.f, SidePanelPadding, 0.f));
	}

	AddRule(*WidgetTree, *Column, StationUi::PanelEdge, 14.f);
	UVerticalBox* Footer = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UVerticalBoxSlot* FooterSlot = Column->AddChildToVerticalBox(Footer))
	{
		FooterSlot->SetPadding(FMargin(SidePanelPadding, 20.f));
	}

	// Push-to-talk (#419): in a voice training the learner holds this button, or the
	// space bar, to talk to the patient; releasing it sends what was said.
	TalkButton = WidgetTree->ConstructWidget<UButton>();
	TalkButton->OnPressed.AddDynamic(this, &UStationHudWidget::HandlePressTalk);
	TalkButton->OnReleased.AddDynamic(this, &UStationHudWidget::HandleReleaseTalk);
	UHorizontalBox* TalkContent = WidgetTree->ConstructWidget<UHorizontalBox>();
	if (UButtonSlot* ContentSlot = Cast<UButtonSlot>(TalkButton->AddChild(TalkContent)))
	{
		ContentSlot->SetPadding(FMargin(0.f));
	}
	TalkIcon = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UHorizontalBoxSlot* IconSlot = TalkContent->AddChildToHorizontalBox(TalkIcon))
	{
		IconSlot->SetVerticalAlignment(VAlign_Center);
		IconSlot->SetPadding(FMargin(0.f, 0.f, 12.f, 0.f));
	}
	TalkText = WidgetTree->ConstructWidget<UTextBlock>();
	TalkText->SetFont(StationUi::MockupFont(StationUi::FontBold, 16.f));
	if (UHorizontalBoxSlot* TextSlot = TalkContent->AddChildToHorizontalBox(TalkText))
	{
		TextSlot->SetVerticalAlignment(VAlign_Center);
	}
	if (UVerticalBoxSlot* TalkSlot = Footer->AddChildToVerticalBox(TalkButton))
	{
		TalkSlot->SetPadding(FMargin(0.f, 0.f, 0.f, 12.f));
	}

	UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>();
	TurnRow = Row;
	Footer->AddChild(Row);

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
	// A simulated exam is voice only (#422).
	StationUi::SetShown(TurnRow, Flow->AllowsTypedInput());
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
		MessageSlot->SetPadding(FMargin(bLearner ? BubbleIndent : 0.f, TranscriptBox->GetChildrenCount() > 1 ? 14.f : 0.f,
			bLearner ? 0.f : BubbleIndent, 0.f));
		MessageSlot->SetHorizontalAlignment(bLearner ? HAlign_Right : HAlign_Left);
	}
	UTextBlock* Who = MakeText(*WidgetTree, bLearner ? LOCTEXT("LearnerSpeaker", "Você") : LOCTEXT("PatientSpeaker", "Paciente"),
		StationUi::FontRegular, 13.f, StationUi::Muted);
	if (UVerticalBoxSlot* WhoSlot = Message->AddChildToVerticalBox(Who))
	{
		WhoSlot->SetHorizontalAlignment(bLearner ? HAlign_Right : HAlign_Left);
	}
	UBorder* Bubble = StationUi::MakeRounded(*WidgetTree, bLearner ? LearnerBubbleFill : PatientBubbleFill, 12.f,
		FMargin(BubblePadding, 12.f));
	// The corner nearest its speaker stays tight.
	FSlateBrush Shape = Bubble->Background;
	Shape.OutlineSettings.CornerRadii = bLearner ? FVector4(12.f, 12.f, 4.f, 12.f) : FVector4(12.f, 12.f, 12.f, 4.f);
	Bubble->SetBrush(Shape);
	if (UVerticalBoxSlot* BubbleSlot = Message->AddChildToVerticalBox(Bubble))
	{
		BubbleSlot->SetPadding(FMargin(0.f, 4.f, 0.f, 0.f));
		BubbleSlot->SetHorizontalAlignment(bLearner ? HAlign_Right : HAlign_Left);
	}
	UTextBlock* Body = MakeText(*WidgetTree, FText::FromString(Text), StationUi::FontRegular, 15.f,
		bInProgress ? StationUi::Muted : StationUi::Ink);
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

void UStationHudWidget::BuildSideActions(UOverlay& Root)
{
	UVerticalBox* Actions = WidgetTree->ConstructWidget<UVerticalBox>();
	SideActions = Actions;
	if (UOverlaySlot* Slot = Root.AddChildToOverlay(Actions))
	{
		Slot->SetHorizontalAlignment(HAlign_Right);
		Slot->SetVerticalAlignment(VAlign_Top);
		Slot->SetPadding(FMargin(0.f, HudEdge, HudEdge, 0.f));
	}

	// An outlined button on a panel's ground, so it reads over the scene.
	const auto AddAction = [this, Actions](const FText& Label, float SpaceAbove)
	{
		UBorder* Ground = StationUi::MakeRounded(*WidgetTree, StationUi::Panel, 8.f, FMargin(0.f));
		if (UVerticalBoxSlot* GroundSlot = Actions->AddChildToVerticalBox(Ground))
		{
			GroundSlot->SetHorizontalAlignment(HAlign_Right);
			GroundSlot->SetPadding(FMargin(0.f, SpaceAbove, 0.f, 0.f));
		}
		UButton* Button = StationUi::AddButton(*WidgetTree, *Ground, Label);
		StationUi::MakeSecondary(*Button);
		// The mockups' 48 px, a little shorter than the kit's button.
		if (UTextBlock* Text = Cast<UTextBlock>(Button->GetChildAt(0)))
		{
			Text->SetMargin(FMargin(24.f, 13.f));
		}
		return Button;
	};
	BriefButton = AddAction(LOCTEXT("OpenBrief", "Cenário e tarefas"), 0.f);
	BriefButton->OnClicked.AddDynamic(this, &UStationHudWidget::HandleOpenBrief);
	ExamTab = AddAction(LOCTEXT("ExamsTab", "Exames"), 12.f);
	ExamTab->OnClicked.AddDynamic(this, &UStationHudWidget::HandleOpenExams);
	ExamTabText = Cast<UTextBlock>(ExamTab->GetChildAt(0));
}

void UStationHudWidget::BuildBriefReader(UOverlay& Root)
{
	// A training's brief over the scene, under everything else on the HUD: the clock stays
	// in view, and the learner can go on talking to the patient while reading it (#461).
	UBorder* Screen = WidgetTree->ConstructWidget<UBorder>();
	Screen->SetBrushColor(StationUi::Backdrop);
	Screen->SetHorizontalAlignment(HAlign_Left);
	Screen->SetPadding(FMargin(HudEdge + SidePanelWidth + HudEdge, 160.f, HudEdge, HudEdge));
	BriefReader = Screen;
	StationUi::SetShown(BriefReader, false);
	if (UOverlaySlot* Slot = Root.AddChildToOverlay(Screen))
	{
		Slot->SetHorizontalAlignment(HAlign_Fill);
		Slot->SetVerticalAlignment(VAlign_Fill);
	}
	USizeBox* Size = WidgetTree->ConstructWidget<USizeBox>();
	Size->SetWidthOverride(BriefReaderWidth);
	Screen->SetContent(Size);
	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>();
	Size->SetContent(Column);

	UHorizontalBox* Eyebrow = WidgetTree->ConstructWidget<UHorizontalBox>();
	Column->AddChild(Eyebrow);
	if (UHorizontalBoxSlot* MarkSlot = Eyebrow->AddChildToHorizontalBox(StationUi::MakeModeMark(*WidgetTree, StationUi::TreinoAccent)))
	{
		MarkSlot->SetVerticalAlignment(VAlign_Center);
		MarkSlot->SetPadding(FMargin(0.f, 0.f, 12.f, 0.f));
	}
	UTextBlock* Heading = MakeText(*WidgetTree, LOCTEXT("TrainingRunningHeading", "Treino · Cenário e tarefas"), StationUi::FontBold, 13.f,
		StationUi::TreinoAccent, 120);
	Heading->SetTextTransformPolicy(ETextTransformPolicy::ToUpper);
	Eyebrow->AddChild(Heading);

	UScrollBox* Scroll = WidgetTree->ConstructWidget<UScrollBox>();
	if (UVerticalBoxSlot* ScrollSlot = Column->AddChildToVerticalBox(Scroll))
	{
		ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		ScrollSlot->SetPadding(FMargin(0.f, 26.f, 0.f, 0.f));
	}
	UVerticalBox* Box = WidgetTree->ConstructWidget<UVerticalBox>();
	Scroll->AddChild(Box);
	BriefTitleText = AddLine(*WidgetTree, *Box, FText::GetEmpty(), StationUi::FontBold, 32.f, StationUi::InkTitle, 0.f, -30);
	AddLine(*WidgetTree, *Box, LOCTEXT("ScenarioHeading", "Cenário de atuação"), StationUi::FontBold, 18.f, StationUi::InkTitle, 26.f);
	BriefScenarioText = AddLine(*WidgetTree, *Box, FText::GetEmpty(), StationUi::FontMedium, 18.f, StationUi::InkBody, 10.f);
	AddLine(*WidgetTree, *Box, LOCTEXT("TasksHeading", "Tarefas"), StationUi::FontBold, 18.f, StationUi::InkTitle, 26.f);
	BriefTaskList = WidgetTree->ConstructWidget<UVerticalBox>();
	Box->AddChild(BriefTaskList);

	UButton* Close = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("CloseBrief", "Voltar ao consultório"), 18.f);
	Close->OnClicked.AddDynamic(this, &UStationHudWidget::HandleCloseBriefReader);
	StationUi::MakePrimary(*Close);
	if (UVerticalBoxSlot* CloseSlot = Cast<UVerticalBoxSlot>(Close->Slot))
	{
		CloseSlot->SetHorizontalAlignment(HAlign_Left);
	}
	AddLine(*WidgetTree, *Column, LOCTEXT("FictionalNote",
		"Caso clínico fictício, criado para treino educacional. Não corresponde a um paciente real."),
		StationUi::FontRegular, 13.f, StationUi::Muted, 18.f);
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
		Slot->SetPadding(FMargin(0.f, HudEdge, HudEdge, HudEdge));
	}

	UBorder* Panel = StationUi::MakeRounded(*WidgetTree, StationUi::HudPanel, 12.f, FMargin(0.f), StationUi::PanelEdge, 1.f);
	Size->SetContent(Panel);
	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>();
	Panel->SetContent(Column);

	UHorizontalBox* Header = WidgetTree->ConstructWidget<UHorizontalBox>();
	if (UVerticalBoxSlot* HeaderSlot = Column->AddChildToVerticalBox(Header))
	{
		HeaderSlot->SetPadding(FMargin(SidePanelPadding, 16.f, 16.f, 16.f));
	}
	if (UHorizontalBoxSlot* TitleSlot = Header->AddChildToHorizontalBox(
			MakeText(*WidgetTree, LOCTEXT("ExamsTitle", "Exames solicitados"), StationUi::FontBold, 18.f, StationUi::InkTitle)))
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
	AddRule(*WidgetTree, *Column, StationUi::PanelEdge, 0.f);

	UScrollBox* Scroll = WidgetTree->ConstructWidget<UScrollBox>();
	Scroll->SetScrollBarVisibility(ESlateVisibility::Collapsed);
	if (UVerticalBoxSlot* ScrollSlot = Column->AddChildToVerticalBox(Scroll))
	{
		ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		ScrollSlot->SetPadding(FMargin(SidePanelPadding, 20.f, SidePanelPadding, 0.f));
	}
	ExamCardBox = WidgetTree->ConstructWidget<UVerticalBox>();
	Scroll->AddChild(ExamCardBox);

	// The footer: hold the microphone in a voice training, type in a text one.
	AddRule(*WidgetTree, *Column, StationUi::PanelEdge, 14.f);
	UVerticalBox* Footer = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UVerticalBoxSlot* FooterSlot = Column->AddChildToVerticalBox(Footer))
	{
		FooterSlot->SetPadding(FMargin(SidePanelPadding, 20.f));
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

	UVerticalBox* Icon = WidgetTree->ConstructWidget<UVerticalBox>();
	AskAloudButton->AddChild(Icon);
	AddMicrophoneIcon(*WidgetTree, *Icon, StationUi::Ink, 1.f);

	// A fixed height, so the panel never jumps as the status changes.
	USizeBox* StatusSize = WidgetTree->ConstructWidget<USizeBox>();
	StatusSize->SetHeightOverride(24.f);
	if (UVerticalBoxSlot* StatusSlot = Box->AddChildToVerticalBox(StatusSize))
	{
		StatusSlot->SetHorizontalAlignment(HAlign_Center);
		StatusSlot->SetPadding(FMargin(0.f, 6.f, 0.f, 0.f));
	}
	ExamAloudText = WidgetTree->ConstructWidget<UTextBlock>();
	ExamAloudText->SetFont(StationUi::MockupFont(StationUi::FontRegular, 13.f));
	ExamAloudText->SetJustification(ETextJustify::Center);
	StatusSize->SetContent(ExamAloudText);
	MicrophoneLook = EMicrophoneLook::Recording; // forces the first `RefreshMicrophone` to style it
	RefreshMicrophone();
}

void UStationHudWidget::BuildDocumentViewer(UOverlay& Root)
{
	// A released document, read over the dimmed scene like a printed sheet.
	UBorder* Dim = WidgetTree->ConstructWidget<UBorder>();
	Dim->SetBrushColor(DocumentDim);
	Dim->SetHorizontalAlignment(HAlign_Left);
	Dim->SetVerticalAlignment(VAlign_Fill);
	Dim->SetPadding(DocumentMargin);
	DocumentViewer = Dim;
	StationUi::SetShown(DocumentViewer, false);
	if (UOverlaySlot* Slot = Root.AddChildToOverlay(Dim))
	{
		Slot->SetHorizontalAlignment(HAlign_Fill);
		Slot->SetVerticalAlignment(VAlign_Fill);
	}

	USizeBox* Size = WidgetTree->ConstructWidget<USizeBox>();
	Size->SetWidthOverride(DocumentWidth);
	Dim->SetContent(Size);
	UBorder* Sheet = StationUi::MakeRounded(*WidgetTree, StationUi::Paper, 6.f, FMargin(0.f));
	Size->SetContent(Sheet);
	UVerticalBox* Column = WidgetTree->ConstructWidget<UVerticalBox>();
	Sheet->SetContent(Column);

	UHorizontalBox* Header = WidgetTree->ConstructWidget<UHorizontalBox>();
	if (UVerticalBoxSlot* HeaderSlot = Column->AddChildToVerticalBox(Header))
	{
		HeaderSlot->SetPadding(FMargin(DocumentSidePadding, 40.f, DocumentSidePadding, 22.f));
	}
	UVerticalBox* Titles = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UHorizontalBoxSlot* TitlesSlot = Header->AddChildToHorizontalBox(Titles))
	{
		TitlesSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	}
	DocumentCategoryText = MakeText(*WidgetTree, FText::GetEmpty(), StationUi::FontBold, 13.f, StationUi::PaperMuted, 120);
	DocumentCategoryText->SetTextTransformPolicy(ETextTransformPolicy::ToUpper);
	Titles->AddChild(DocumentCategoryText);
	DocumentTitleText = MakeText(*WidgetTree, FText::GetEmpty(), StationUi::FontBold, 34.f, StationUi::PaperInk, -20);
	DocumentTitleText->SetAutoWrapText(true);
	if (UVerticalBoxSlot* TitleSlot = Titles->AddChildToVerticalBox(DocumentTitleText))
	{
		TitleSlot->SetPadding(FMargin(0.f, 8.f, 0.f, 0.f));
	}
	UButton* Close = StationUi::MakeFlatButton(*WidgetTree, FText::FromString(TEXT("×")), 28, StationUi::PaperInk);
	Close->SetToolTipText(LOCTEXT("CloseDocument", "Fechar documento"));
	Close->OnClicked.AddDynamic(this, &UStationHudWidget::HandleCloseDocument);
	if (UHorizontalBoxSlot* CloseSlot = Header->AddChildToHorizontalBox(Close))
	{
		CloseSlot->SetVerticalAlignment(VAlign_Top);
		CloseSlot->SetPadding(FMargin(16.f, 0.f, 0.f, 0.f));
	}

	USizeBox* RuleInset = WidgetTree->ConstructWidget<USizeBox>();
	if (UVerticalBoxSlot* RuleSlot = Column->AddChildToVerticalBox(RuleInset))
	{
		RuleSlot->SetPadding(FMargin(DocumentSidePadding, 0.f));
	}
	UVerticalBox* RuleColumn = WidgetTree->ConstructWidget<UVerticalBox>();
	RuleInset->SetContent(RuleColumn);
	AddRule(*WidgetTree, *RuleColumn, StationUi::PaperEdge, 0.f);

	DocumentScroll = WidgetTree->ConstructWidget<UScrollBox>();
	if (UVerticalBoxSlot* ScrollSlot = Column->AddChildToVerticalBox(DocumentScroll))
	{
		ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	}
	DocumentBody = WidgetTree->ConstructWidget<UVerticalBox>();
	DocumentScroll->AddChild(DocumentBody);
	if (UScrollBoxSlot* BodySlot = Cast<UScrollBoxSlot>(DocumentBody->Slot))
	{
		BodySlot->SetPadding(FMargin(DocumentSidePadding, 22.f, DocumentSidePadding, 40.f));
	}
}

void UStationHudWidget::RefreshExams()
{
	const bool bAloud = Flow->ShouldRequestExamsAloud();
	StationUi::SetShown(MicrophoneBox, bAloud);
	// A simulated exam asks its exams only aloud (#422), even once the voice is lost.
	StationUi::SetShown(ExamTypedRow, !bAloud && Flow->AllowsTypedInput());
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
	// and the control the empty panel names. A simulated exam has no typed box (#422).
	const bool bAloud = Flow->ShouldRequestExamsAloud() || !Flow->AllowsTypedInput();
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
		WrapAt(*AddLine(*WidgetTree, *ExamCardBox, bAloud
			? LOCTEXT("NoExamsAloud", "Nenhum exame solicitado ainda. Segure o microfone e diga o que você solicita.")
			: LOCTEXT("NoExamsTyped", "Nenhum exame solicitado ainda. Descreva abaixo o que você solicita."),
			StationUi::FontMedium, 15.f, StationUi::Muted, 0.f), ExamListWrapWidth);
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
		WrapAt(*AddLine(*WidgetTree, *ExamCardBox, LOCTEXT("OtherDocuments", "Outros documentos liberados"),
			StationUi::FontBold, 14.f, StationUi::Muted, 12.f), ExamListWrapWidth);
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
		Text->SetFont(StationUi::Font(StationUi::FontBold, 13));
		Text->SetColorAndOpacity(FSlateColor(Ink));
		Chip->SetContent(Text);
		return Chip;
	}

	/** The status of a request, in the kit's outlined pill, on the card's own opaque ground. */
	UBorder* MakeRequestChip(UWidgetTree& Tree, const FText& Label, const FLinearColor& Ink = StationUi::InkLabel)
	{
		UBorder* Chip = StationUi::MakeChip(Tree, Label);
		Chip->SetBrush(StationUi::RoundedBrush(StationUi::PanelSolid, 16.f, StationUi::ChipEdge, 1.f));
		if (UTextBlock* Text = Cast<UTextBlock>(Chip->GetContent()))
		{
			Text->SetColorAndOpacity(FSlateColor(Ink));
		}
		return Chip;
	}

	/** A card's column, with the request and its status label in the first row. */
	UVerticalBox* AddCard(UWidgetTree& Tree, UVerticalBox& Parent, const FString& Text, UBorder* Chip,
		const FLinearColor& TitleInk = StationUi::InkTitle)
	{
		UBorder* Card = StationUi::MakeRounded(Tree, StationUi::PanelSolid, 10.f, FMargin(CardPadding, 16.f), StationUi::PanelEdge, 1.f);
		if (UVerticalBoxSlot* CardSlot = Parent.AddChildToVerticalBox(Card))
		{
			CardSlot->SetPadding(FMargin(0.f, Parent.GetChildrenCount() > 1 ? 12.f : 0.f, 0.f, 0.f));
		}
		UVerticalBox* Column = Tree.ConstructWidget<UVerticalBox>();
		Card->SetContent(Column);
		UHorizontalBox* Row = Tree.ConstructWidget<UHorizontalBox>();
		Column->AddChild(Row);
		UTextBlock* Title = MakeText(Tree, FText::FromString(Text), StationUi::FontBold, 16.f, TitleInk);
		WrapAt(*Title, CardTitleWrapWidth);
		if (UHorizontalBoxSlot* TitleSlot = Row->AddChildToHorizontalBox(Title))
		{
			TitleSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
			TitleSlot->SetVerticalAlignment(VAlign_Center);
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
	const bool bDeclined = Reply.Decision != EStationImpressoDecision::Released
		&& Reply.Decision != EStationImpressoDecision::AlreadyReleased;
	UBorder* Chip = Reply.Decision == EStationImpressoDecision::Released
		? MakeRequestChip(*WidgetTree, LOCTEXT("ExamReleased", "Liberado"))
		: Reply.Decision == EStationImpressoDecision::AlreadyReleased
		? MakeRequestChip(*WidgetTree, LOCTEXT("ExamAlreadyReleased", "Já liberado"))
		: MakeRequestChip(*WidgetTree, LOCTEXT("ExamUnavailable", "Não disponível"), StationUi::Muted);
	UVerticalBox* Column = AddCard(*WidgetTree, *ExamCardBox, Request.Text, Chip, bDeclined ? StationUi::InkBody : StationUi::InkTitle);
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
		WrapAt(*AddLine(*WidgetTree, *Column, FText::FromString(Reply.FeedbackMessage), StationUi::FontRegular, 13.f,
			StationUi::Muted, 10.f), CardWrapWidth);
	}
}

void UStationHudWidget::AddPendingExamCard(const FString& Text)
{
	AddCard(*WidgetTree, *ExamCardBox, Text, MakeRequestChip(*WidgetTree, LOCTEXT("ExamPending", "Solicitando..."), StationUi::Muted),
		StationUi::InkBody);
}

void UStationHudWidget::AddDocumentLink(UVerticalBox& Parent, const FStationImpresso& Impresso, const FText& Label)
{
	UButton* Open = StationUi::MakeFlatButton(*WidgetTree,
		Label.IsEmpty() ? FText::Format(LOCTEXT("OpenDocumentLink", "{0}  ›"), FText::FromString(Impresso.Title)) : Label,
		15, StationUi::Link, true);
	if (UTextBlock* Text = Cast<UTextBlock>(Open->GetChildAt(0)))
	{
		Text->SetFont(StationUi::MockupFont(StationUi::FontSemiBold, 15.f));
		// Less the link's own margins, so "›" stays on the label's line.
		WrapAt(*Text, CardWrapWidth - 12.f);
	}
	if (UVerticalBoxSlot* LinkSlot = Parent.AddChildToVerticalBox(Open))
	{
		LinkSlot->SetPadding(FMargin(-6.f, 8.f, 0.f, 0.f));
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
	// Shift + space bar holds the exam's talk key too (#419). A press refused while the
	// patient answers (the first tap of a cut) waits for nothing, so it looks idle.
	const bool bTalking = Flow && Flow->IsTalkingForExam();
	const bool bHeld = bMicrophoneHeld || bTalking;
	const bool bAccepted = bMicrophoneAccepted || bTalking;
	const EMicrophoneLook Look = !bHeld ? EMicrophoneLook::Idle
		: !bAccepted ? (Flow && !Flow->CanAskExamAloud() ? EMicrophoneLook::Waiting : EMicrophoneLook::Idle)
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
		ExamAloudText->SetText(LOCTEXT("ExamAloudIdle", "Segure para pedir (Shift + Espaço)"));
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
	StationUi::SetShown(SideActions, false);
}

void UStationHudWidget::CloseExams()
{
	StationUi::SetShown(ExamDrawer, false);
	StationUi::SetShown(SideActions, true);
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

void UStationHudWidget::HandlePressTalk()
{
	if (Flow)
	{
		Flow->PressTalkKey(/*bForExam*/ false, EStationTalkInput::TalkButton);
	}
	RefreshTalk();
}

void UStationHudWidget::HandleReleaseTalk()
{
	if (Flow)
	{
		Flow->ReleaseTalkKey(EStationTalkInput::TalkButton);
	}
	RefreshTalk();
}

void UStationHudWidget::HandleAskExamAloud()
{
	bMicrophoneHeld = true;
	// The exam push-to-talk (#419): refused while the previous spoken request still
	// waits for Phoenix, and while the patient answers unless the press follows a tap.
	bMicrophoneAccepted = Flow && Flow->PressTalkKey(/*bForExam*/ true, EStationTalkInput::ExamButton);
	RefreshMicrophone();
}

void UStationHudWidget::HandleReleaseExamAloud()
{
	bMicrophoneHeld = false;
	bMicrophoneAccepted = false;
	// Every press is released to the flow: a refused one may be the first tap of a cut,
	// and the flow ignores the release when another input holds the talk key (#419).
	if (Flow)
	{
		Flow->ReleaseTalkKey(EStationTalkInput::ExamButton);
	}
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

void UStationHudWidget::HandleOpenBrief()
{
	if (!Flow)
	{
		return;
	}
	if (Flow->GetSessionMode() == EStationSessionMode::SimulatedExam)
	{
		Flow->OpenBrief();
		return;
	}
	const FStationSummary* Station = Flow->GetStation();
	if (!Station)
	{
		return;
	}
	BriefTitleText->SetText(FText::FromString(Station->DisplayTitle));
	BriefScenarioText->SetText(FText::FromString(Station->Scenario));
	BriefTaskList->ClearChildren();
	for (const FString& Task : Station->Tasks)
	{
		AddLine(*WidgetTree, *BriefTaskList, FText::FromString(TEXT("•  ") + Task), StationUi::FontRegular, 17.f, StationUi::InkBody, 8.f);
	}
	StationUi::SetShown(BriefReader, true);
}

void UStationHudWidget::HandleCloseBriefReader()
{
	StationUi::SetShown(BriefReader, false);
}

void UStationHudWidget::RefreshTimer()
{
	if (Flow && Flow->GetClient() && Flow->ShowsStationTimer())
	{
		ShowStationTime(Flow->GetClient()->GetSignedRemainingTime());
	}
}

void UStationHudWidget::ShowStationTime(const FTimespan& Left)
{
	const bool bOvertime = Left < FTimespan::Zero();
	TimerText->SetText(FormatStationTimer(Left));
	TimerText->SetColorAndOpacity(FSlateColor(bOvertime ? StationUi::ProvaAccent : StationUi::InkTitle));
	TimerLabelText->SetText(bOvertime ? LOCTEXT("TimeOver", "Tempo esgotado · além do tempo") : LOCTEXT("TimeLeft", "Tempo restante"));
	TimerLabelText->SetColorAndOpacity(FSlateColor(bOvertime ? StationUi::ProvaAccent : StationUi::Muted));
}

void UStationHudWidget::Refresh()
{
	if (!Flow || !ModeText)
	{
		return;
	}
	if (Flow->GetStep() != EStationRunStep::Running)
	{
		StationUi::SetShown(BriefReader, false);
	}
	FinishButton->SetIsEnabled(Flow->CanFinish());
	// A simulated exam shows no countdown, only the desk clock in the room (#425).
	const bool bExam = Flow->GetSessionMode() == EStationSessionMode::SimulatedExam;
	ModeText->SetText(bExam ? LOCTEXT("SimulatedExamLabel", "Prova simulada")
		: Flow->GetMode() == EStationTrainingMode::Voice ? LOCTEXT("VoiceTrainingLabel", "Treino por voz")
		: LOCTEXT("TextTrainingLabel", "Treino por texto"));
	for (UWidget* Part : {TimerColumn.Get(), TimerDivider.Get(), static_cast<UWidget*>(TimerText.Get())})
	{
		StationUi::SetShown(Part, Flow->ShowsStationTimer());
	}
	RefreshTimer();
	StationUi::SetShown(FallbackText, Flow->IsVoiceFallback());

	const FStationVoiceView& Voice = Flow->GetVoice();
	const bool bVoiceRun = Flow->GetMode() == EStationTrainingMode::Voice && !Flow->IsVoiceFallback();
	const FLinearColor Accent = bExam ? StationUi::ProvaAccent : StationUi::TreinoAccent;
	FText Status;
	FLinearColor Dot = StationUi::Muted;
	if (Voice.bLost)
	{
		Status = LOCTEXT("VoiceLost", "A voz caiu. O tempo da estação continua.");
		Dot = StationUi::DangerInk;
	}
	else if (Voice.bMicrophoneUnavailable)
	{
		Status = LOCTEXT("MicrophoneUnavailable", "Microfone indisponível. Continue por escrito.");
		Dot = StationUi::DangerInk;
	}
	else if (Voice.State == EStationVoiceState::Ready)
	{
		Status = LOCTEXT("VoiceReady", "Voz conectada");
		Dot = Accent;
	}
	else if (Voice.State == EStationVoiceState::Reconnecting)
	{
		Status = LOCTEXT("VoiceReconnecting", "Reconectando a voz...");
		Dot = StationUi::ProvaAccent;
	}
	else if (Voice.State != EStationVoiceState::Disconnected)
	{
		Status = LOCTEXT("VoiceConnecting", "Conectando a voz...");
	}
	StationUi::SetShown(VoiceRow, bVoiceRun && !Status.IsEmpty());
	VoiceStatusText->SetText(Status);
	VoiceDot->SetBrushColor(Dot);

	RefreshConversation();
	RefreshTalk();
	RefreshExams();
}

void UStationHudWidget::RefreshTalk()
{
	if (!Flow || !TalkButton)
	{
		return;
	}
	const bool bShown = Flow->ShouldRequestExamsAloud(); // a voice training whose voice and microphone work
	StationUi::SetShown(TalkButton, bShown);
	// Hidden, not collapsed, where it can come back: the conversation must not jump each time.
	PatientTalkingRow->SetVisibility(Flow->IsPatientAnswering() ? ESlateVisibility::SelfHitTestInvisible
		: bShown ? ESlateVisibility::Hidden
		: ESlateVisibility::Collapsed);
	if (!bShown)
	{
		return;
	}
	// Disabling a held button would lose its release, so it stays enabled while the run goes on.
	TalkButton->SetIsEnabled(Flow->CanFinish());
	const bool bTalking = Flow->IsTalking() && !Flow->IsTalkingForExam();
	const FText Label = bTalking ? LOCTEXT("TalkTalking", "Falando... solte para enviar")
		: Flow->IsPatientAnswering() ? LOCTEXT("TalkCut", "Toque e segure para interromper")
		: LOCTEXT("TalkIdle", "Segure para falar (Espaço)");
	if (!Label.EqualTo(TalkText->GetText()))
	{
		TalkText->SetText(Label);
	}
	const FLinearColor Fill = bTalking ? StationUi::Recording
		: Flow->GetSessionMode() == EStationSessionMode::SimulatedExam ? StationUi::ProvaAccent
		: StationUi::TreinoAccent;
	if (TalkLookFill.IsSet() && TalkLookFill.GetValue() == Fill)
	{
		return;
	}
	TalkLookFill = Fill;
	const FLinearColor Ink = bTalking ? StationUi::InkTitle : StationUi::InkOnAccent;
	const FLinearColor Edge = bTalking ? StationUi::RecordingInk : Fill;
	FButtonStyle Style;
	Style.SetNormal(StationUi::RoundedBrush(Fill, 30.f, Edge, 1.5f));
	Style.SetHovered(StationUi::RoundedBrush(Fill, 30.f, StationUi::InkTitle, 1.5f));
	Style.SetPressed(StationUi::RoundedBrush(Fill, 30.f, Edge, 1.5f));
	Style.SetDisabled(StationUi::RoundedBrush(StationUi::Raised, 30.f, StationUi::PanelEdge, 1.5f));
	// With the label's line, the mockups' 60 px.
	Style.SetNormalPadding(FMargin(12.f, 19.f));
	Style.SetPressedPadding(FMargin(12.f, 19.f));
	TalkButton->SetStyle(Style);
	TalkText->SetColorAndOpacity(FSlateColor(Ink));
	TalkIcon->ClearChildren();
	AddMicrophoneIcon(*WidgetTree, *TalkIcon, Ink, 0.62f);
}

void UStationHudWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);
	if (Flow && Flow->GetClient() && TimerText)
	{
		RefreshTimer();
		Flow->CheckStationTimer();
	}
	RefreshTalk();
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
		UVerticalBox* Column = StationUi::MakeCenteredCard(*WidgetTree, 760.f, 900.f);
		TitleText = StationUi::AddText(*WidgetTree, *Column,
			StationInvalidatedTitle(EStationSessionMode::Training), 32, true, StationUi::Ink, 0.f);
		BodyText = StationUi::AddText(*WidgetTree, *Column,
			StationInvalidatedText(EStationSessionMode::Training, EStationInvalidation::PhoenixLost), 18);
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("InvalidatedRestart",
			"Reinicie a estação para começar de novo."), 16, false, StationUi::Muted);
		UButton* Restart = StationUi::AddButton(*WidgetTree, *Column, LOCTEXT("RestartStation", "Reiniciar estação"));
		Restart->OnClicked.AddDynamic(this, &UStationInvalidatedWidget::HandleRestart);
		StationUi::MakePrimary(*Restart);
	}
	return Super::RebuildWidget();
}

void UStationInvalidatedWidget::Refresh()
{
	if (!Flow || !TitleText || !BodyText)
	{
		return;
	}
	TitleText->SetText(StationInvalidatedTitle(Flow->GetSessionMode()));
	BodyText->SetText(StationInvalidatedText(Flow->GetSessionMode(), Flow->GetInvalidation()));
}

void UStationInvalidatedWidget::HandleRestart()
{
	OnRestart.ExecuteIfBound();
}

TSharedRef<SWidget> UStationFeedbackWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UVerticalBox* Footer = nullptr;
		UVerticalBox* Column = StationUi::MakeFooterCard(*WidgetTree, 920.f, 900.f, Footer);
		FooterBox = Footer;
		StationUi::AddText(*WidgetTree, *Column, LOCTEXT("ResultTitle", "Resultado educacional da estação"), 30, true,
			StationUi::Ink, 0.f);
		// Every state of this screen says what the result is not.
		StationUi::AddText(*WidgetTree, *Column, ResultDisclaimer(), 16, false, StationUi::Muted);

		LoadingBox = WidgetTree->ConstructWidget<UVerticalBox>();
		Column->AddChild(LoadingBox);
		StationUi::AddText(*WidgetTree, *LoadingBox, LOCTEXT("LoadingResult", "Gerando o resultado da estação..."), 18);
		StationUi::AddText(*WidgetTree, *LoadingBox, LOCTEXT("LoadingResultWait",
			"Gerando feedback da estação… isso pode levar até um minuto."), 15, false, StationUi::Muted, 4.f);

		ErrorText = StationUi::AddText(*WidgetTree, *Column, FText::GetEmpty(), 18, false, StationUi::Caution);

		ResultBox = WidgetTree->ConstructWidget<UVerticalBox>();
		Column->AddChild(ResultBox);

		RestartNote = StationUi::AddText(*WidgetTree, *FooterBox, LOCTEXT("RestartDiscards",
			"Ao reiniciar, esta tentativa é descartada e não poderá ser recuperada."), 15, false, StationUi::Muted, 16.f);
		SessionNote = StationUi::AddText(*WidgetTree, *FooterBox, LOCTEXT("SessionOnly",
			"Evidências apenas desta sessão. Ao reiniciar, os dados são descartados; não há histórico pessoal."),
			15, false, StationUi::Muted, 16.f);
		RestartButton = StationUi::AddButton(*WidgetTree, *FooterBox, LOCTEXT("RestartStation", "Reiniciar estação"), 14.f);
		RestartButton->OnClicked.AddDynamic(this, &UStationFeedbackWidget::HandleRestart);
		StationUi::MakePrimary(*RestartButton);

		// The card built above is the tree's root until now; both screens share it from here.
		CardScreen = WidgetTree->RootWidget;
		ExamScreen = BuildExamScreen();
		UOverlay* Screens = WidgetTree->ConstructWidget<UOverlay>();
		WidgetTree->RootWidget = Screens;
		for (UWidget* Screen : {CardScreen.Get(), ExamScreen.Get()})
		{
			if (UOverlaySlot* ScreenSlot = Screens->AddChildToOverlay(Screen))
			{
				ScreenSlot->SetHorizontalAlignment(HAlign_Fill);
				ScreenSlot->SetVerticalAlignment(VAlign_Fill);
			}
		}
		StationUi::SetShown(ExamScreen, false);
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
	StationUi::SetShown(FooterBox, bFeedback);
	StationUi::SetShown(RestartNote, bFeedback && !Result);
	StationUi::SetShown(SessionNote, Result != nullptr);
	StationUi::SetShown(RestartButton, bFeedback);
	RestartButton->SetIsEnabled(Flow->CanDiscard());

	// Only Phoenix scores a Prova simulada, so its score is what picks the layout.
	const bool bExamResult = Result && Result->CertaintyLevel > 0;
	StationUi::SetShown(CardScreen, !bExamResult);
	StationUi::SetShown(ExamScreen, bExamResult);

	ResultBox->ClearChildren();
	StationUi::SetShown(ResultBox, Result != nullptr);
	if (!Result)
	{
		return;
	}
	if (bExamResult)
	{
		ShowExamResult(*Result);
		return;
	}

	if (Result->bPlaceholder)
	{
		StationUi::AddText(*WidgetTree, *ResultBox, LOCTEXT("FictionalResult", "Exemplo — dados fictícios"), 15, true,
			StationUi::Caution);
	}
	AddSummary(*Result);
	for (int32 Index = 0; Index < Result->Criteria.Num(); ++Index)
	{
		AddCriterion(Index + 1, Result->Criteria[Index]);
	}
}

namespace
{
	/** The widest an evidence bubble's text runs inside a criterion card. */
	constexpr float EvidenceWrapWidth = 560.f;

	/** A rounded card of the result, below what came before it in `Parent`. */
	UVerticalBox* AddResultCard(UWidgetTree& Tree, UVerticalBox& Parent)
	{
		UBorder* Card = StationUi::MakeRounded(Tree, StationUi::Raised, 10.f, FMargin(18.f, 14.f));
		if (UVerticalBoxSlot* CardSlot = Parent.AddChildToVerticalBox(Card))
		{
			CardSlot->SetPadding(FMargin(0.f, Parent.GetChildrenCount() > 1 ? 12.f : 24.f, 0.f, 0.f));
		}
		UVerticalBox* Column = Tree.ConstructWidget<UVerticalBox>();
		Card->SetContent(Column);
		return Column;
	}

	/** One count of the coverage summary: the number large, in its status's color, over its label. */
	void AddCountTile(UWidgetTree& Tree, UHorizontalBox& Row, int32 Count, const FText& Label, const FLinearColor& Color)
	{
		UBorder* Tile = StationUi::MakeRounded(Tree, StationUi::PanelSolid, 8.f, FMargin(12.f, 8.f));
		if (UHorizontalBoxSlot* TileSlot = Row.AddChildToHorizontalBox(Tile))
		{
			TileSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
			TileSlot->SetPadding(FMargin(Row.GetChildrenCount() > 1 ? 10.f : 0.f, 0.f, 0.f, 0.f));
		}
		UVerticalBox* Column = Tree.ConstructWidget<UVerticalBox>();
		Tile->SetContent(Column);
		StationUi::AddText(Tree, *Column, FText::AsNumber(Count), 24, true, Color, 0.f);
		StationUi::AddText(Tree, *Column, Label, 14, false, StationUi::Muted, 0.f);
	}
}

void UStationFeedbackWidget::AddSummary(const FStationResult& Result)
{
	auto Count = [&Result](EStationCriterionStatus Status)
	{
		return Result.Criteria.FilterByPredicate(
			[Status](const FStationCriterionResult& Criterion) { return Criterion.Status == Status; }).Num();
	};

	UVerticalBox* Summary = AddResultCard(*WidgetTree, *ResultBox);
	StationUi::AddText(*WidgetTree, *Summary, LOCTEXT("Coverage", "Cobertura dos critérios"), 20, true, StationUi::Ink, 0.f);
	UHorizontalBox* Counts = WidgetTree->ConstructWidget<UHorizontalBox>();
	if (UVerticalBoxSlot* CountsSlot = Summary->AddChildToVerticalBox(Counts))
	{
		CountsSlot->SetPadding(FMargin(0.f, 12.f, 0.f, 0.f));
	}
	AddCountTile(*WidgetTree, *Counts, Count(EStationCriterionStatus::Assessed),
		LOCTEXT("CountAssessed", "Avaliados"), StationUi::ReleasedInk);
	AddCountTile(*WidgetTree, *Counts, Count(EStationCriterionStatus::Uncertain),
		LOCTEXT("CountUncertain", "Incertos"), StationUi::DeclinedInk);
	AddCountTile(*WidgetTree, *Counts, Count(EStationCriterionStatus::NotObservable),
		LOCTEXT("CountNotObservable", "Não observáveis"), StationUi::NeutralInk);
	AddCountTile(*WidgetTree, *Counts, Count(EStationCriterionStatus::NotApplicable),
		LOCTEXT("CountExcluded", "Excluídos"), StationUi::NeutralInk);

	StationUi::AddText(*WidgetTree, *Summary, FText::Format(LOCTEXT("ScoredPoints",
		"Pontos obtidos nos critérios avaliados: {0} de {1}"),
		DisplayPoints(Result.ScoredSubtotal), DisplayPoints(Result.ScoredMax)), 16, false, StationUi::Ink, 14.f);
	StationUi::AddText(*WidgetTree, *Summary, FText::Format(LOCTEXT("EligibleMax",
		"Máximo da estação (todos os critérios elegíveis): {0}"), DisplayPoints(Result.EligibleMax)), 16, false,
		StationUi::Ink, 4.f);
	const bool bNoneEligible = Result.Criteria.Num() == Count(EStationCriterionStatus::NotApplicable);
	StationUi::AddText(*WidgetTree, *Summary, !Result.EstimatedTotal.IsEmpty()
		? FText::Format(LOCTEXT("Total", "Total educacional: {0}"), DisplayPoints(Result.EstimatedTotal))
		: bNoneEligible
		? LOCTEXT("NoEligible", "Nenhum critério elegível — não há estimativa total.")
		: LOCTEXT("OpenTotal",
			"Total indisponível — há critérios não resolvidos. Os pontos acima contam apenas os critérios avaliados e não representam a estação inteira."),
		16, true, StationUi::Ink, 10.f);
}

void UStationFeedbackWidget::AddCriterion(int32 Ordinal, const FStationCriterionResult& Criterion)
{
	UBorder* Chip = nullptr;
	FText Note;
	switch (Criterion.Status)
	{
	case EStationCriterionStatus::Assessed:
		Chip = MakeChip(*WidgetTree, LOCTEXT("CriterionAssessed", "Avaliado"), StationUi::ReleasedFill, StationUi::ReleasedInk);
		Note = FText::Format(LOCTEXT("CriterionPoints", "Pontos: {0} de {1}"),
			DisplayPoints(Criterion.Points), DisplayPoints(Criterion.MaxPoints));
		break;
	case EStationCriterionStatus::Uncertain:
		Chip = MakeChip(*WidgetTree, LOCTEXT("CriterionUncertain", "Incerto"), StationUi::DeclinedFill, StationUi::DeclinedInk);
		Note = LOCTEXT("CriterionUncertainNote", "sem pontos atribuídos");
		break;
	case EStationCriterionStatus::NotObservable:
		Chip = MakeChip(*WidgetTree, LOCTEXT("CriterionNotObservable", "Não observável"), StationUi::NeutralFill,
			StationUi::NeutralInk);
		Note = LOCTEXT("CriterionNotObservableNote", "modalidade indisponível; sem pontos atribuídos");
		break;
	case EStationCriterionStatus::NotApplicable:
		Chip = MakeChip(*WidgetTree, LOCTEXT("CriterionExcluded", "Excluído pelo autor"), StationUi::NeutralFill,
			StationUi::NeutralInk);
		Note = LOCTEXT("CriterionExcludedNote", "fora dos máximos; sem pontos atribuídos");
		break;
	}

	UVerticalBox* Card = AddResultCard(*WidgetTree, *ResultBox);
	UHorizontalBox* Heading = WidgetTree->ConstructWidget<UHorizontalBox>();
	Card->AddChild(Heading);
	UTextBlock* Title = WidgetTree->ConstructWidget<UTextBlock>();
	Title->SetText(FText::Format(LOCTEXT("CriterionHeading", "Critério {0}"), Ordinal));
	Title->SetFont(StationUi::Font(StationUi::FontBold, 18));
	Title->SetColorAndOpacity(FSlateColor(StationUi::Ink));
	if (UHorizontalBoxSlot* TitleSlot = Heading->AddChildToHorizontalBox(Title))
	{
		TitleSlot->SetVerticalAlignment(VAlign_Center);
	}
	if (UHorizontalBoxSlot* ChipSlot = Heading->AddChildToHorizontalBox(Chip))
	{
		ChipSlot->SetPadding(FMargin(10.f, 0.f, 0.f, 0.f));
		ChipSlot->SetVerticalAlignment(VAlign_Center);
	}
	const bool bAssessed = Criterion.Status == EStationCriterionStatus::Assessed;
	UTextBlock* NoteText = WidgetTree->ConstructWidget<UTextBlock>();
	NoteText->SetText(Note);
	NoteText->SetFont(StationUi::Font(bAssessed ? StationUi::FontBold : StationUi::FontRegular, bAssessed ? 16 : 14));
	NoteText->SetColorAndOpacity(FSlateColor(bAssessed ? StationUi::Ink : StationUi::Muted));
	NoteText->SetJustification(ETextJustify::Right);
	NoteText->SetAutoWrapText(true);
	if (UHorizontalBoxSlot* NoteSlot = Heading->AddChildToHorizontalBox(NoteText))
	{
		NoteSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		NoteSlot->SetPadding(FMargin(16.f, 0.f, 0.f, 0.f));
		NoteSlot->SetVerticalAlignment(VAlign_Center);
	}

	StationUi::AddText(*WidgetTree, *Card, FText::FromString(Criterion.Description), 16, false, StationUi::Ink, 10.f);
	AddCriterionDetails(*Card, Criterion, 15);
}

void UStationFeedbackWidget::AddCriterionDetails(UVerticalBox& Card, const FStationCriterionResult& Criterion, int32 TextSize)
{
	const int32 HeadingSize = TextSize - 1;
	if (Criterion.Status == EStationCriterionStatus::Assessed && !Criterion.LevelDescription.TrimStartAndEnd().IsEmpty())
	{
		StationUi::AddText(*WidgetTree, Card, FText::Format(LOCTEXT("CriterionLevel", "Nível autoral: {0}"),
			FText::FromString(Criterion.LevelDescription)), TextSize, false, StationUi::Muted, 4.f);
	}

	if (Criterion.Evidence.Num() > 0)
	{
		StationUi::AddText(*WidgetTree, Card, LOCTEXT("EvidenceHeading", "Evidências"), HeadingSize, true, StationUi::Muted, 14.f);
		for (const FStationEvidence& Excerpt : Criterion.Evidence)
		{
			// Laid out like the conversation: the learner's words on the right, the patient's on the left.
			const bool bLearner = Excerpt.Speaker == EStationSpeaker::Learner;
			UBorder* Bubble = StationUi::MakeRounded(*WidgetTree, bLearner ? StationUi::LearnerBubble : StationUi::PanelSolid,
				10.f, FMargin(12.f, 8.f));
			if (UVerticalBoxSlot* BubbleSlot = Card.AddChildToVerticalBox(Bubble))
			{
				BubbleSlot->SetPadding(FMargin(0.f, 6.f, 0.f, 0.f));
				BubbleSlot->SetHorizontalAlignment(bLearner ? HAlign_Right : HAlign_Left);
			}
			UTextBlock* Quote = WidgetTree->ConstructWidget<UTextBlock>();
			Quote->SetText(FText::Format(bLearner
				? LOCTEXT("EvidenceLearner", "Você: “{0}”")
				: LOCTEXT("EvidencePatient", "Paciente: “{0}”"), FText::FromString(Excerpt.Text)));
			Quote->SetFont(StationUi::Font(StationUi::FontRegular, TextSize));
			Quote->SetColorAndOpacity(FSlateColor(StationUi::Ink));
			Quote->SetWrapTextAt(EvidenceWrapWidth);
			Bubble->SetContent(Quote);
		}
	}

	StationUi::AddText(*WidgetTree, Card, LOCTEXT("RecommendationHeading", "Recomendação"), HeadingSize, true, StationUi::Muted, 14.f);
	StationUi::AddText(*WidgetTree, Card, FText::FromString(Criterion.Recommendation), TextSize, false, StationUi::Ink, 4.f);
}

void UStationCriterionRow::HandleClicked()
{
	StationUi::SetShown(Details, Details && Details->GetVisibility() == ESlateVisibility::Collapsed);
}

namespace
{
	/** The width of the left column, and of a row's first and last cells, as in the mockup. */
	constexpr float ExamSummaryWidth = 500.f;
	constexpr float ExamOrdinalWidth = 76.f;
	constexpr float ExamPointsWidth = 104.f;

	// The font sizes below are the mockup's pixels times 0.75: Slate's size is in points
	// at 96 DPI, so the same number would come out a third larger than in the mockup.

	/** The tracking of the mockup's `.eyebrow`, in thousandths of an em. */
	constexpr int32 EyebrowTracking = 120;

	UTextBlock* AddEyebrow(UWidgetTree& Tree, UPanelWidget& Parent, const FText& Text, int32 Size, const FLinearColor& Color,
		float SpaceAbove = 0.f)
	{
		UTextBlock* Block = StationUi::AddText(Tree, Parent, Text, Size, true, Color, SpaceAbove);
		FSlateFontInfo Font = StationUi::Font(StationUi::FontBold, Size);
		Font.LetterSpacing = EyebrowTracking;
		Block->SetFont(Font);
		return Block;
	}

	/** How sure the level is, in the mockup's three colors. */
	FLinearColor CertaintyColor(int32 Level)
	{
		return Level >= 4 ? StationUi::TreinoAccent : Level >= 2 ? StationUi::ProvaAccent : StationUi::DangerInk;
	}

	/** Lights `Level` of the five segments. */
	UHorizontalBox* MakeCertaintyMeter(UWidgetTree& Tree, int32 Level)
	{
		UHorizontalBox* Meter = Tree.ConstructWidget<UHorizontalBox>();
		for (int32 Step = 1; Step <= 5; ++Step)
		{
			USizeBox* Segment = Tree.ConstructWidget<USizeBox>();
			Segment->SetHeightOverride(8.f);
			Segment->SetContent(StationUi::MakeRounded(Tree, Step <= Level ? CertaintyColor(Level) : StationUi::PanelEdge,
				4.f, FMargin(0.f)));
			if (UHorizontalBoxSlot* SegmentSlot = Meter->AddChildToHorizontalBox(Segment))
			{
				SegmentSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
				SegmentSlot->SetPadding(FMargin(Step > 1 ? 6.f : 0.f, 0.f, 0.f, 0.f));
			}
		}
		return Meter;
	}

	/** A criterion's outcome as an outlined pill. */
	UBorder* MakeOutcomeChip(UWidgetTree& Tree, const FStationCriterionResult& Criterion)
	{
		FText Label;
		FLinearColor Color = StationUi::Muted;
		switch (Criterion.Status)
		{
		case EStationCriterionStatus::Assessed:
			Label = Criterion.Level == TEXT("adequado") ? LOCTEXT("OutcomeAdequate", "Adequado")
				: Criterion.Level == TEXT("parcialmente_adequado") ? LOCTEXT("OutcomePartial", "Parcialmente adequado")
				: LOCTEXT("OutcomeInadequate", "Inadequado");
			Color = Criterion.Level == TEXT("adequado") ? StationUi::TreinoAccent
				: Criterion.Level == TEXT("parcialmente_adequado") ? StationUi::ProvaAccent : StationUi::DangerInk;
			break;
		case EStationCriterionStatus::Uncertain:
			Label = LOCTEXT("CriterionUncertain", "Incerto");
			break;
		case EStationCriterionStatus::NotObservable:
			Label = LOCTEXT("CriterionNotObservable", "Não observável");
			break;
		case EStationCriterionStatus::NotApplicable:
			Label = LOCTEXT("OutcomeExcluded", "Excluído");
			break;
		}
		const bool bAssessed = Criterion.Status == EStationCriterionStatus::Assessed;
		UBorder* Chip = StationUi::MakeRounded(Tree, FLinearColor::Transparent, 16.f, FMargin(12.f, 6.f),
			bAssessed ? Color : StationUi::ChipEdge, 1.f);
		UTextBlock* Text = Tree.ConstructWidget<UTextBlock>();
		Text->SetText(Label);
		Text->SetFont(StationUi::Font(StationUi::FontSemiBold, 10));
		Text->SetColorAndOpacity(FSlateColor(Color));
		Chip->SetContent(Text);
		return Chip;
	}
}

FText StationCertaintyLabel(int32 Level)
{
	switch (Level)
	{
	case 5:
		return LOCTEXT("CertaintyFive", "Certeira");
	case 4:
		return LOCTEXT("CertaintyFour", "Quase certeira");
	case 3:
		return LOCTEXT("CertaintyThree", "Parcialmente certeira");
	case 2:
		return LOCTEXT("CertaintyTwo", "Pouco certeira");
	default:
		return LOCTEXT("CertaintyOne", "Insuficiente");
	}
}

FText StationIncompleteNotice(const FStationResult& Result)
{
	if (!Result.bIncomplete)
	{
		return FText::GetEmpty();
	}

	TArray<FText> LeftOut;
	for (int32 Index = 0; Index < Result.Criteria.Num(); ++Index)
	{
		const EStationCriterionStatus Status = Result.Criteria[Index].Status;
		if (Status == EStationCriterionStatus::Uncertain)
		{
			LeftOut.Add(FText::Format(LOCTEXT("LeftOutUncertain", "Critério {0} (incerto)"), Index + 1));
		}
		else if (Status == EStationCriterionStatus::NotObservable)
		{
			LeftOut.Add(FText::Format(LOCTEXT("LeftOutNotObservable", "Critério {0} (não observável)"), Index + 1));
		}
	}

	const bool bOne = LeftOut.Num() == 1;
	const FText List = FText::Join(LOCTEXT("LeftOutSeparator", ", "), LeftOut);
	const FText Lead = Result.CertaintyLevel == 2
		? LOCTEXT("IncompleteLow", "Nota incompleta e pouco certeira: leia este total com cautela.")
		: LOCTEXT("Incomplete", "Nota incompleta.");
	const FText Names = FText::Format(bOne
		? LOCTEXT("LeftOutOne", "{0} Ficou de fora: {1}.")
		: LOCTEXT("LeftOutMany", "{0} Ficaram de fora: {1}."), Lead, List);
	if (Result.ScaledTotal.IsEmpty())
	{
		return Names;
	}
	return FText::Format(bOne
		? LOCTEXT("EstimatedWithoutIt", "{0} O total foi estimado sem ele.")
		: LOCTEXT("EstimatedWithoutThem", "{0} O total foi estimado sem eles."), Names);
}

UWidget* UStationFeedbackWidget::BuildExamScreen()
{
	UOverlay* Screen = WidgetTree->ConstructWidget<UOverlay>();

	UBorder* Backdrop = WidgetTree->ConstructWidget<UBorder>();
	Backdrop->SetBrushColor(StationUi::Backdrop);
	Backdrop->SetPadding(FMargin(96.f, 64.f, 96.f, 48.f));
	if (UOverlaySlot* BackdropSlot = Screen->AddChildToOverlay(Backdrop))
	{
		BackdropSlot->SetHorizontalAlignment(HAlign_Fill);
		BackdropSlot->SetVerticalAlignment(VAlign_Fill);
	}

	UBorder* Sample = StationUi::MakeRounded(*WidgetTree, StationUi::Ink, 4.f, FMargin(10.f, 4.f));
	UTextBlock* SampleText = WidgetTree->ConstructWidget<UTextBlock>();
	SampleText->SetText(LOCTEXT("FictionalResultMark", "EXEMPLO — DADOS FICTÍCIOS"));
	SampleText->SetFont(StationUi::Font(StationUi::FontBold, 9));
	SampleText->SetColorAndOpacity(FSlateColor(StationUi::InkOnAccent));
	Sample->SetContent(SampleText);
	ExamSampleMark = Sample;
	if (UOverlaySlot* SampleSlot = Screen->AddChildToOverlay(Sample))
	{
		SampleSlot->SetHorizontalAlignment(HAlign_Center);
		SampleSlot->SetVerticalAlignment(VAlign_Top);
		SampleSlot->SetPadding(FMargin(0.f, 24.f, 0.f, 0.f));
	}

	UHorizontalBox* Columns = WidgetTree->ConstructWidget<UHorizontalBox>();
	Backdrop->SetContent(Columns);

	USizeBox* LeftSize = WidgetTree->ConstructWidget<USizeBox>();
	LeftSize->SetWidthOverride(ExamSummaryWidth);
	Columns->AddChild(LeftSize);
	UVerticalBox* Left = WidgetTree->ConstructWidget<UVerticalBox>();
	LeftSize->SetContent(Left);

	// A long list of what was left out scrolls; the disclaimer and the way out stay in view.
	UScrollBox* SummaryScroll = WidgetTree->ConstructWidget<UScrollBox>();
	if (UVerticalBoxSlot* ScrollSlot = Left->AddChildToVerticalBox(SummaryScroll))
	{
		ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	}
	ExamSummaryBox = WidgetTree->ConstructWidget<UVerticalBox>();
	SummaryScroll->AddChild(ExamSummaryBox);

	StationUi::AddText(*WidgetTree, *Left, ResultDisclaimer(), 10, false, StationUi::Muted, 14.f);
	ExamErrorText = StationUi::AddText(*WidgetTree, *Left, FText::GetEmpty(), 11, false, StationUi::Caution, 6.f);
	ExamBackButton = StationUi::AddButton(*WidgetTree, *Left, LOCTEXT("BackToMenu", "Voltar ao menu"), 14.f);
	ExamBackButton->OnClicked.AddDynamic(this, &UStationFeedbackWidget::HandleRestart);
	StationUi::MakeExam(*ExamBackButton);
	if (UVerticalBoxSlot* BackSlot = Cast<UVerticalBoxSlot>(ExamBackButton->Slot))
	{
		BackSlot->SetHorizontalAlignment(HAlign_Left);
	}

	UVerticalBox* Right = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UHorizontalBoxSlot* RightSlot = Columns->AddChildToHorizontalBox(Right))
	{
		RightSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		RightSlot->SetPadding(FMargin(64.f, 0.f, 0.f, 0.f));
	}

	UHorizontalBox* Heading = WidgetTree->ConstructWidget<UHorizontalBox>();
	Right->AddChild(Heading);
	UTextBlock* HeadingText = WidgetTree->ConstructWidget<UTextBlock>();
	HeadingText->SetText(LOCTEXT("CriteriaHeading", "Critérios"));
	HeadingText->SetFont(StationUi::Font(StationUi::FontBold, 15));
	HeadingText->SetColorAndOpacity(FSlateColor(StationUi::InkTitle));
	Heading->AddChild(HeadingText);
	ExamPointsText = WidgetTree->ConstructWidget<UTextBlock>();
	ExamPointsText->SetFont(StationUi::Font(StationUi::FontMedium, 11));
	ExamPointsText->SetColorAndOpacity(FSlateColor(StationUi::Muted));
	ExamPointsText->SetJustification(ETextJustify::Right);
	if (UHorizontalBoxSlot* PointsSlot = Heading->AddChildToHorizontalBox(ExamPointsText))
	{
		PointsSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		PointsSlot->SetVerticalAlignment(VAlign_Bottom);
	}

	UBorder* Panel = StationUi::MakePanel(*WidgetTree, FMargin(24.f, 4.f));
	if (UVerticalBoxSlot* PanelSlot = Right->AddChildToVerticalBox(Panel))
	{
		PanelSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		PanelSlot->SetPadding(FMargin(0.f, 16.f, 0.f, 0.f));
	}
	UScrollBox* CriteriaScroll = WidgetTree->ConstructWidget<UScrollBox>();
	Panel->SetContent(CriteriaScroll);
	ExamCriteriaBox = WidgetTree->ConstructWidget<UVerticalBox>();
	CriteriaScroll->AddChild(ExamCriteriaBox);

	StationUi::AddText(*WidgetTree, *Right, LOCTEXT("OpenCriterionHint",
		"Toque num critério para ver a evidência e a recomendação."), 10, false, StationUi::Muted, 16.f);

	return Screen;
}

void UStationFeedbackWidget::ShowExamResult(const FStationResult& Result)
{
	StationUi::SetShown(ExamSampleMark, Result.bPlaceholder);
	StationUi::SetShown(ExamErrorText, !Flow->GetErrorText().IsEmpty());
	ExamErrorText->SetText(Flow->GetErrorText());
	ExamBackButton->SetIsEnabled(Flow->CanDiscard());
	ExamPointsText->SetText(FText::Format(LOCTEXT("AssessedOfStation", "Avaliados {0} dos {1} pontos da estação"),
		DisplayPoints(Result.ScoredMax), DisplayPoints(Result.EligibleMax)));

	ExamSummaryBox->ClearChildren();
	AddExamSummary(Result);

	ExamCriteriaBox->ClearChildren();
	ExamRows.Reset();
	for (int32 Index = 0; Index < Result.Criteria.Num(); ++Index)
	{
		AddExamCriterion(Index + 1, Result.Criteria[Index]);
	}
}

void UStationFeedbackWidget::AddExamSummary(const FStationResult& Result)
{
	UHorizontalBox* Mode = WidgetTree->ConstructWidget<UHorizontalBox>();
	ExamSummaryBox->AddChild(Mode);
	if (UHorizontalBoxSlot* MarkSlot = Mode->AddChildToHorizontalBox(StationUi::MakeModeMark(*WidgetTree, StationUi::ProvaAccent)))
	{
		MarkSlot->SetVerticalAlignment(VAlign_Center);
		MarkSlot->SetPadding(FMargin(0.f, 0.f, 12.f, 0.f));
	}
	AddEyebrow(*WidgetTree, *Mode, LOCTEXT("ExamResultMode", "RESULTADO EDUCACIONAL · PROVA SIMULADA"), 10, StationUi::ProvaAccent);

	if (const FStationSummary* Station = Flow->GetStation())
	{
		StationUi::AddText(*WidgetTree, *ExamSummaryBox, FText::FromString(Station->DisplayTitle), 24, true, StationUi::InkTitle, 26.f);
	}

	AddEyebrow(*WidgetTree, *ExamSummaryBox, LOCTEXT("EstimatedTotal", "TOTAL ESTIMADO"), 9, StationUi::Muted, 26.f);
	if (!Result.ScaledTotal.IsEmpty())
	{
		UHorizontalBox* Total = WidgetTree->ConstructWidget<UHorizontalBox>();
		ExamSummaryBox->AddChild(Total);
		UTextBlock* Scaled = WidgetTree->ConstructWidget<UTextBlock>();
		Scaled->SetText(DisplayPoints(Result.ScaledTotal));
		Scaled->SetFont(StationUi::Font(StationUi::FontExtraBold, 66));
		Scaled->SetColorAndOpacity(FSlateColor(StationUi::InkTitle));
		Total->AddChild(Scaled);
		UTextBlock* Of = WidgetTree->ConstructWidget<UTextBlock>();
		Of->SetText(FText::Format(LOCTEXT("OfMaximum", "de {0}"), DisplayPoints(Result.EligibleMax)));
		Of->SetFont(StationUi::Font(StationUi::FontSemiBold, 21));
		Of->SetColorAndOpacity(FSlateColor(StationUi::Muted));
		if (UHorizontalBoxSlot* OfSlot = Total->AddChildToHorizontalBox(Of))
		{
			OfSlot->SetVerticalAlignment(VAlign_Bottom);
			OfSlot->SetPadding(FMargin(10.f, 0.f, 0.f, 10.f));
		}
	}
	else
	{
		const bool bNoneEligible = !Result.Criteria.ContainsByPredicate([](const FStationCriterionResult& Criterion)
		{
			return Criterion.Status != EStationCriterionStatus::NotApplicable;
		});
		StationUi::AddText(*WidgetTree, *ExamSummaryBox, LOCTEXT("NoExamTotal", "Sem total nesta tentativa"), 21, true,
			StationUi::InkTitle, 8.f);
		StationUi::AddText(*WidgetTree, *ExamSummaryBox, bNoneEligible
			? LOCTEXT("NoEligible", "Nenhum critério elegível — não há estimativa total.")
			: LOCTEXT("ExamBelowFloor", "Menos de 40% dos pontos da estação puderam ser avaliados."),
			11, false, StationUi::InkBody, 8.f);
	}

	UBorder* Panel = StationUi::MakePanel(*WidgetTree, FMargin(22.f, 20.f));
	if (UVerticalBoxSlot* PanelSlot = ExamSummaryBox->AddChildToVerticalBox(Panel))
	{
		PanelSlot->SetPadding(FMargin(0.f, 26.f, 0.f, 0.f));
	}
	UVerticalBox* Certainty = WidgetTree->ConstructWidget<UVerticalBox>();
	Panel->SetContent(Certainty);

	UHorizontalBox* Heading = WidgetTree->ConstructWidget<UHorizontalBox>();
	Certainty->AddChild(Heading);
	UTextBlock* HeadingText = AddEyebrow(*WidgetTree, *Heading, LOCTEXT("CertaintyHeading", "CERTEZA DA ESTIMATIVA"), 9,
		StationUi::Muted);
	if (UHorizontalBoxSlot* HeadingSlot = Cast<UHorizontalBoxSlot>(HeadingText->Slot))
	{
		HeadingSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
		HeadingSlot->SetVerticalAlignment(VAlign_Center);
	}
	UTextBlock* Label = WidgetTree->ConstructWidget<UTextBlock>();
	Label->SetText(StationCertaintyLabel(Result.CertaintyLevel));
	Label->SetFont(StationUi::Font(StationUi::FontBold, 14));
	Label->SetColorAndOpacity(FSlateColor(CertaintyColor(Result.CertaintyLevel)));
	Heading->AddChild(Label);

	ExamMeter = MakeCertaintyMeter(*WidgetTree, Result.CertaintyLevel);
	if (UVerticalBoxSlot* MeterSlot = Certainty->AddChildToVerticalBox(ExamMeter))
	{
		MeterSlot->SetPadding(FMargin(0.f, 14.f, 0.f, 0.f));
	}

	// Phoenix's exact points, not the mockup's percentage: the client computes nothing.
	StationUi::AddText(*WidgetTree, *Certainty, Result.CertaintyLevel == 5 && !Result.bIncomplete
		? LOCTEXT("AllAssessed", "Todos os critérios da estação foram avaliados.")
		: FText::Format(LOCTEXT("PointsAssessed", "{0} dos {1} pontos da estação foram avaliados."),
			DisplayPoints(Result.ScoredMax), DisplayPoints(Result.EligibleMax)),
		11, false, StationUi::InkBody, 14.f);
	if (Result.bIncomplete)
	{
		StationUi::AddText(*WidgetTree, *Certainty, StationIncompleteNotice(Result), 11, false,
			Result.CertaintyLevel == 2 ? StationUi::DangerInk : StationUi::ProvaWarning, 14.f);
	}
}

void UStationFeedbackWidget::AddExamCriterion(int32 Ordinal, const FStationCriterionResult& Criterion)
{
	UButton* Row = WidgetTree->ConstructWidget<UButton>();
	StationUi::MakeRow(*Row);
	ExamCriteriaBox->AddChild(Row);

	UHorizontalBox* Cells = WidgetTree->ConstructWidget<UHorizontalBox>();
	Row->AddChild(Cells);
	if (UButtonSlot* CellsSlot = Cast<UButtonSlot>(Cells->Slot))
	{
		CellsSlot->SetHorizontalAlignment(HAlign_Fill);
		CellsSlot->SetPadding(FMargin(0.f, 14.f));
	}

	auto AddCell = [this, Cells](UWidget* Cell, ESlateSizeRule::Type Size, float SpaceBefore)
	{
		if (UHorizontalBoxSlot* CellSlot = Cells->AddChildToHorizontalBox(Cell))
		{
			CellSlot->SetSize(FSlateChildSize(Size));
			CellSlot->SetVerticalAlignment(VAlign_Center);
			CellSlot->SetPadding(FMargin(SpaceBefore, 0.f, 0.f, 0.f));
		}
	};
	auto MakeFixedCell = [this](const FText& Text, FName Weight, int32 Size, const FLinearColor& Color, float Width,
		ETextJustify::Type Justification)
	{
		USizeBox* Cell = WidgetTree->ConstructWidget<USizeBox>();
		Cell->SetWidthOverride(Width);
		UTextBlock* Block = WidgetTree->ConstructWidget<UTextBlock>();
		Block->SetText(Text);
		Block->SetFont(StationUi::Font(Weight, Size));
		Block->SetColorAndOpacity(FSlateColor(Color));
		Block->SetJustification(Justification);
		Cell->SetContent(Block);
		return Cell;
	};

	AddCell(MakeFixedCell(FText::Format(LOCTEXT("CriterionHeading", "Critério {0}"), Ordinal), StationUi::FontRegular, 10,
		StationUi::Muted, ExamOrdinalWidth, ETextJustify::Left), ESlateSizeRule::Automatic, 0.f);

	UTextBlock* Description = WidgetTree->ConstructWidget<UTextBlock>();
	Description->SetText(FText::FromString(Criterion.Description));
	Description->SetFont(StationUi::Font(StationUi::FontRegular, 11));
	Description->SetColorAndOpacity(FSlateColor(StationUi::InkTitle));
	Description->SetAutoWrapText(true);
	AddCell(Description, ESlateSizeRule::Fill, 20.f);

	AddCell(MakeOutcomeChip(*WidgetTree, Criterion), ESlateSizeRule::Automatic, 20.f);

	const FText Points = Criterion.Status == EStationCriterionStatus::Assessed
		? FText::Format(LOCTEXT("CriterionPointsShort", "{0} / {1}"), DisplayPoints(Criterion.Points), DisplayPoints(Criterion.MaxPoints))
		: LOCTEXT("NoPoints", "sem pontos");
	AddCell(MakeFixedCell(Points, StationUi::FontBold, 11, StationUi::Ink, ExamPointsWidth, ETextJustify::Right),
		ESlateSizeRule::Automatic, 20.f);

	UVerticalBox* Details = WidgetTree->ConstructWidget<UVerticalBox>();
	if (UVerticalBoxSlot* DetailsSlot = ExamCriteriaBox->AddChildToVerticalBox(Details))
	{
		DetailsSlot->SetPadding(FMargin(0.f, 0.f, 0.f, 14.f));
	}
	AddCriterionDetails(*Details, Criterion, 11);
	StationUi::SetShown(Details, false);

	UStationCriterionRow* Opener = NewObject<UStationCriterionRow>(this);
	Opener->Details = Details;
	Row->OnClicked.AddDynamic(Opener, &UStationCriterionRow::HandleClicked);
	ExamRows.Add(Opener);

	UBorder* Rule = WidgetTree->ConstructWidget<UBorder>();
	Rule->SetBrushColor(StationUi::PanelEdge);
	Rule->SetPadding(FMargin(0.f, 0.5f));
	ExamCriteriaBox->AddChild(Rule);
}

void UStationFeedbackWidget::HandleRestart()
{
	if (Flow)
	{
		Flow->Discard();
	}
}

#undef LOCTEXT_NAMESPACE
