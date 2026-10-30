// Small builders for the station's native UMG screens, which are assembled in
// C++ so they review as text and need no binary widget assets.

#pragma once

#include "CoreMinimal.h"
#include "Components/SlateWrapperTypes.h"
#include "Fonts/SlateFontInfo.h"
#include "Styling/SlateBrush.h"

class UBorder;
class UButton;
class UEditableTextBox;
class UHorizontalBox;
class UPanelWidget;
class UTextBlock;
class UVerticalBox;
class UWidget;
class UWidgetTree;

namespace StationUi
{
	// The Cine palette (docs/design/screens/html/cine.css). Given as sRGB, like the
	// mockups it comes from. Only the panels are see-through; what the learner reads
	// or types on them (bubbles, inputs, exam cards, the document's sheet) keeps an
	// opaque surface of its own (#444).

	// Ink: text on the scrim, from the title down to what recedes.
	const FLinearColor InkTitle(FColor(0xFF, 0xFF, 0xFF));
	const FLinearColor Ink(FColor(0xE8, 0xEE, 0xF2));
	const FLinearColor InkBody(FColor(0xC9, 0xD4, 0xDB));
	const FLinearColor Muted(FColor(0xA9, 0xB7, 0xC1));
	const FLinearColor Link = Ink;
	/** On a filled accent: the Treino and Prova simulada buttons and the enter arrow. */
	const FLinearColor InkOnAccent(FColor(0x0B, 0x11, 0x16));
	/** The labels of chips and keyboard hints. */
	const FLinearColor InkLabel(FColor(0xDF, 0xE7, 0xEC));
	const FLinearColor InkHint(FColor(0xB9, 0xC6, 0xCF));

	// One accent per mode, in its marks and buttons.
	const FLinearColor TreinoAccent(FColor(0x5F, 0xD0, 0xBF));
	const FLinearColor ProvaAccent(FColor(0xF2, 0xA6, 0x5A));
	/** A warning in a Prova simulada's panels, softer than its accent. */
	const FLinearColor ProvaWarning(FColor(0xF2, 0xC8, 0x9A));

	// Danger: finishing the station, and failures.
	const FLinearColor Danger(FColor(0xC2, 0x41, 0x3A));
	const FLinearColor DangerInk(FColor(0xFF, 0x8A, 0x7A));

	/** The colour of every scrim; each one only changes how much of it covers the scene. */
	const FLinearColor ScrimColor(FColor(0x09, 0x0D, 0x11));
	/** Behind a centred card: the scene barely shows. */
	const FLinearColor Backdrop = ScrimColor.CopyWithNewOpacity(0.88f);

	/** Where a stop of the left-to-right scrim sits, as a share of its width, and how much it covers. */
	struct FScrimStop
	{
		float Position;
		float Opacity;
	};
	inline constexpr FScrimStop ScrimStops[] = {{0.f, 0.92f}, {0.34f, 0.74f}, {0.64f, 0.f}, {1.f, 0.f}};

	const FLinearColor PanelSolid(FColor(0x0C, 0x11, 0x16));
	const FLinearColor Panel = PanelSolid.CopyWithNewOpacity(0.84f);
	/** How much of the in-run HUD's panels covers the scene behind them; tune it here (#444). */
	const float HudPanelOpacity = 0.6f;
	/** The in-run HUD's panels: the top bar, the conversation and the exam drawer. */
	const FLinearColor HudPanel = Panel.CopyWithNewOpacity(HudPanelOpacity);
	const FLinearColor PanelEdge(FColor(0x2F, 0x3D, 0x48));
	/** The outlines of the secondary button and the keyboard hint. */
	const FLinearColor ControlEdge(FColor(0x5A, 0x6A, 0x76));
	const FLinearColor ChipEdge(FColor(0x4A, 0x5A, 0x66));
	const FLinearColor Raised(FColor(0x1D, 0x28, 0x33));
	const FLinearColor RaisedHover(FColor(0x2F, 0x3D, 0x48));
	const FLinearColor Quiet(FColor(0x8D, 0x9C, 0xA7));
	const FLinearColor Paper(FColor(0xF6, 0xF3, 0xEC));
	const FLinearColor PaperInk(FColor(0x1D, 0x28, 0x33));
	const FLinearColor PaperMuted(FColor(0x5F, 0x5E, 0x5A));
	const FLinearColor PaperEdge(FColor(0xD3, 0xD1, 0xC7));

	const FLinearColor Caution(0.95f, 0.66f, 0.22f, 1.f);
	const FLinearColor LearnerBubble(FColor(0x0C, 0x44, 0x7C));
	const FLinearColor Recording(FColor(0xE2, 0x4B, 0x4A));
	const FLinearColor RecordingInk(FColor(0xF7, 0xC1, 0xC1));

	// The status labels of the exam requests.
	const FLinearColor ReleasedFill(FColor(0x27, 0x50, 0x0A));
	const FLinearColor ReleasedInk(FColor(0xC0, 0xDD, 0x97));
	const FLinearColor DeclinedFill(FColor(0x63, 0x38, 0x06));
	const FLinearColor DeclinedInk(FColor(0xFA, 0xC7, 0x75));
	/** A status that is neither good nor bad news: still waiting, or released before. */
	const FLinearColor NeutralFill(FColor(0x44, 0x44, 0x41));
	const FLinearColor NeutralInk(FColor(0xD3, 0xD1, 0xC7));

