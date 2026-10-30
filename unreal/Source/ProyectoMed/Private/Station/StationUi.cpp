#include "Station/StationUi.h"

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/ButtonSlot.h"
#include "Components/EditableTextBox.h"
#include "Components/HorizontalBox.h"
#include "Components/HorizontalBoxSlot.h"
#include "Components/NativeWidgetHost.h"
#include "Components/ScrollBox.h"
#include "Components/SizeBox.h"
#include "Components/SizeBoxSlot.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Components/VerticalBoxSlot.h"
#include "Components/Widget.h"
#include "Engine/Font.h"
#include "Rendering/DrawElements.h"
#include "Styling/CoreStyle.h"
#include "Widgets/SLeafWidget.h"

DEFINE_LOG_CATEGORY_STATIC(LogStationUi, Log, All);

FSlateFontInfo StationUi::Font(FName Weight, int32 Size)
{
	static const TCHAR* const ManropePath = TEXT("/Game/Station/UI/Fonts/Manrope.Manrope");
	if (const UFont* Manrope = LoadObject<UFont>(nullptr, ManropePath))
	{
		return FSlateFontInfo(Manrope, Size, Weight);
	}
	UE_LOG(LogStationUi, Warning, TEXT("%s is missing; falling back to the engine's font."), ManropePath);
	return FCoreStyle::GetDefaultFontStyle(Weight, Size);
}

FSlateFontInfo StationUi::MockupFont(FName Weight, float Pixels)
{
	FSlateFontInfo Info = Font(Weight, 0);
	Info.Size = Pixels * 0.75f;
	return Info;
}

UVerticalBox* StationUi::MakeCenteredCard(UWidgetTree& Tree, float MaxWidth, float MaxHeight)
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
	CardBorder->SetBrush(RoundedBrush(Panel, 12.f, PanelEdge, 1.f));
	CardBorder->SetPadding(FMargin(40.f, 32.f));
	Size->SetContent(CardBorder);

	UVerticalBox* Column = Tree.ConstructWidget<UVerticalBox>();
	CardBorder->SetContent(Column);
	return Column;
}

UVerticalBox* StationUi::MakeFooterCard(UWidgetTree& Tree, float MaxWidth, float MaxHeight, UVerticalBox*& OutFooter)
{
	UVerticalBox* Card = MakeCenteredCard(Tree, MaxWidth, MaxHeight);
	UScrollBox* Scroll = Tree.ConstructWidget<UScrollBox>();
	if (UVerticalBoxSlot* ScrollSlot = Card->AddChildToVerticalBox(Scroll))
	{
		ScrollSlot->SetSize(FSlateChildSize(ESlateSizeRule::Fill));
	}
	UVerticalBox* Column = Tree.ConstructWidget<UVerticalBox>();
	Scroll->AddChild(Column);

	OutFooter = Tree.ConstructWidget<UVerticalBox>();
	if (UVerticalBoxSlot* FooterSlot = Card->AddChildToVerticalBox(OutFooter))
	{
		FooterSlot->SetPadding(FMargin(0.f, 18.f, 0.f, 0.f));
	}
	UBorder* Rule = Tree.ConstructWidget<UBorder>();
	Rule->SetBrushColor(PanelEdge);
	Rule->SetPadding(FMargin(0.f, 0.5f));
	OutFooter->AddChild(Rule);
	return Column;
}

