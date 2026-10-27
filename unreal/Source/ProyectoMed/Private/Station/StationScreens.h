// The station's native UMG screens: the first-launch microphone disclosure,
// Pre-Station Notice, brief, the in-run HUD with the Station Timer, the voice
// status, the conversation and the exam panel, and the feedback once the run
// ends. They render UStationRunFlow and never call the network.

#pragma once

#include "Blueprint/UserWidget.h"
#include "CoreMinimal.h"

#include "StationScreens.generated.h"

class UButton;
class UEditableTextBox;
class UOverlay;
class UScrollBox;
class UStationRunFlow;
class UTextBlock;
class UVerticalBox;

UCLASS()
class UStationMicrophoneWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	/** True to ask the system for the microphone, false for "not now". */
	TDelegate<void(bool)> OnAnswered;

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	UFUNCTION()
	void HandleAllow();

	UFUNCTION()
	void HandleNotNow();
};
struct FStationCriterionResult;

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

	/** Re-reads the training mode, the voice fallback notice, the conversation and the exam panel. */
	void Refresh();

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override;

private:
	void BuildConversation(UOverlay& Root);
	void RefreshConversation();
	void AddTranscriptLine(const FText& Text, const FLinearColor& Color);
	void SendTypedTurn();
	void BuildExams(UOverlay& Root);
	void RefreshExams();
	void RequestExam();

	UFUNCTION()
	void HandleSend();

	UFUNCTION()
	void HandleTurnCommitted(const FText& Text, ETextCommit::Type CommitMethod);

	UFUNCTION()
	void HandleToggleExams();

	UFUNCTION()
	void HandleRequestExam();

	UFUNCTION()
	void HandleExamCommitted(const FText& Text, ETextCommit::Type CommitMethod);

	UFUNCTION()
	void HandleFinish();

	UPROPERTY()
	TObjectPtr<UStationRunFlow> Flow;

	UPROPERTY()
	TObjectPtr<UScrollBox> TranscriptScroll;

	UPROPERTY()
	TObjectPtr<UVerticalBox> TranscriptBox;

	UPROPERTY()
	TObjectPtr<UTextBlock> TurnErrorText;

	UPROPERTY()
	TObjectPtr<UEditableTextBox> TurnInput;

	UPROPERTY()
	TObjectPtr<UButton> SendButton;

	UPROPERTY()
	TObjectPtr<UVerticalBox> ExamPanel;

	UPROPERTY()
	TObjectPtr<UVerticalBox> ExamRequestBox;

	UPROPERTY()
	TObjectPtr<UVerticalBox> DocumentBox;

	UPROPERTY()
	TObjectPtr<UTextBlock> NoDocumentText;

	UPROPERTY()
	TObjectPtr<UTextBlock> ExamErrorText;

	UPROPERTY()
	TObjectPtr<UEditableTextBox> ExamInput;

	UPROPERTY()
	TObjectPtr<UButton> ExamButton;

	UPROPERTY()
	TObjectPtr<UTextBlock> ModeText;

	UPROPERTY()
	TObjectPtr<UTextBlock> TimerText;

	UPROPERTY()
	TObjectPtr<UTextBlock> FallbackText;

	UPROPERTY()
	TObjectPtr<UTextBlock> VoiceStatusText;

	UPROPERTY()
	TObjectPtr<UButton> FinishButton;
};

/** A training that lost Phoenix (#196): it is over, with nothing to show but the restart. */
UCLASS()
class UStationInvalidatedWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	FSimpleDelegate OnRestart;

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	UFUNCTION()
	void HandleRestart();
};

UCLASS()
class UStationFeedbackWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	void SetFlow(UStationRunFlow* InFlow) { Flow = InFlow; }

	/** Re-reads the flow: grading in progress, the feedback or why it is missing, and the discard. */
	void Refresh();

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	void AddCriterion(int32 Ordinal, const FStationCriterionResult& Criterion);

	UFUNCTION()
	void HandleRestart();

	UPROPERTY()
	TObjectPtr<UStationRunFlow> Flow;

	UPROPERTY()
	TObjectPtr<UVerticalBox> LoadingBox;

	UPROPERTY()
	TObjectPtr<UTextBlock> ErrorText;

	UPROPERTY()
	TObjectPtr<UTextBlock> RestartNote;

	UPROPERTY()
	TObjectPtr<UVerticalBox> ResultBox;

	UPROPERTY()
	TObjectPtr<UTextBlock> SessionNote;

	UPROPERTY()
	TObjectPtr<UButton> RestartButton;
};
