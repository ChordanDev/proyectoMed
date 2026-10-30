// The shared Cine style kit (#455): its tokens match the mockups in
// docs/design/screens, and its builders keep the rules every screen relies on.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Blueprint/WidgetTree.h"
#include "Components/Border.h"
#include "Components/Button.h"
#include "Components/HorizontalBox.h"
#include "Components/SizeBox.h"
#include "Components/TextBlock.h"
#include "Components/VerticalBox.h"
#include "Engine/Font.h"
#include "Fonts/CompositeFont.h"
#include "Framework/Application/SlateApplication.h"
#include "Misc/ConfigCacheIni.h"
#include "Station/StationUi.h"
#include "Widgets/SWindow.h"

namespace StationUiSpec
{
	/** Relative luminance, from WCAG 2.2; an FLinearColor is already linear. */
	float Luminance(const FLinearColor& Color)
	{
		return 0.2126f * Color.R + 0.7152f * Color.G + 0.0722f * Color.B;
	}

	float Contrast(const FLinearColor& Text, const FLinearColor& Background)
	{
		const float Lighter = FMath::Max(Luminance(Text), Luminance(Background));
		const float Darker = FMath::Min(Luminance(Text), Luminance(Background));
		return (Lighter + 0.05f) / (Darker + 0.05f);
	}

	/** `Top` over `Bottom`, blended in sRGB like Slate and the mockups do. */
	FLinearColor Over(const FLinearColor& Top, const FLinearColor& Bottom)
	{
		const FColor Above = Top.ToFColor(true);
		const FColor Below = Bottom.ToFColor(true);
		const auto Mix = [&Top](uint8 A, uint8 B)
		{
			return static_cast<uint8>(FMath::RoundToInt(A * Top.A + B * (1.f - Top.A)));
		};
		return FLinearColor(FColor(Mix(Above.R, Below.R), Mix(Above.G, Below.G), Mix(Above.B, Below.B)));
	}

	/** The brightest thing in the mockups' stand-in for the office, its window. */
	const FLinearColor BrightestScene(FColor(0x2E, 0x3F, 0x4D));

	float Height(UWidget& Widget)
	{
		TSharedRef<SWidget> Slate = Widget.TakeWidget();
		Slate->SlatePrepass(1.f);
		return Slate->GetDesiredSize().Y;
	}

	UTextBlock* LabelOf(UPanelWidget& Parent)
	{
		TArray<UWidget*> Found;
		UWidgetTree::GetChildWidgets(&Parent, Found);
		for (UWidget* Widget : Found)
		{
			if (UTextBlock* Text = Cast<UTextBlock>(Widget))
			{
				return Text;
			}
		}
		return nullptr;
	}
}

