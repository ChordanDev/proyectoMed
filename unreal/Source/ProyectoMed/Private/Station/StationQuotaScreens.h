// The Cine screens of a start Phoenix refused (#467): today's simulations are used
// up, or the account has no subscription. They render UStationRunFlow and never call
// the network. Phoenix decides both refusals; prices and plans live on the website.

#pragma once

#include "Blueprint/UserWidget.h"
#include "CoreMinimal.h"

#include "StationQuotaScreens.generated.h"

class UButton;
class UStationRunFlow;
class UTextBlock;
class UWidget;

/** "5 h 12 min", or "12 min" under an hour, rounding partial minutes up so it reads 0 only at the reset. */
FText FormatDailyQuotaTimeLeft(const FTimespan& Left);

/** The plans page of the website, which Phoenix serves. */
FString StationPlansUrl(const FString& PhoenixBaseUrl);

UCLASS()
class UStationQuotaWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	FSimpleDelegate OnBackToMenu;

	void SetFlow(UStationRunFlow* InFlow) { Flow = InFlow; }

	/** Re-reads the time left; without any, the countdown leaves the screen. */
	void Refresh();

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override;

private:
	friend class FStationQuotaScreensSpec;

	UFUNCTION()
	void HandleBackToMenu();

	UPROPERTY()
	TObjectPtr<UStationRunFlow> Flow;

	/** The time left and what it counts down to. */
	UPROPERTY()
	TObjectPtr<UWidget> Countdown;

	UPROPERTY()
	TObjectPtr<UTextBlock> TimeLeftText;

	/** Shown, disabled, until the history exists (#465). */
	UPROPERTY()
	TObjectPtr<UButton> HistoryButton;

	UPROPERTY()
	TObjectPtr<UButton> MenuButton;
};

UCLASS()
class UStationSubscriptionWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	/** The learner asks for the plans page. */
	FSimpleDelegate OnOpenPlans;

	FSimpleDelegate OnBackToMenu;

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	friend class FStationQuotaScreensSpec;

	UFUNCTION()
	void HandleOpenPlans();

	UFUNCTION()
	void HandleBackToMenu();

	UPROPERTY()
	TObjectPtr<UButton> PlansButton;

	UPROPERTY()
	TObjectPtr<UButton> MenuButton;
};