	// The fills of the main menu's mode cards (#421), until the Cine menu replaces them (#456).
	const FLinearColor TrainingFill(FColor(0x14, 0x36, 0x5C));
	const FLinearColor TrainingHover(FColor(0x1B, 0x47, 0x77));
	const FLinearColor ExamFill(FColor(0x4E, 0x2A, 0x0C));
	const FLinearColor ExamHover(FColor(0x66, 0x37, 0x12));
	/** Behind the main menu until the doctor's office shows there (#431). */
	const FLinearColor MenuBackdrop(FColor(0x0E, 0x24, 0x40));

	/** Every weight of Manrope the mockups use, named as the typefaces of its font asset. */
	inline const FName FontRegular(TEXT("Regular"));
	inline const FName FontMedium(TEXT("Medium"));
	inline const FName FontSemiBold(TEXT("SemiBold"));
	inline const FName FontBold(TEXT("Bold"));
	inline const FName FontExtraBold(TEXT("ExtraBold"));

	/** Manrope in `Weight`, one of the names above. */
	FSlateFontInfo Font(FName Weight, int32 Size);

	/** A rounded box of `Fill`, outlined in `Outline` when `OutlineWidth` is above 0. */
	FSlateBrush RoundedBrush(const FLinearColor& Fill, float Radius,
		const FLinearColor& Outline = FLinearColor::Transparent, float OutlineWidth = 0.f);

	/** A border painted with `RoundedBrush`. */
	UBorder* MakeRounded(UWidgetTree& Tree, const FLinearColor& Fill, float Radius, const FMargin& Padding,
		const FLinearColor& Outline = FLinearColor::Transparent, float OutlineWidth = 0.f);

	// Restyling a button from `AddButton`: at least 44 px tall, with a white ring
	// while the keyboard has it. It stays the one `AddButton` returned, so its slot
	// and handlers are kept.

	/** The panel's main action, in the Treino accent. `AddButton` starts here. */
	void MakePrimary(UButton& Button);

	/** The main action of a Prova simulada, in its accent. */
	void MakeExam(UButton& Button);

	/** A red button, for ending the run. */
	void MakeDanger(UButton& Button);

	/** Outlined and empty, a quieter alternative to the primary one. */
	void MakeSecondary(UButton& Button);

	/** Only its label, muted until hovered: for what sits beside the main actions. */
	void MakeGhost(UButton& Button);

	/** A whole row of a list as one button: only its own content shows, on a lighter ground while hovered. */
	void MakeRow(UButton& Button);

	/** The round button that enters a mode, in that mode's `Accent`. */
	UButton* MakeEnterArrow(UWidgetTree& Tree, const FLinearColor& Accent);

	/**
	 * Darkens the scene behind text, from the left edge to clear past the middle. Goes
	 * full screen under the text, in an overlay; the pointer passes through it.
	 */
	UWidget* MakeScrim(UWidgetTree& Tree);

	/**
	 * The 32x4 bar in the mode's `Accent` before every mode title. Give its slot a
	 * centred vertical alignment: a filling slot would stretch it.
	 */
	UWidget* MakeModeMark(UWidgetTree& Tree, const FLinearColor& Accent);

	/** A short fact in an outlined pill. */
	UBorder* MakeChip(UWidgetTree& Tree, const FText& Label);

	/** A panel's surface, see-through and outlined. */
	UBorder* MakePanel(UWidgetTree& Tree, const FMargin& Padding);

	/** What a key does: `Key` (`Espaço`, `Enter`, `Esc`) in its keycap, then `Action`. */
	UHorizontalBox* MakeKeyHint(UWidgetTree& Tree, const FText& Key, const FText& Action);

	/** A dark, rounded text box that matches the side panels. */
	void StyleInput(UEditableTextBox& Input);

	/** A button with no box of its own: only its content shows, lighter while hovered. */
	UButton* MakeFlatButton(UWidgetTree& Tree, const FText& Label, int32 Size, const FLinearColor& Color, bool bBold = false);

	/**
	 * A full-screen dimmed backdrop that centers one card of at most `MaxWidth`, in the
	 * panels' look, but opaque (rounded and outlined); returns the card's column.
	 */
	UVerticalBox* MakeCenteredCard(UWidgetTree& Tree, float MaxWidth, float MaxHeight);

	/**
	 * `MakeCenteredCard` whose content scrolls above a footer that stays in view,
	 * set off by a rule. Returns the scrolling column; `OutFooter` is the footer.
	 */
	UVerticalBox* MakeFooterCard(UWidgetTree& Tree, float MaxWidth, float MaxHeight, UVerticalBox*& OutFooter);

	UTextBlock* AddText(UWidgetTree& Tree, UPanelWidget& Parent, const FText& Text, int32 Size,
		bool bBold = false, const FLinearColor& Color = Ink, float SpaceAbove = 12.f);

	UButton* AddButton(UWidgetTree& Tree, UPanelWidget& Parent, const FText& Label, float SpaceAbove = 24.f);

	void SetShown(UWidget* Widget, bool bShown);
}