UTextBlock* StationUi::AddText(UWidgetTree& Tree, UPanelWidget& Parent, const FText& Text, int32 Size,
	bool bBold, const FLinearColor& Color, float SpaceAbove)
{
	UTextBlock* Block = Tree.ConstructWidget<UTextBlock>();
	Block->SetText(Text);
	Block->SetFont(Font(bBold ? FontBold : FontRegular, Size));
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
	UTextBlock* Text = Tree.ConstructWidget<UTextBlock>();
	Text->SetText(Label);
	Button->AddChild(Text);
	MakePrimary(*Button);

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
	constexpr float ButtonRadius = 8.f;
	/** Above and below a button's label: with the line, the mockups' 52 px, or 44 px for a ghost. */
	constexpr float ButtonLabelSpace = 15.f;
	constexpr float GhostLabelSpace = 12.f;
	constexpr float EnterArrowSize = 60.f;
	/** A disabled button in the mockups. */
	constexpr float DisabledOpacity = 0.45f;
	constexpr float FocusRingWidth = 2.f;

	/** What one kind of button looks like. */
	struct FButtonLook
	{
		FLinearColor Fill = FLinearColor::Transparent;
		FLinearColor HoverFill = FLinearColor::Transparent;
		FLinearColor Label = StationUi::Ink;
		FLinearColor HoverLabel = StationUi::Ink;
		FLinearColor Outline = FLinearColor::Transparent;
		FLinearColor HoverOutline = FLinearColor::Transparent;
		float OutlineWidth = 0.f;
		float Radius = ButtonRadius;
	};

	/** The mockups' hover: CSS `brightness(1.1)`, which works on the sRGB values. */
	FLinearColor Brighter(const FLinearColor& Color)
	{
		const FColor Base = Color.ToFColor(true);
		const auto Channel = [](uint8 Value) { return static_cast<uint8>(FMath::Min(FMath::RoundToInt(Value * 1.1f), 255)); };
		return FLinearColor(FColor(Channel(Base.R), Channel(Base.G), Channel(Base.B)));
	}

	FButtonLook Filled(const FLinearColor& Fill, const FLinearColor& Label)
	{
		FButtonLook Look;
		Look.Fill = Fill;
		Look.HoverFill = Brighter(Fill);
		Look.Label = Label;
		Look.HoverLabel = Label;
		return Look;
	}

	FLinearColor Faded(const FLinearColor& Color)
	{
		return Color.CopyWithNewOpacity(Color.A * DisabledOpacity);
	}

	FButtonStyle StyleFor(const FButtonLook& Look)
	{
		FButtonStyle Style;
		Style.SetNormal(StationUi::RoundedBrush(Look.Fill, Look.Radius, Look.Outline, Look.OutlineWidth));
		Style.SetHovered(StationUi::RoundedBrush(Look.HoverFill, Look.Radius, Look.HoverOutline, Look.OutlineWidth));
		Style.SetPressed(StationUi::RoundedBrush(Look.Fill, Look.Radius, Look.Outline, Look.OutlineWidth));
		Style.SetDisabled(StationUi::RoundedBrush(Faded(Look.Fill), Look.Radius, Faded(Look.Outline), Look.OutlineWidth));
		Style.SetNormalForeground(FSlateColor(Look.Label));
		Style.SetHoveredForeground(FSlateColor(Look.HoverLabel));
		Style.SetPressedForeground(FSlateColor(Look.Label));
		Style.SetDisabledForeground(FSlateColor(Faded(Look.Label)));
		Style.SetNormalPadding(FMargin(0.f));
		Style.SetPressedPadding(FMargin(0.f));
		return Style;
	}

	/** `Style` with the mockups' white outline around all the states the keyboard can reach. */
	FButtonStyle WithFocusRing(FButtonStyle Style)
	{
		for (FSlateBrush* Brush : {&Style.Normal, &Style.Hovered, &Style.Pressed})
		{
			Brush->OutlineSettings.Color = FSlateColor(StationUi::InkTitle);
			Brush->OutlineSettings.Width = FocusRingWidth;
		}
		return Style;
	}

	/**
	 * Applies `Style` and rings the button while the keyboard has it. Slate's own focus
	 * mark is a faint dashed box; a click focuses too, but like CSS's `:focus-visible`,
	 * only the keyboard asks where the focus went.
	 */
	void ApplyWithFocusRing(UButton& Button, const FButtonStyle& Style)
	{
		Button.SetStyle(Style);
		const TWeakObjectPtr<UButton> Weak(&Button);
		Button.OnReceivedFocus.BindLambda([Weak, Style]()
		{
			if (UButton* Focused = Weak.Get())
			{
				const TSharedPtr<SWidget> Slate = Focused->GetCachedWidget();
				const TOptional<EFocusCause> Cause = Slate ? Slate->HasAnyUserFocus() : TOptional<EFocusCause>();
				if (Cause.Get(EFocusCause::Navigation) != EFocusCause::Mouse)
				{
					Focused->SetStyle(WithFocusRing(Style));
				}
			}
		});
		Button.OnLostFocus.BindLambda([Weak, Style]()
		{
			if (UButton* Blurred = Weak.Get())
			{
				Blurred->SetStyle(Style);
			}
		});
	}

	void MakeLabelled(UButton& Button, const FButtonLook& Look, FName Weight = StationUi::FontBold, float Pixels = 16.f,
		float SideSpace = 24.f, float LabelSpace = ButtonLabelSpace)
	{
		ApplyWithFocusRing(Button, StyleFor(Look));
		Button.SetBackgroundColor(FLinearColor::White);
		if (UTextBlock* Label = Cast<UTextBlock>(Button.GetChildAt(0)))
		{
			Label->SetFont(StationUi::MockupFont(Weight, Pixels));
			Label->SetColorAndOpacity(FSlateColor::UseForeground());
			Label->SetMargin(FMargin(SideSpace, LabelSpace));
			if (UButtonSlot* LabelSlot = Cast<UButtonSlot>(Label->Slot))
			{
				LabelSlot->SetPadding(FMargin(0.f));
			}
		}
	}

	/** The left-to-right gradient that Slate has no brush for. */
	class SStationScrim : public SLeafWidget
	{
	public:
		SLATE_BEGIN_ARGS(SStationScrim) {}
		SLATE_END_ARGS()

		void Construct(const FArguments&) {}

		virtual int32 OnPaint(const FPaintArgs&, const FGeometry& Geometry, const FSlateRect&,
			FSlateWindowElementList& OutElements, int32 LayerId, const FWidgetStyle& Style, bool bParentEnabled) const override
		{
			const float Width = Geometry.GetLocalSize().X;
			TArray<FSlateGradientStop> Stops;
			for (const StationUi::FScrimStop& Stop : StationUi::ScrimStops)
			{
				Stops.Emplace(FVector2f(Width * Stop.Position, 0.f), StationUi::ScrimColor.CopyWithNewOpacity(Stop.Opacity));
			}
			FSlateDrawElement::MakeGradient(OutElements, LayerId, Geometry.ToPaintGeometry(), MoveTemp(Stops), Orient_Vertical,
				ShouldBeEnabled(bParentEnabled) ? ESlateDrawEffect::None : ESlateDrawEffect::DisabledEffect);
			return LayerId;
		}

		virtual FVector2D ComputeDesiredSize(float) const override
		{
			return FVector2D::ZeroVector;
		}
	};
}

