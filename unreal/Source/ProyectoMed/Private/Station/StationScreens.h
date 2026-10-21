// The station's native UMG screens: Pre-Station Notice, brief, and the
// in-run HUD with the Station Timer. They render UStationRunFlow and never call
// the network.

#pragma once

#include "Blueprint/UserWidget.h"
#include "CoreMinimal.h"

#include "StationScreens.generated.h"

class UButton;
class UStationRunFlow;
class UTextBlock;
class UVerticalBox;

UCLASS()
class UStationNoticeWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	FSimpleDelegate OnAcknowledged;

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	UFUNCTION()
	void HandleAcknowledge();
};

UCLASS()
class UStationBriefWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	void SetFlow(UStationRunFlow* InFlow) { Flow = InFlow; }

	/** Re-reads the flow: loading, error, the station brief, and which trainings can start. */
	void Refresh();

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	UFUNCTION()
	void HandleTextTraining();

	UFUNCTION()
	void HandleVoiceTraining();

	UFUNCTION()
	void HandleRetry();

	UPROPERTY()
	TObjectPtr<UStationRunFlow> Flow;

	UPROPERTY()
	TObjectPtr<UTextBlock> StatusText;

	UPROPERTY()
	TObjectPtr<UTextBlock> ErrorText;

	UPROPERTY()
	TObjectPtr<UButton> RetryButton;

	UPROPERTY()
	TObjectPtr<UVerticalBox> BriefBox;

	UPROPERTY()
	TObjectPtr<UTextBlock> TitleText;

	UPROPERTY()
	TObjectPtr<UTextBlock> ScenarioText;

	UPROPERTY()
	TObjectPtr<UVerticalBox> TaskList;

	UPROPERTY()
	TObjectPtr<UButton> TextButton;

	UPROPERTY()
	TObjectPtr<UButton> VoiceButton;

	UPROPERTY()
	TObjectPtr<UTextBlock> VoiceNote;
};

UCLASS()
class UStationHudWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	void SetFlow(UStationRunFlow* InFlow) { Flow = InFlow; }

	/** Re-reads the training mode and the voice fallback notice. */
	void Refresh();

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override;

private:
	UPROPERTY()
	TObjectPtr<UStationRunFlow> Flow;

	UPROPERTY()
	TObjectPtr<UTextBlock> ModeText;

	UPROPERTY()
	TObjectPtr<UTextBlock> TimerText;

	UPROPERTY()
	TObjectPtr<UTextBlock> FallbackText;
};