BEGIN_DEFINE_SPEC(FStationUiSpec, "ProyectoMed.StationUi",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	UWidgetTree* Tree = nullptr;
	UVerticalBox* Column = nullptr;

	UButton* MakeButton(TFunctionRef<void(UButton&)> Restyle);
	void TestReadable(const TCHAR* What, const FLinearColor& Text);
END_DEFINE_SPEC(FStationUiSpec)

UButton* FStationUiSpec::MakeButton(TFunctionRef<void(UButton&)> Restyle)
{
	UButton* Button = StationUi::AddButton(*Tree, *Column, FText::FromString(TEXT("Entrar")));
	Restyle(*Button);
	return Button;
}

void FStationUiSpec::TestReadable(const TCHAR* What, const FLinearColor& Text)
{
	// Past the last stop that covers anything the scrim is gone, and no text goes there.
	for (const StationUi::FScrimStop& Stop : StationUi::ScrimStops)
	{
		if (Stop.Opacity > 0.f)
		{
			const FLinearColor Behind = StationUiSpec::Over(
				StationUi::ScrimColor.CopyWithNewOpacity(Stop.Opacity), StationUiSpec::BrightestScene);
			TestTrue(*FString::Printf(TEXT("%s reads at %.0f%% of the scrim"), What, Stop.Position * 100.f),
				StationUiSpec::Contrast(Text, Behind) >= 4.5f);
		}
	}
}

void FStationUiSpec::Define()
{
	using namespace StationUiSpec;

	BeforeEach([this]()
	{
		Tree = NewObject<UWidgetTree>();
		Column = Tree->ConstructWidget<UVerticalBox>();
		Tree->RootWidget = Column;
	});

	Describe("the Cine tokens", [this]()
	{
		It("are the mockups' colours", [this]()
		{
			const auto Is = [this](const TCHAR* What, const FLinearColor& Token, FColor Mockup)
			{
				TestEqual(What, Token.ToFColor(true), Mockup);
			};
			Is(TEXT("title ink"), StationUi::InkTitle, FColor(0xFF, 0xFF, 0xFF));
			Is(TEXT("text ink"), StationUi::Ink, FColor(0xE8, 0xEE, 0xF2));
			Is(TEXT("body ink"), StationUi::InkBody, FColor(0xC9, 0xD4, 0xDB));
			Is(TEXT("muted ink"), StationUi::Muted, FColor(0xA9, 0xB7, 0xC1));
			Is(TEXT("Treino accent"), StationUi::TreinoAccent, FColor(0x5F, 0xD0, 0xBF));
			Is(TEXT("Prova simulada accent"), StationUi::ProvaAccent, FColor(0xF2, 0xA6, 0x5A));
			Is(TEXT("danger"), StationUi::Danger, FColor(0xC2, 0x41, 0x3A));
			Is(TEXT("danger text"), StationUi::DangerInk, FColor(0xFF, 0x8A, 0x7A));
			Is(TEXT("scrim"), StationUi::ScrimColor, FColor(0x09, 0x0D, 0x11));
			Is(TEXT("panel"), StationUi::PanelSolid, FColor(0x0C, 0x11, 0x16));
			Is(TEXT("panel edge"), StationUi::PanelEdge, FColor(0x2F, 0x3D, 0x48));
			Is(TEXT("paper"), StationUi::Paper, FColor(0xF6, 0xF3, 0xEC));
			Is(TEXT("paper ink"), StationUi::PaperInk, FColor(0x1D, 0x28, 0x33));
			TestEqual(TEXT("the panel lets the scene through"), StationUi::Panel.A, 0.84f);
		});

		It("keep text readable over the scrim", [this]()
		{
			TestReadable(TEXT("the title"), StationUi::InkTitle);
			TestReadable(TEXT("text"), StationUi::Ink);
			TestReadable(TEXT("the body"), StationUi::InkBody);
			TestReadable(TEXT("muted text"), StationUi::Muted);
			TestReadable(TEXT("the Treino accent"), StationUi::TreinoAccent);
			TestReadable(TEXT("the Prova simulada accent"), StationUi::ProvaAccent);
			TestReadable(TEXT("danger text"), StationUi::DangerInk);
		});

		It("keep text readable on a panel", [this]()
		{
			const FLinearColor Behind = Over(StationUi::Panel, BrightestScene);
			TestTrue(TEXT("text"), Contrast(StationUi::Ink, Behind) >= 4.5f);
			TestTrue(TEXT("muted text"), Contrast(StationUi::Muted, Behind) >= 4.5f);
			TestTrue(TEXT("paper"), Contrast(StationUi::PaperInk, StationUi::Paper) >= 4.5f);
		});
	});

	Describe("the scrim", [this]()
	{
		It("runs from the mockups' dark left edge to clear", [this]()
		{
			TestEqual(TEXT("the left edge"), StationUi::ScrimStops[0].Opacity, 0.92f);
			TestEqual(TEXT("clear before the right edge"), StationUi::ScrimStops[UE_ARRAY_COUNT(StationUi::ScrimStops) - 1].Opacity, 0.f);
		});

		It("lets the pointer through to the screen", [this]()
		{
			UWidget* Scrim = StationUi::MakeScrim(*Tree);
			TestEqual(TEXT("the pointer passes"), Scrim->GetVisibility(), ESlateVisibility::HitTestInvisible);
		});
	});

	Describe("Manrope", [this]()
	{
		It("has every weight of the mockups", [this]()
		{
			const UFont* Manrope = Cast<UFont>(StationUi::Font(StationUi::FontBold, 16).FontObject);
			if (!TestNotNull(TEXT("the font asset"), Manrope))
			{
				return;
			}
			TestEqual(TEXT("loaded at runtime"), Manrope->FontCacheType, EFontCacheType::Runtime);
			const FCompositeFont* Composite = Manrope->GetCompositeFont();
			if (!TestNotNull(TEXT("the typefaces"), Composite))
			{
				return;
			}
			for (const FName Weight : {StationUi::FontRegular, StationUi::FontMedium, StationUi::FontSemiBold,
				StationUi::FontBold, StationUi::FontExtraBold})
			{
				const FTypefaceEntry* Entry = Composite->DefaultTypeface.Fonts.FindByPredicate(
					[Weight](const FTypefaceEntry& Candidate) { return Candidate.Name == Weight; });
				if (TestNotNull(*FString::Printf(TEXT("the %s typeface"), *Weight.ToString()), Entry))
				{
					TestNotNull(*FString::Printf(TEXT("the %s face"), *Weight.ToString()), Entry->Font.GetFontFaceAsset());
				}
			}
		});

		It("reaches a packaged game, though no map references it", [this]()
		{
			TArray<FString> Cooked;
			GConfig->GetArray(TEXT("/Script/UnrealEd.ProjectPackagingSettings"), TEXT("DirectoriesToAlwaysCook"), Cooked, GGameIni);
			TestTrue(TEXT("its folder is always cooked"), Cooked.ContainsByPredicate(
				[](const FString& Directory) { return Directory.Contains(TEXT("/Game/Station/UI/Fonts")); }));
		});

		It("sets the screens' text", [this]()
		{
			UTextBlock* Text = StationUi::AddText(*Tree, *Column, FText::FromString(TEXT("Treino")), 18, true);
			TestEqual(TEXT("the font"), Text->GetFont().FontObject.Get(), StationUi::Font(StationUi::FontBold, 18).FontObject.Get());
			TestEqual(TEXT("the weight"), Text->GetFont().TypefaceFontName, StationUi::FontBold);
			TestEqual(TEXT("the size"), Text->GetFont().Size, 18.f);
		});
	});

	Describe("the buttons", [this]()
	{
		It("are at least 44 px tall", [this]()
		{
			TestTrue(TEXT("primary"), Height(*MakeButton(StationUi::MakePrimary)) >= 44.f);
			TestTrue(TEXT("exam"), Height(*MakeButton(StationUi::MakeExam)) >= 44.f);
			TestTrue(TEXT("danger"), Height(*MakeButton(StationUi::MakeDanger)) >= 44.f);
			TestTrue(TEXT("secondary"), Height(*MakeButton(StationUi::MakeSecondary)) >= 44.f);
			TestTrue(TEXT("ghost"), Height(*MakeButton(StationUi::MakeGhost)) >= 44.f);
			TestTrue(TEXT("the enter arrow"), Height(*StationUi::MakeEnterArrow(*Tree, StationUi::TreinoAccent)) >= 44.f);
		});

		It("fill with their kind's colour under a readable label", [this]()
		{
			const auto Fills = [this](const TCHAR* What, UButton& Button, const FLinearColor& Fill, const FLinearColor& Ink)
			{
				const FButtonStyle& Style = Button.GetStyle();
				TestEqual(What, Style.Normal.TintColor.GetSpecifiedColor(), Fill);
				TestEqual(What, Style.NormalForeground.GetSpecifiedColor(), Ink);
				TestTrue(What, Contrast(Ink, Fill) >= 4.5f);
			};
			Fills(TEXT("primary"), *MakeButton(StationUi::MakePrimary), StationUi::TreinoAccent, StationUi::InkOnAccent);
			Fills(TEXT("exam"), *MakeButton(StationUi::MakeExam), StationUi::ProvaAccent, StationUi::InkOnAccent);
			Fills(TEXT("danger"), *MakeButton(StationUi::MakeDanger), StationUi::Danger, StationUi::InkTitle);
		});

		It("keep the secondary and the ghost empty", [this]()
		{
			const FButtonStyle Secondary = MakeButton(StationUi::MakeSecondary)->GetStyle();
			TestEqual(TEXT("no fill"), Secondary.Normal.TintColor.GetSpecifiedColor().A, 0.f);
			TestEqual(TEXT("its outline"), Secondary.Normal.OutlineSettings.Color.GetSpecifiedColor(), StationUi::ControlEdge);
			TestEqual(TEXT("its label"), Secondary.NormalForeground.GetSpecifiedColor(), StationUi::Ink);

			const FButtonStyle Ghost = MakeButton(StationUi::MakeGhost)->GetStyle();
			TestEqual(TEXT("no fill"), Ghost.Normal.TintColor.GetSpecifiedColor().A, 0.f);
			TestEqual(TEXT("no outline"), Ghost.Normal.OutlineSettings.Width, 0.f);
			TestEqual(TEXT("muted"), Ghost.NormalForeground.GetSpecifiedColor(), StationUi::Muted);
			TestEqual(TEXT("lit while hovered"), Ghost.HoveredForeground.GetSpecifiedColor(), StationUi::InkTitle);
		});

		It("fade while disabled, like the mockups", [this]()
		{
			const FButtonStyle Style = MakeButton(StationUi::MakePrimary)->GetStyle();
			TestEqual(TEXT("the fill"), Style.Disabled.TintColor.GetSpecifiedColor().A, 0.45f);
			TestEqual(TEXT("the label"), Style.DisabledForeground.GetSpecifiedColor().A, 0.45f);
		});

		It("draw the label in the button's colour, so hovering can change it", [this]()
		{
			UButton* Button = MakeButton(StationUi::MakeGhost);
			UTextBlock* Label = LabelOf(*Button);
			if (TestNotNull(TEXT("the label"), Label))
			{
				TestTrue(TEXT("follows the button"), Label->GetColorAndOpacity().IsColorSpecified() == false);
			}
		});

		It("make the enter arrow round, in the mode's accent", [this]()
		{
			UButton* Arrow = StationUi::MakeEnterArrow(*Tree, StationUi::ProvaAccent);
			const FSlateBrush& Normal = Arrow->GetStyle().Normal;
			TestEqual(TEXT("the accent"), Normal.TintColor.GetSpecifiedColor(), StationUi::ProvaAccent);
			TestEqual(TEXT("round"), static_cast<float>(Normal.OutlineSettings.CornerRadii.X), Height(*Arrow) / 2.f);
			TestEqual(TEXT("as wide as tall"), static_cast<float>(Arrow->TakeWidget()->GetDesiredSize().X), Height(*Arrow));
		});
	});

	Describe("the keyboard focus", [this]()
	{
		const auto Ringed = [](const FButtonStyle& Style)
		{
			for (const FSlateBrush* Brush : {&Style.Normal, &Style.Hovered, &Style.Pressed})
			{
				if (Brush->OutlineSettings.Width < 2.f || Brush->OutlineSettings.Color.GetSpecifiedColor() != StationUi::InkTitle)
				{
					return false;
				}
			}
			return true;
		};

		It("rings a button while the keyboard has it, and gives its look back", [this, Ringed]()
		{
			const auto Rings = [this, Ringed](const TCHAR* What, UButton& Button)
			{
				const FButtonStyle Before = Button.GetStyle();
				Button.OnReceivedFocus.ExecuteIfBound();
				TestTrue(*FString::Printf(TEXT("%s ringed"), What), Ringed(Button.GetStyle()));
				Button.OnLostFocus.ExecuteIfBound();
				TestTrue(*FString::Printf(TEXT("%s back"), What), Button.GetStyle().Normal == Before.Normal);
			};
			Rings(TEXT("primary"), *MakeButton(StationUi::MakePrimary));
			Rings(TEXT("exam"), *MakeButton(StationUi::MakeExam));
			Rings(TEXT("danger"), *MakeButton(StationUi::MakeDanger));
			Rings(TEXT("secondary"), *MakeButton(StationUi::MakeSecondary));
			Rings(TEXT("ghost"), *MakeButton(StationUi::MakeGhost));
			Rings(TEXT("the enter arrow"), *StationUi::MakeEnterArrow(*Tree, StationUi::TreinoAccent));
			Rings(TEXT("a flat button"), *StationUi::MakeFlatButton(*Tree, FText::FromString(TEXT("Voltar")), 16, StationUi::Link));
		});

		It("answers real keyboard focus, and not a click", [this, Ringed]()
		{
			UButton* Button = MakeButton(StationUi::MakePrimary);
			TSharedRef<SWindow> Window = SNew(SWindow).ClientSize(FVector2f(200.f, 100.f))[Button->TakeWidget()];
			FSlateApplication::Get().AddWindow(Window, false);
			TSharedRef<SWidget> Slate = Button->TakeWidget();

			FSlateApplication::Get().SetUserFocus(0, Slate, EFocusCause::Mouse);
			TestFalse(TEXT("a click draws no ring"), Ringed(Button->GetStyle()));
			FSlateApplication::Get().ClearUserFocus(0);
			FSlateApplication::Get().SetUserFocus(0, Slate, EFocusCause::Navigation);
			TestTrue(TEXT("the keyboard does"), Ringed(Button->GetStyle()));
			FSlateApplication::Get().ClearUserFocus(0);
			TestFalse(TEXT("gone with the focus"), Ringed(Button->GetStyle()));

			FSlateApplication::Get().RequestDestroyWindow(Window);
		});
	});

	Describe("the small pieces", [this]()
	{
		It("builds the 32x4 mode mark in the mode's accent", [this]()
		{
			USizeBox* Mark = Cast<USizeBox>(StationUi::MakeModeMark(*Tree, StationUi::TreinoAccent));
			if (!TestNotNull(TEXT("sized"), Mark))
			{
				return;
			}
			const FVector2D Size = (Mark->TakeWidget()->SlatePrepass(1.f), Mark->TakeWidget()->GetDesiredSize());
			TestEqual(TEXT("32 wide"), Size.X, 32.0);
			TestEqual(TEXT("4 tall"), Size.Y, 4.0);
			UBorder* Bar = Cast<UBorder>(Mark->GetContent());
			if (TestNotNull(TEXT("the bar"), Bar))
			{
				TestEqual(TEXT("the accent"), Bar->Background.TintColor.GetSpecifiedColor(), StationUi::TreinoAccent);
			}
		});

		It("builds a chip around its label", [this]()
		{
			UBorder* Chip = StationUi::MakeChip(*Tree, FText::FromString(TEXT("Só voz")));
			TestEqual(TEXT("empty"), Chip->Background.TintColor.GetSpecifiedColor().A, 0.f);
			TestEqual(TEXT("outlined"), Chip->Background.OutlineSettings.Color.GetSpecifiedColor(), StationUi::ChipEdge);
			UTextBlock* Label = Cast<UTextBlock>(Chip->GetContent());
			if (TestNotNull(TEXT("the label"), Label))
			{
				TestEqual(TEXT("the words"), Label->GetText().ToString(), FString(TEXT("Só voz")));
			}
		});

		It("builds a see-through panel", [this]()
		{
			UBorder* Panel = StationUi::MakePanel(*Tree, FMargin(20.f));
			TestEqual(TEXT("the fill"), Panel->Background.TintColor.GetSpecifiedColor(), StationUi::Panel);
			TestEqual(TEXT("the edge"), Panel->Background.OutlineSettings.Color.GetSpecifiedColor(), StationUi::PanelEdge);
			TestEqual(TEXT("rounded"), static_cast<float>(Panel->Background.OutlineSettings.CornerRadii.X), 12.f);
		});

		It("builds a keyboard hint from any key", [this]()
		{
			for (const TCHAR* Key : {TEXT("Espaço"), TEXT("Enter"), TEXT("Esc")})
			{
				UHorizontalBox* Hint = StationUi::MakeKeyHint(*Tree, FText::FromString(Key), FText::FromString(TEXT("Falar")));
				UBorder* Cap = nullptr;
				TArray<UWidget*> Found;
				UWidgetTree::GetChildWidgets(Hint, Found);
				for (UWidget* Widget : Found)
				{
					Cap = Cap ? Cap : Cast<UBorder>(Widget);
				}
				if (!TestNotNull(TEXT("the keycap"), Cap))
				{
					continue;
				}
				UTextBlock* Label = LabelOf(*Cap);
				if (TestNotNull(TEXT("the key"), Label))
				{
					TestEqual(TEXT("the key's name"), Label->GetText().ToString(), FString(Key));
				}
				TestEqual(TEXT("what it does"), Cast<UTextBlock>(Hint->GetChildAt(1))->GetText().ToString(), FString(TEXT("Falar")));
			}
		});
	});
}

#endif
