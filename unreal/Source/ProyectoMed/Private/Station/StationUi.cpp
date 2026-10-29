#include "Station/StationUi.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/EditableTextBox.h"
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

FSlateBrush StationUi::RoundedBrush(const FLinearColor& Fill, float Radius, const FLinearColor& Outline, float OutlineWidth)
{
	FSlateBrush Brush;
	Brush.DrawAs = ESlateBrushDrawType::RoundedBox;
	Brush.TintColor = FSlateColor(Fill);
	Brush.OutlineSettings = FSlateBrushOutlineSettings(FVector4(Radius, Radius, Radius, Radius), FSlateColor(Outline), OutlineWidth);
	Brush.OutlineSettings.RoundingType = ESlateBrushRoundingType::FixedRadius;
	return Brush;
}

UBorder* StationUi::MakeRounded(UWidgetTree& Tree, const FLinearColor& Fill, float Radius, const FMargin& Padding,
	const FLinearColor& Outline, float OutlineWidth)
{
	UBorder* Box = Tree.ConstructWidget<UBorder>();
	Box->SetBrush(RoundedBrush(Fill, Radius, Outline, OutlineWidth));
	Box->SetPadding(Padding);
	return Box;
}

namespace
{
	void MakeFilled(UButton& Button, const FLinearColor& Fill, const FLinearColor& Hover)
	{
		FButtonStyle Style;
		Style.SetNormal(StationUi::RoundedBrush(Fill, 8.f));
		Style.SetHovered(StationUi::RoundedBrush(Hover, 8.f));
		Style.SetPressed(StationUi::RoundedBrush(Fill, 8.f));
		Style.SetDisabled(StationUi::RoundedBrush(StationUi::Raised, 8.f));
		Button.SetStyle(Style);
		Button.SetBackgroundColor(FLinearColor::White);
		if (UTextBlock* Label = Cast<UTextBlock>(Button.GetChildAt(0)))
		{
			Label->SetFont(FCoreStyle::GetDefaultFontStyle("Bold", 16));
		}
	}
}

void StationUi::MakePrimary(UButton& Button)
{
	MakeFilled(Button, Action, ActionHover);
}

void StationUi::MakeDanger(UButton& Button)
{
	MakeFilled(Button, Danger, DangerHover);
}

void StationUi::StyleInput(UEditableTextBox& Input)
{
	FEditableTextBoxStyle Style = Input.GetWidgetStyle();
	Style.SetBackgroundImageNormal(RoundedBrush(Raised, 8.f, PanelEdge, 1.f));
	Style.SetBackgroundImageHovered(RoundedBrush(Raised, 8.f, Quiet, 1.f));
	Style.SetBackgroundImageFocused(RoundedBrush(Raised, 8.f, Link, 1.f));
	Style.SetBackgroundImageReadOnly(RoundedBrush(Raised, 8.f, PanelEdge, 1.f));
	Style.SetFont(FCoreStyle::GetDefaultFontStyle("Regular", 16));
	Style.SetForegroundColor(FSlateColor(Ink));
	Style.SetPadding(FMargin(12.f, 9.f));
	Input.SetWidgetStyle(Style);
}

UButton* StationUi::MakeFlatButton(UWidgetTree& Tree, const FText& Label, int32 Size, const FLinearColor& Color, bool bBold)
{
	UButton* Button = Tree.ConstructWidget<UButton>();
	FButtonStyle Style;
	Style.SetNormal(RoundedBrush(FLinearColor::Transparent, 6.f));
	Style.SetHovered(RoundedBrush(FLinearColor(1.f, 1.f, 1.f, 0.08f), 6.f));
	Style.SetPressed(RoundedBrush(FLinearColor(1.f, 1.f, 1.f, 0.14f), 6.f));
	Style.SetNormalPadding(FMargin(0.f));
	Style.SetPressedPadding(FMargin(0.f));
	Button->SetStyle(Style);

	UTextBlock* Text = Tree.ConstructWidget<UTextBlock>();
	Text->SetText(Label);
	Text->SetFont(FCoreStyle::GetDefaultFontStyle(bBold ? "Bold" : "Regular", Size));
	Text->SetColorAndOpacity(FSlateColor(Color));
	Text->SetMargin(FMargin(6.f, 2.f));
	Button->AddChild(Text);
	return Button;
}

void StationUi::SetShown(UWidget* Widget, bool bShown)
{
	if (Widget)
	{
		Widget->SetVisibility(bShown ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	}
}
