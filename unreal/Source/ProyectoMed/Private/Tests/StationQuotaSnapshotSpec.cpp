// Renders the quota and subscription screens (#467) to PNG files, for a person to
// compare with docs/design/screens/png/Quota.png and Quota--subscription.png. Runs
// only with an RHI and when $STATION_HUD_SNAPSHOT_DIR names the folder for the images:
//   STATION_HUD_SNAPSHOT_DIR=/tmp/hud UnrealEditor ProyectoMed.uproject \
//     -ExecCmds="Automation RunTests ProyectoMed.StationCards.QuotaSnapshot; Quit" -unattended
// It asserts nothing about the look.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Blueprint/UserWidget.h"
#include "Engine/Engine.h"
#include "Engine/TextureRenderTarget2D.h"
#include "ImageUtils.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "RenderingThread.h"
#include "Slate/WidgetRenderer.h"
#include "Station/StationQuotaScreens.h"
#include "Station/StationRunFlow.h"
#include "TextureResource.h"
#include "Widgets/Colors/SColorBlock.h"
#include "Widgets/SOverlay.h"

BEGIN_DEFINE_SPEC(FStationQuotaSnapshotSpec, "ProyectoMed.StationCards.QuotaSnapshot",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	void Save(UUserWidget* Screen, const FString& OutDir, const FString& Name);
END_DEFINE_SPEC(FStationQuotaSnapshotSpec)

void FStationQuotaSnapshotSpec::Save(UUserWidget* Screen, const FString& OutDir, const FString& Name)
{
	const FVector2D Size(1600.0, 900.0);
	// A plain backdrop where the scene would be.
	TSharedRef<SWidget> Root = SNew(SOverlay)
		+ SOverlay::Slot()[SNew(SColorBlock).Color(FLinearColor(0.16f, 0.17f, 0.18f, 1.f))]
		+ SOverlay::Slot()[Screen->TakeWidget()];
	// Slate encodes the colors once; a linear target keeps them as the screen shows them.
	FWidgetRenderer Renderer(true, true);
	UTextureRenderTarget2D* Target = FWidgetRenderer::CreateTargetFor(Size, TF_Bilinear, false);
	// The first pass lays the text out; the second draws it in place.
	Renderer.DrawWidget(Target, Root, Size, 0.f);
	Renderer.DrawWidget(Target, Root, Size, 0.016f);
	FlushRenderingCommands();

	TArray<FColor> Pixels;
	if (!TestTrue(TEXT("pixels read"), Target->GameThread_GetRenderTargetResource()->ReadPixels(Pixels)))
	{
		return;
	}
	for (FColor& Pixel : Pixels)
	{
		Pixel.A = 255;
	}
	TArray64<uint8> Png;
	FImageUtils::PNGCompressImageArray(static_cast<int32>(Size.X), static_cast<int32>(Size.Y), Pixels, Png);
	const FString Path = FPaths::Combine(OutDir, Name + TEXT(".png"));
	TestTrue(*FString::Printf(TEXT("%s written"), *Path), FFileHelper::SaveArrayToFile(Png, *Path));
}

void FStationQuotaSnapshotSpec::Define()
{
	It("renders the quota and subscription screens", [this]()
	{
		const FString OutDir = FPlatformMisc::GetEnvironmentVariable(TEXT("STATION_HUD_SNAPSHOT_DIR"));
		if (OutDir.IsEmpty() || !FApp::CanEverRender())
		{
			AddInfo(TEXT("Skipped: set STATION_HUD_SNAPSHOT_DIR and run with an RHI."));
			return;
		}

		UWorld* World = GEngine->GetWorldContexts()[0].World();
		UStationRunFlow* Flow = NewObject<UStationRunFlow>();
		Flow->Step = EStationRunStep::DailyQuota;
		Flow->DailyQuotaResetsAt = FDateTime::UtcNow() + FTimespan(5, 12, 0);
		UStationQuotaWidget* Quota = CreateWidget<UStationQuotaWidget>(World);
		Quota->SetFlow(Flow);
		// Held: the scrim does not outlive its Slate widgets.
		const TSharedRef<SWidget> QuotaSlate = Quota->TakeWidget();
		Quota->Refresh();
		Save(Quota, OutDir, TEXT("quota"));
		Save(CreateWidget<UStationSubscriptionWidget>(World), OutDir, TEXT("quota-subscription"));
	});
}

#endif
