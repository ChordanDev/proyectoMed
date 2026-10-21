#include "Station/StationPlayerController.h"

#include "Blueprint/UserWidget.h"
#include "Camera/CameraActor.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"
#include "Station/StationRunFlow.h"
#include "Station/StationScreens.h"
#include "StationClient.h"
#include "StationClientSubsystem.h"

DEFINE_LOG_CATEGORY_STATIC(LogStationPlayer, Log, All);

const FName AStationPlayerController::StationViewTag(TEXT("StationView"));

void AStationPlayerController::BeginPlay()
{
	Super::BeginPlay();
	if (!IsLocalController())
	{
		return;
	}

	UseStationCamera();

	UStationClientSubsystem* Subsystem = GetGameInstance()->GetSubsystem<UStationClientSubsystem>();
	Flow = NewObject<UStationRunFlow>(this);

	Notice = CreateWidget<UStationNoticeWidget>(this, UStationNoticeWidget::StaticClass());
	Brief = CreateWidget<UStationBriefWidget>(this, UStationBriefWidget::StaticClass());
	Hud = CreateWidget<UStationHudWidget>(this, UStationHudWidget::StaticClass());
	Brief->SetFlow(Flow);
	Hud->SetFlow(Flow);
	Notice->OnAcknowledged.BindWeakLambda(this, [this]() { Flow->AcknowledgeNotice(); });
	Notice->AddToViewport();
	Brief->AddToViewport();
	Hud->AddToViewport();

	bShowMouseCursor = true;
	Flow->OnChanged.AddUObject(this, &AStationPlayerController::Render);
	Flow->Begin(Subsystem->GetClient());
	Render();
}

void AStationPlayerController::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	// A run left mid-way is ephemeral: ask Phoenix to forget it now instead of
	// waiting for the session to expire.
	if (Flow && Flow->GetClient() && Flow->GetClient()->GetSession())
	{
		Flow->GetClient()->DiscardSession([](const TStationResult<FStationNone>&) {});
	}
	Super::EndPlay(EndPlayReason);
}

void AStationPlayerController::Render()
{
	if (!Flow || !Notice || !Brief || !Hud)
	{
		return;
	}

	const EStationRunStep Step = Flow->GetStep();
	const bool bRunning = Step == EStationRunStep::Running;
	Notice->SetVisibility(Step == EStationRunStep::Notice ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	Brief->SetVisibility(Step == EStationRunStep::Brief || Step == EStationRunStep::Starting
		? ESlateVisibility::Visible
		: ESlateVisibility::Collapsed);
	Hud->SetVisibility(bRunning ? ESlateVisibility::SelfHitTestInvisible : ESlateVisibility::Collapsed);
	Brief->Refresh();
	Hud->Refresh();

	if (bRunning)
	{
		SetInputMode(FInputModeGameAndUI());
	}
	else
	{
		SetInputMode(FInputModeUIOnly());
	}
}

void AStationPlayerController::UseStationCamera()
{
	for (TActorIterator<ACameraActor> It(GetWorld()); It; ++It)
	{
		if (It->ActorHasTag(StationViewTag))
		{
			SetViewTarget(*It);
			return;
		}
	}
	UE_LOG(LogStationPlayer, Warning, TEXT("No camera tagged '%s' in this level; the view stays at the controller."),
		*StationViewTag.ToString());
}
