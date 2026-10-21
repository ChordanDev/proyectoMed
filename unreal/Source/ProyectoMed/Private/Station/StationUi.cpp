#include "Station/StationUi.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/ScrollBox.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Components/Widget.h"
#include "Styling/CoreStyle.h"

UVerticalBox* StationUi::MakeCenteredCard(UWidgetTree& Tree, float MaxWidth, float MaxHeight, bool bScrollable)
{
	UBorder* Screen = Tree.ConstructWidget<UBorder>();
	Screen->SetBrushColor(Backdrop);
	Screen->SetHorizontalAlignment(HAlign_Center);
	Screen->SetVerticalAlignment(VAlign_Center);
	Tree.RootWidget = Screen;

	USizeBox* Size = Tree.ConstructWidget<USizeBox>();
	Size->SetMaxDesiredWidth(MaxWidth);
	Size->SetMaxDesiredHeight(MaxHeight);
	Screen->SetContent(Size);

	UBorder* CardBorder = Tree.ConstructWidget<UBorder>();
	CardBorder->SetBrushColor(Card);
	CardBorder->SetPadding(FMargin(40.f, 32.f));
	Size->SetContent(CardBorder);

	UVerticalBox* Column = Tree.ConstructWidget<UVerticalBox>();
	if (bScrollable)
	{
		UScrollBox* Scroll = Tree.ConstructWidget<UScrollBox>();
		CardBorder->SetContent(Scroll);
		Scroll->AddChild(Column);
	}
	else
	{
		CardBorder->SetContent(Column);
	}
	return Column;
}

UTextBlock* StationUi::AddText(UWidgetTree& Tree, UPanelWidget& Parent, const FText& Text, int32 Size,
	bool bBold, const FLinearColor& Color, float SpaceAbove)
{
	UTextBlock* Block = Tree.ConstructWidget<UTextBlock>();
	Block->SetText(Text);
	Block->SetFont(FCoreStyle::GetDefaultFontStyle(bBold ? "Bold" : "Regular", Size));
	Block->SetColorAndOpacity(FSlateColor(Color));
	Block->SetAutoWrapText(true);
	if (UVerticalBoxSlot* Slot = Cast<UVerticalBoxSlot>(Parent.AddChild(Block)))
	{
		Slot->SetPadding(FMargin(0.f, SpaceAbove, 0.f, 0.f));
	}
	return Block;
}

UButton* StationUi::AddButton(UWidgetTree& Tree, UPanelWidget& Parent, const FText& Label, float SpaceAbove)
{
	UButton* Button = Tree.ConstructWidget<UButton>();
	Button->SetBackgroundColor(Accent);

	UTextBlock* Text = Tree.ConstructWidget<UTextBlock>();
	Text->SetText(Label);
	Text->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 18));
	Text->SetColorAndOpacity(FSlateColor(Ink));
	Text->SetMargin(FMargin(16.f, 8.f));
	Button->AddChild(Text);

	if (UVerticalBoxSlot* Slot = Cast<UVerticalBoxSlot>(Parent.AddChild(Button)))
	{
		Slot->SetPadding(FMargin(0.f, SpaceAbove, 0.f, 0.f));
		Slot->SetHorizontalAlignment(HAlign_Left);
	}
	return Button;
}

void StationUi::SetShown(UWidget* Widget, bool bShown)
{
	if (Widget)
	{
		Widget->SetVisibility(bShown ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	}
}
