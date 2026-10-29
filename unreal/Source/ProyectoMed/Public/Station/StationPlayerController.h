// Shows the station screens for the local learner and points the view at the
// consultation scene's camera. Flow logic lives in UStationRunFlow.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"

#include "StationPlayerController.generated.h"

class UStationBriefWidget;
class UStationFeedbackWidget;
class UStationHudWidget;
class UStationInvalidatedWidget;
class UStationMenuWidget;
class UStationMicrophone;
class UStationMicrophoneWidget;
class UStationNoticeWidget;
class UStationPatientVoice;
class UStationRunFlow;

UCLASS()
class PROYECTOMED_API AStationPlayerController : public APlayerController
{
	GENERATED_BODY()

public:
	/** Actor tag of the camera the learner sees the patient through. */
	static const FName StationViewTag;

	/**
	 * Actor tag of the camera the main menu looks at the room through (#421). A level
	 * without one shows the menu through the station camera.
	 */
	static const FName MenuViewTag;

	UStationRunFlow* GetRunFlow() const { return Flow; }

protected:
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

private:
	void Render();
	/** The first camera tagged `Tag` in the level, or null. */
	AActor* FindCamera(const FName& Tag) const;
	/** Looks through the menu camera on the menu, and through the station camera otherwise. */
	void UpdateCamera();
	/** Gives the patient a voice and a speaking mouth for a voice training. */
	void PreparePatientVoice();
	/** Keeps the microphone on exactly while the voice link is in the room. */
	void UpdateMicrophone();

	UPROPERTY()
	TObjectPtr<UStationRunFlow> Flow;

	UPROPERTY()
	TObjectPtr<UStationMenuWidget> Menu;

	UPROPERTY()
	TObjectPtr<UStationNoticeWidget> Notice;

	UPROPERTY()
	TObjectPtr<UStationBriefWidget> Brief;

	UPROPERTY()
	TObjectPtr<UStationHudWidget> Hud;

	UPROPERTY()
	TObjectPtr<UStationFeedbackWidget> Feedback;

	UPROPERTY()
	TObjectPtr<UStationInvalidatedWidget> Invalidated;

	UPROPERTY()
	TObjectPtr<UStationMicrophoneWidget> MicrophoneScreen;

	UPROPERTY()
	TObjectPtr<UStationMicrophone> Microphone;

	UPROPERTY()
	TObjectPtr<UStationPatientVoice> PatientVoice;

	TWeakObjectPtr<AActor> StationCamera;
	TWeakObjectPtr<AActor> MenuCamera;

	/** The input mode last applied: game and UI during a run, UI only around it. */
	TOptional<bool> bAppliedRunInputMode;
};
