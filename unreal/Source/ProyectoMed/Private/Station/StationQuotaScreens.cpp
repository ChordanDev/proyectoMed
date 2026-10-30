#include "Station/StationQuotaScreens.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Button.h"
#include "Components/ButtonSlot.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/Overlay.h"
#include "Components/OverlaySlot.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Station/StationRunFlow.h"
#include "Station/StationUi.h"

#define LOCTEXT_NAMESPACE "StationQuotaScreens"

namespace
{
	/** The gap between the blocks of the column (docs/design/screens/html/Quota.dc.html). */
	constexpr float BlockGap = 26.f;
	constexpr float ColumnWidth = 660.f;
	/** 1.08 of the font's size, over Manrope's own line height. */
	constexpr float TitleLineHeight = 0.79f;
	/** The space `StationUi` leaves on each side of a button's label. */
	constexpr float LabelSideSpace = 24.f;
	/** Between a button's label and the arrow after it. */
	constexpr float ArrowGap = 8.f;

	UTextBlock* MakeQuotaText(UWidgetTree& Tree, const FText& Text, FName Weight, float Pixels, const FLinearColor& Color,
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

	void AddBlock(UVerticalBox& Column, UWidget* Block)
	{
		if (UVerticalBoxSlot* Slot = Column.AddChildToVerticalBox(Block))
		{
			Slot->SetPadding(FMargin(0.f, Column.GetChildrenCount() > 1 ? BlockGap : 0.f, 0.f, 0.f));
		}
	}

	/** The scrim, the wordmark and, in the bottom-left corner, the column with these three lines. */
	UVerticalBox* BuildScreen(UWidgetTree& Tree, const FText& Eyebrow, const FText& Title, const FText& Body)
	{
		UOverlay* Screen = Tree.ConstructWidget<UOverlay>();
		Tree.RootWidget = Screen;
		if (UOverlaySlot* ScrimSlot = Screen->AddChildToOverlay(StationUi::MakeScrim(Tree)))
		{
			ScrimSlot->SetHorizontalAlignment(HAlign_Fill);
			ScrimSlot->SetVerticalAlignment(VAlign_Fill);
		}

		UHorizontalBox* Wordmark = Tree.ConstructWidget<UHorizontalBox>();
		Wordmark->AddChild(MakeQuotaText(Tree, LOCTEXT("WordmarkFirst", "Proyecto"), StationUi::FontExtraBold, 26.f, StationUi::InkTitle, -15));
		Wordmark->AddChild(MakeQuotaText(Tree, LOCTEXT("WordmarkSecond", "Med"), StationUi::FontExtraBold, 26.f, StationUi::TreinoAccent, -15));
		if (UOverlaySlot* BrandSlot = Screen->AddChildToOverlay(Wordmark))
		{
			BrandSlot->SetHorizontalAlignment(HAlign_Left);
			BrandSlot->SetVerticalAlignment(VAlign_Top);
			BrandSlot->SetPadding(FMargin(96.f, 80.f, 0.f, 0.f));
		}

		USizeBox* Width = Tree.ConstructWidget<USizeBox>();
		Width->SetWidthOverride(ColumnWidth);
		UVerticalBox* Column = Tree.ConstructWidget<UVerticalBox>();
		Width->SetContent(Column);
		if (UOverlaySlot* ColumnSlot = Screen->AddChildToOverlay(Width))
		{
			ColumnSlot->SetHorizontalAlignment(HAlign_Left);
			ColumnSlot->SetVerticalAlignment(VAlign_Bottom);
			ColumnSlot->SetPadding(FMargin(96.f, 0.f, 0.f, 96.f));
		}

		UTextBlock* EyebrowText = MakeQuotaText(Tree, Eyebrow, StationUi::FontBold, 13.f, StationUi::Muted, 120);
		EyebrowText->SetTextTransformPolicy(ETextTransformPolicy::ToUpper);
		AddBlock(*Column, EyebrowText);

		UTextBlock* TitleText = MakeQuotaText(Tree, Title, StationUi::FontBold, 56.f, StationUi::InkTitle, -25);
		TitleText->SetAutoWrapText(true);
		TitleText->SetLineHeightPercentage(TitleLineHeight);
		AddBlock(*Column, TitleText);

		UTextBlock* BodyText = MakeQuotaText(Tree, Body, StationUi::FontMedium, 18.f, StationUi::InkBody);
		BodyText->SetAutoWrapText(true);
		AddBlock(*Column, BodyText);
		return Column;
	}

	/** The row of a primary and a secondary button. */
	void AddActions(UWidgetTree& Tree, UVerticalBox& Column, const FText& Primary, const FText& Secondary,
		UButton*& OutPrimary, UButton*& OutSecondary)
	{
		UHorizontalBox* Row = Tree.ConstructWidget<UHorizontalBox>();
		AddBlock(Column, Row);
		OutPrimary = StationUi::AddButton(Tree, *Row, Primary, 0.f);
		OutSecondary = StationUi::AddButton(Tree, *Row, Secondary, 0.f);
		StationUi::MakeSecondary(*OutSecondary);
		if (UHorizontalBoxSlot* SecondarySlot = Cast<UHorizontalBoxSlot>(OutSecondary->Slot))
		{
			SecondarySlot->SetPadding(FMargin(16.f, 0.f, 0.f, 0.f));
		}
	}

	/**
	 * Ends the label of `Button` in the arrow of a link that leaves the app. Manrope has
	 * no `↗`, so it is its `→` turned up.
	 */
	void AddLeavingArrow(UWidgetTree& Tree, UButton& Button)
	{
		UTextBlock* Label = Cast<UTextBlock>(Button.GetChildAt(0));
		if (!Label)
		{
			return;
		}

		UTextBlock* Arrow = Tree.ConstructWidget<UTextBlock>();
		Arrow->SetText(FText::FromString(TEXT("→")));
		Arrow->SetFont(Label->GetFont());
		Arrow->SetColorAndOpacity(FSlateColor::UseForeground());
		Arrow->SetRenderTransformAngle(-45.f);

		Button.RemoveChildAt(0);
		UHorizontalBox* Row = Tree.ConstructWidget<UHorizontalBox>();
		Row->AddChild(Label);
		if (UHorizontalBoxSlot* ArrowSlot = Row->AddChildToHorizontalBox(Arrow))
		{
			ArrowSlot->SetVerticalAlignment(VAlign_Center);
			// The label keeps its side space, which the arrow takes over.
			ArrowSlot->SetPadding(FMargin(ArrowGap - LabelSideSpace, 0.f, LabelSideSpace, 0.f));
		}
		if (UButtonSlot* RowSlot = Cast<UButtonSlot>(Button.AddChild(Row)))
		{
			RowSlot->SetPadding(FMargin(0.f));
		}
	}
}

FText FormatDailyQuotaTimeLeft(const FTimespan& Left)
{
	const int32 Minutes = FMath::Max(0, FMath::CeilToInt32(Left.GetTotalMinutes()));
	return Minutes < 60
		? FText::Format(LOCTEXT("QuotaMinutes", "{0} min"), Minutes)
		: FText::Format(LOCTEXT("QuotaHoursMinutes", "{0} h {1} min"), Minutes / 60, Minutes % 60);
}

FString StationPlansUrl(const FString& PhoenixBaseUrl)
{
	return PhoenixBaseUrl + TEXT("/planos");
}

TSharedRef<SWidget> UStationQuotaWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UVerticalBox* Column = BuildScreen(*WidgetTree,
			LOCTEXT("QuotaEyebrow", "Simulações de hoje"),
			LOCTEXT("QuotaTitle", "Você usou todas as simulações de hoje."),
			LOCTEXT("QuotaBody", "A cota renova à meia-noite (horário de Brasília)."));

