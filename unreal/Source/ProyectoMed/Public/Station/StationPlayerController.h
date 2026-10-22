// Shows the station screens for the local learner and points the view at the
// consultation scene's camera. Flow logic lives in UStationRunFlow.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"

#include "StationPlayerController.generated.h"

class UStationBriefWidget;
class UStationFeedbackWidget;
class UStationHudWidget;
class UStationNoticeWidget;
class UStationRunFlow;

UCLASS()
class PROYECTOMED_API AStationPlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	/** Actor tag of the camera the learner sees the patient through. */
	static const FName StationViewTag;

	UStationRunFlow* GetRunFlow() const { return Flow; }

protected:
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

private:
	void Render();
	void UseStationCamera();

	UPROPERTY()
	TObjectPtr<UStationRunFlow> Flow;

	UPROPERTY()
	TObjectPtr<UStationNoticeWidget> Notice;

	UPROPERTY()
	TObjectPtr<UStationBriefWidget> Brief;

	UPROPERTY()
	TObjectPtr<UStationHudWidget> Hud;

	UPROPERTY()
	TObjectPtr<UStationFeedbackWidget> Feedback;
};
