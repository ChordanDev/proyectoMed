// Small builders for the station's native UMG screens, which are assembled in
// C++ so they review as text and need no binary widget assets.

#pragma once

#include "CoreMinimal.h"
#include "Components/SlateWrapperTypes.h"
#include "Styling/SlateBrush.h"

class UBorder;
class UButton;
class UEditableTextBox;
class UPanelWidget;
class UTextBlock;
class UVerticalBox;
class UWidget;
class UWidgetTree;

namespace StationUi
{
	const FLinearColor Backdrop(0.01f, 0.012f, 0.016f, 0.92f);
	const FLinearColor Ink(0.94f, 0.95f, 0.96f, 1.f);
	const FLinearColor Muted(0.62f, 0.66f, 0.72f, 1.f);
	const FLinearColor Accent(0.13f, 0.45f, 0.86f, 1.f);
	const FLinearColor Caution(0.95f, 0.66f, 0.22f, 1.f);

	// The in-run side panel and the documents it opens: opaque, so the scene
	// behind never mixes with what the learner reads. Given as sRGB, like the
	// web palette they come from.
	const FLinearColor Panel(FColor(0x1B, 0x1B, 0x1A));
	const FLinearColor PanelEdge(FColor(0x44, 0x44, 0x41));
	const FLinearColor Raised(FColor(0x2C, 0x2C, 0x2A));
	const FLinearColor RaisedHover(FColor(0x3A, 0x3A, 0x38));
	const FLinearColor Quiet(FColor(0x88, 0x87, 0x80));
	const FLinearColor Link(FColor(0x85, 0xB7, 0xEB));
	const FLinearColor LearnerBubble(FColor(0x0C, 0x44, 0x7C));
	const FLinearColor Action(FColor(0x18, 0x5F, 0xA5));
	const FLinearColor ActionHover(FColor(0x23, 0x6F, 0xBA));
	const FLinearColor Danger(FColor(0xA3, 0x2D, 0x2D));
	const FLinearColor DangerHover(FColor(0xBE, 0x37, 0x36));
	const FLinearColor Recording(FColor(0xE2, 0x4B, 0x4A));
	const FLinearColor RecordingInk(FColor(0xF7, 0xC1, 0xC1));
	const FLinearColor Paper(FColor(0xF1, 0xEF, 0xE8));
	const FLinearColor PaperInk(FColor(0x2C, 0x2C, 0x2A));
	const FLinearColor PaperMuted(FColor(0x5F, 0x5E, 0x5A));
	const FLinearColor PaperEdge(FColor(0xD3, 0xD1, 0xC7));

	// The status labels of the exam requests.
	const FLinearColor ReleasedFill(FColor(0x27, 0x50, 0x0A));
	const FLinearColor ReleasedInk(FColor(0xC0, 0xDD, 0x97));
	const FLinearColor DeclinedFill(FColor(0x63, 0x38, 0x06));
	const FLinearColor DeclinedInk(FColor(0xFA, 0xC7, 0x75));
	/** A status that is neither good nor bad news: still waiting, or released before. */
	const FLinearColor NeutralFill(FColor(0x44, 0x44, 0x41));
	const FLinearColor NeutralInk(FColor(0xD3, 0xD1, 0xC7));

	// The main menu's mode cards (#421): blue for a training, amber for a simulated exam.
	const FLinearColor TrainingFill(FColor(0x14, 0x36, 0x5C));
	const FLinearColor TrainingHover(FColor(0x1B, 0x47, 0x77));
	const FLinearColor TrainingAccent(FColor(0x85, 0xB7, 0xEB));
	const FLinearColor ExamFill(FColor(0x4E, 0x2A, 0x0C));
	const FLinearColor ExamHover(FColor(0x66, 0x37, 0x12));
	const FLinearColor ExamAccent(FColor(0xF2, 0xB6, 0x61));
	/** Behind the main menu until the doctor's office shows there (#431). */
	const FLinearColor MenuBackdrop(FColor(0x0E, 0x24, 0x40));

	/** A rounded box of `Fill`, outlined in `Outline` when `OutlineWidth` is above 0. */
	FSlateBrush RoundedBrush(const FLinearColor& Fill, float Radius,
		const FLinearColor& Outline = FLinearColor::Transparent, float OutlineWidth = 0.f);

	/** A border painted with `RoundedBrush`. */
	UBorder* MakeRounded(UWidgetTree& Tree, const FLinearColor& Fill, float Radius, const FMargin& Padding,
		const FLinearColor& Outline = FLinearColor::Transparent, float OutlineWidth = 0.f);

	/** Restyles a button from `AddButton` as the panel's main, rounded action. */
	void MakePrimary(UButton& Button);

	/** Restyles a button from `AddButton` as a rounded, quieter alternative to the primary one. */
	void MakeSecondary(UButton& Button);

	/** Restyles a button from `AddButton` as a rounded red one, for ending the run. */
	void MakeDanger(UButton& Button);

	/** A dark, rounded text box that matches the side panels. */
	void StyleInput(UEditableTextBox& Input);

	/** A button with no box of its own: only its content shows, lighter while hovered. */
	UButton* MakeFlatButton(UWidgetTree& Tree, const FText& Label, int32 Size, const FLinearColor& Color, bool bBold = false);

	/**
	 * A full-screen dimmed backdrop that centers one card of at most `MaxWidth`, in the
	 * in-run panels' look (opaque, rounded and outlined); returns the card's column.
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
