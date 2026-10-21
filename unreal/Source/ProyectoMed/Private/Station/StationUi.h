// Small builders for the station's native UMG screens, which are assembled in
// C++ so they review as text and need no binary widget assets.

#pragma once

#include "CoreMinimal.h"
#include "Components/SlateWrapperTypes.h"

class UBorder;
class UButton;
class UPanelWidget;
class UTextBlock;
class UVerticalBox;
class UWidget;
class UWidgetTree;

namespace StationUi
{
	const FLinearColor Backdrop(0.01f, 0.012f, 0.016f, 0.92f);
	const FLinearColor Card(0.06f, 0.07f, 0.085f, 1.f);
	const FLinearColor Ink(0.94f, 0.95f, 0.96f, 1.f);
	const FLinearColor Muted(0.62f, 0.66f, 0.72f, 1.f);
	const FLinearColor Accent(0.13f, 0.45f, 0.86f, 1.f);
	const FLinearColor Caution(0.95f, 0.66f, 0.22f, 1.f);

	/** A full-screen dimmed backdrop that centers one card of at most `MaxWidth`; returns the card's column. */
	UVerticalBox* MakeCenteredCard(UWidgetTree& Tree, float MaxWidth, float MaxHeight, bool bScrollable);

	UTextBlock* AddText(UWidgetTree& Tree, UPanelWidget& Parent, const FText& Text, int32 Size,
		bool bBold = false, const FLinearColor& Color = Ink, float SpaceAbove = 12.f);

	UButton* AddButton(UWidgetTree& Tree, UPanelWidget& Parent, const FText& Label, float SpaceAbove = 24.f);

	void SetShown(UWidget* Widget, bool bShown);
}