void StationUi::MakePrimary(UButton& Button)
{
	MakeLabelled(Button, Filled(TreinoAccent, InkOnAccent));
}

void StationUi::MakeExam(UButton& Button)
{
	MakeLabelled(Button, Filled(ProvaAccent, InkOnAccent));
}

void StationUi::MakeDanger(UButton& Button)
{
	MakeLabelled(Button, Filled(Danger, InkTitle));
}

void StationUi::MakeSecondary(UButton& Button)
{
	FButtonLook Look;
	Look.Outline = ControlEdge;
	Look.HoverOutline = Ink;
	Look.OutlineWidth = 1.f;
	MakeLabelled(Button, Look);
}

void StationUi::MakeGhost(UButton& Button)
{
	FButtonLook Look;
	Look.Label = Muted;
	Look.HoverLabel = InkTitle;
	MakeLabelled(Button, Look, FontSemiBold, 15.f, 0.f, GhostLabelSpace);
}

void StationUi::MakeRow(UButton& Button)
{
	FButtonLook Look;
	Look.HoverFill = Raised;
	Look.Radius = 4.f;
	MakeLabelled(Button, Look, FontRegular, 15, 0.f);
}

UButton* StationUi::MakeEnterArrow(UWidgetTree& Tree, const FLinearColor& Accent)
{
	UButton* Button = Tree.ConstructWidget<UButton>();
	FButtonLook Look = Filled(Accent, InkOnAccent);
	Look.Radius = EnterArrowSize / 2.f;
	ApplyWithFocusRing(*Button, StyleFor(Look));
	Button->SetBackgroundColor(FLinearColor::White);

	USizeBox* Size = Tree.ConstructWidget<USizeBox>();
	Size->SetWidthOverride(EnterArrowSize);
	Size->SetHeightOverride(EnterArrowSize);
	if (UButtonSlot* Slot = Cast<UButtonSlot>(Button->AddChild(Size)))
	{
		Slot->SetPadding(FMargin(0.f));
	}
	UTextBlock* Arrow = Tree.ConstructWidget<UTextBlock>();
	Arrow->SetText(FText::FromString(TEXT("→")));
	Arrow->SetFont(MockupFont(FontBold, 26.f));
	Arrow->SetColorAndOpacity(FSlateColor::UseForeground());
	if (USizeBoxSlot* ArrowSlot = Cast<USizeBoxSlot>(Size->AddChild(Arrow)))
	{
		ArrowSlot->SetHorizontalAlignment(HAlign_Center);
		ArrowSlot->SetVerticalAlignment(VAlign_Center);
	}
	return Button;
}