		UHorizontalBox* Row = WidgetTree->ConstructWidget<UHorizontalBox>();
		Countdown = Row;
		AddBlock(*Column, Row);
		TimeLeftText = MakeQuotaText(*WidgetTree, FText::GetEmpty(), StationUi::FontExtraBold, 44.f, StationUi::Ink);
		Row->AddChild(TimeLeftText);
		if (UHorizontalBoxSlot* NoteSlot = Row->AddChildToHorizontalBox(
				MakeQuotaText(*WidgetTree, LOCTEXT("QuotaToRenew", "para renovar"), StationUi::FontMedium, 14.f, StationUi::Muted)))
		{
			NoteSlot->SetVerticalAlignment(VAlign_Bottom);
			NoteSlot->SetPadding(FMargin(12.f, 0.f, 0.f, 8.f));
		}

		UButton* History = nullptr;
		UButton* Menu = nullptr;
		AddActions(*WidgetTree, *Column, LOCTEXT("QuotaHistory", "Revisar o histórico"),
			LOCTEXT("BackToMenu", "Voltar ao menu"), History, Menu);
		HistoryButton = History;
		HistoryButton->SetIsEnabled(false);
		MenuButton = Menu;
		MenuButton->OnClicked.AddDynamic(this, &UStationQuotaWidget::HandleBackToMenu);
	}
	return Super::RebuildWidget();
}

void UStationQuotaWidget::NativeTick(const FGeometry& MyGeometry, float InDeltaTime)
{
	Super::NativeTick(MyGeometry, InDeltaTime);
	Refresh();
}

void UStationQuotaWidget::Refresh()
{
	if (!Flow || !Countdown || !TimeLeftText)
	{
		return;
	}
	const FTimespan Left = Flow->GetDailyQuotaTimeLeft();
	StationUi::SetShown(Countdown, Left > FTimespan::Zero());
	const FText Text = FormatDailyQuotaTimeLeft(Left);
	if (!TimeLeftText->GetText().EqualTo(Text))
	{
		TimeLeftText->SetText(Text);
	}
}

void UStationQuotaWidget::HandleBackToMenu()
{
	OnBackToMenu.ExecuteIfBound();
}

TSharedRef<SWidget> UStationSubscriptionWidget::RebuildWidget()
{
	if (WidgetTree && !WidgetTree->RootWidget)
	{
		UVerticalBox* Column = BuildScreen(*WidgetTree,
			LOCTEXT("SubscriptionEyebrow", "Assinatura"),
			LOCTEXT("SubscriptionTitle", "Assine para fazer estações"),
			LOCTEXT("SubscriptionBody", "Sua conta não tem uma assinatura ativa. Assine no site e volte para o aplicativo."));

		UButton* Plans = nullptr;
		UButton* Menu = nullptr;
		AddActions(*WidgetTree, *Column, LOCTEXT("SubscriptionPlans", "Ver planos no site"),
			LOCTEXT("BackToMenu", "Voltar ao menu"), Plans, Menu);
		AddLeavingArrow(*WidgetTree, *Plans);
		PlansButton = Plans;
		PlansButton->OnClicked.AddDynamic(this, &UStationSubscriptionWidget::HandleOpenPlans);
		MenuButton = Menu;
		MenuButton->OnClicked.AddDynamic(this, &UStationSubscriptionWidget::HandleBackToMenu);
	}
	return Super::RebuildWidget();
}

void UStationSubscriptionWidget::HandleOpenPlans()
{
	OnOpenPlans.ExecuteIfBound();
}

void UStationSubscriptionWidget::HandleBackToMenu()
{
	OnBackToMenu.ExecuteIfBound();
}

#undef LOCTEXT_NAMESPACE