UButton* StationUi::MakeContentButton(UWidgetTree& Tree, UWidget& Content, const FMargin& RingSpace)
{
	UButton* Button = Tree.ConstructWidget<UButton>();
	FButtonLook Look;
	Look.Radius = 6.f;
	ApplyWithFocusRing(*Button, StyleFor(Look));
	Button->SetBackgroundColor(FLinearColor::White);
	if (UButtonSlot* Slot = Cast<UButtonSlot>(Button->AddChild(&Content)))
	{
		Slot->SetPadding(RingSpace);
		Slot->SetHorizontalAlignment(HAlign_Fill);
		Slot->SetVerticalAlignment(VAlign_Fill);
	}
	return Button;
}

UWidget* StationUi::MakeScrim(UWidgetTree& Tree)
{
	UNativeWidgetHost* Host = Tree.ConstructWidget<UNativeWidgetHost>();
	Host->SetContent(SNew(SStationScrim));
	Host->SetVisibility(ESlateVisibility::HitTestInvisible);
	return Host;
}

UWidget* StationUi::MakeModeMark(UWidgetTree& Tree, const FLinearColor& Accent)
{
	USizeBox* Size = Tree.ConstructWidget<USizeBox>();
	Size->SetWidthOverride(32.f);
	Size->SetHeightOverride(4.f);
	Size->SetContent(MakeRounded(Tree, Accent, 2.f, FMargin(0.f)));
	return Size;
}

UBorder* StationUi::MakeChip(UWidgetTree& Tree, const FText& Label)
{
	UBorder* Chip = MakeRounded(Tree, FLinearColor::Transparent, 16.f, FMargin(12.f, 6.f), ChipEdge, 1.f);
	UTextBlock* Text = Tree.ConstructWidget<UTextBlock>();
	Text->SetText(Label);
	Text->SetFont(MockupFont(FontSemiBold, 13.f));
	Text->SetColorAndOpacity(FSlateColor(InkLabel));
	Chip->SetContent(Text);
	return Chip;
}

UBorder* StationUi::MakePanel(UWidgetTree& Tree, const FMargin& Padding)
{
	return MakeRounded(Tree, Panel, 12.f, Padding, PanelEdge, 1.f);
}

UHorizontalBox* StationUi::MakeKeyHint(UWidgetTree& Tree, const FText& Key, const FText& Action)
{
	UHorizontalBox* Hint = Tree.ConstructWidget<UHorizontalBox>();
	USizeBox* Size = Tree.ConstructWidget<USizeBox>();
	Size->SetMinDesiredWidth(26.f);
	Size->SetMinDesiredHeight(26.f);
	UBorder* Cap = MakeRounded(Tree, FLinearColor::Transparent, 5.f, FMargin(7.f, 0.f), ControlEdge, 1.f);
	Cap->SetHorizontalAlignment(HAlign_Center);
	Cap->SetVerticalAlignment(VAlign_Center);
	UTextBlock* KeyName = Tree.ConstructWidget<UTextBlock>();
	KeyName->SetText(Key);
	KeyName->SetFont(MockupFont(FontBold, 12.f));
	KeyName->SetColorAndOpacity(FSlateColor(InkLabel));
	Cap->SetContent(KeyName);
	Size->SetContent(Cap);
	if (UHorizontalBoxSlot* CapSlot = Hint->AddChildToHorizontalBox(Size))
	{
		CapSlot->SetVerticalAlignment(VAlign_Center);
	}

	UTextBlock* What = Tree.ConstructWidget<UTextBlock>();
	What->SetText(Action);
	What->SetFont(MockupFont(FontMedium, 13.f));
	What->SetColorAndOpacity(FSlateColor(InkHint));
	if (UHorizontalBoxSlot* WhatSlot = Hint->AddChildToHorizontalBox(What))
	{
		WhatSlot->SetVerticalAlignment(VAlign_Center);
		WhatSlot->SetPadding(FMargin(8.f, 0.f, 0.f, 0.f));
	}
	return Hint;
}

void StationUi::StyleInput(UEditableTextBox& Input)
{
	FEditableTextBoxStyle Style = Input.GetWidgetStyle();
	Style.SetBackgroundImageNormal(RoundedBrush(Raised, 8.f, PanelEdge, 1.f));
	Style.SetBackgroundImageHovered(RoundedBrush(Raised, 8.f, Quiet, 1.f));
	Style.SetBackgroundImageFocused(RoundedBrush(Raised, 8.f, Link, 1.f));
	Style.SetBackgroundImageReadOnly(RoundedBrush(Raised, 8.f, PanelEdge, 1.f));
	Style.SetFont(Font(FontRegular, 16));
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
	ApplyWithFocusRing(*Button, Style);

	UTextBlock* Text = Tree.ConstructWidget<UTextBlock>();
	Text->SetText(Label);
	Text->SetFont(Font(bBold ? FontBold : FontRegular, Size));
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
