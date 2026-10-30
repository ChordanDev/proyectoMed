// The station's native UMG screens: the first-launch microphone disclosure,
// the main menu (#421), Pre-Station Notice, brief, the in-run HUD with the Station Timer, the voice
// status, the conversation and the exam panel, and the feedback once the run
// ends. They render UStationRunFlow and never call the network.

#pragma once

#include "Blueprint/UserWidget.h"
#include "CoreMinimal.h"

#include "StationScreens.generated.h"

class UBorder;
class UButton;
class UEditableTextBox;
class UHorizontalBox;
class UOverlay;
class UScrollBox;
class UStationRunFlow;
class UTextBlock;
class UVerticalBox;
class UWidget;
enum class EStationSpeaker : uint8;
struct FStationExamRequest;
enum class EStationSessionMode : uint8;
struct FStationImpresso;
struct FStationResult;

/** The pt-BR name of a Prova simulada's certainty level, from "Certeira" (5) to "Insuficiente" (1). */
FText StationCertaintyLabel(int32 Level);

/** What a Prova simulada's result says when criteria were left out, naming them; empty when none was. */
FText StationIncompleteNotice(const FStationResult& Result);

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

/**
 * The main menu, like a game's title screen (#421): the learner chooses a training
 * or a simulated exam, over the consultation room seen from the menu camera.
 */
UCLASS()
class UStationMenuWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	TDelegate<void(EStationSessionMode)> OnModeChosen;

	/** The learner leaves the app. */
	FSimpleDelegate OnQuit;

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	friend class FStationBriefUnitSpec;

	UFUNCTION()
	void HandleTraining();

	UFUNCTION()
	void HandleSimulatedExam();

	UFUNCTION()
	void HandleQuit();

	/** A solid background that hides the scene until the office behind the menu exists (#431). */
	UPROPERTY()
	TObjectPtr<UBorder> Backdrop;

	UPROPERTY()
	TObjectPtr<UButton> TrainingButton;

	UPROPERTY()
	TObjectPtr<UButton> SimulatedExamButton;

	/** Shown, disabled, until the settings exist. */
	UPROPERTY()
	TObjectPtr<UButton> SettingsButton;

	UPROPERTY()
	TObjectPtr<UButton> QuitButton;
};

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

	/**
	 * Re-reads the flow: loading, error, the station brief, and the chosen mode's way
	 * in: which trainings can start, or whether the simulated exam can and why not (#421).
	 */
	void Refresh();

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	friend class FStationBriefUnitSpec;

	UFUNCTION()
	void HandleTextTraining();

	UFUNCTION()
	void HandleVoiceTraining();

	UFUNCTION()
	void HandleSimulatedExam();

	UFUNCTION()
	void HandleBackToMenu();

	UFUNCTION()
	void HandleRetry();

	/** Back to the room from a running simulated exam's brief (#425). */
	UFUNCTION()
	void HandleCloseBrief();

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

	/** Under the scrolling brief, so the trainings stay in view however long it runs. */
	UPROPERTY()
	TObjectPtr<UVerticalBox> FooterBox;

	/** Back to the main menu (#421). */
	UPROPERTY()
	TObjectPtr<UButton> MenuButton;

	/** Names the chosen mode. */
	UPROPERTY()
	TObjectPtr<UTextBlock> HeadingText;

	/** A training's two ways in: by text and by voice. */
	UPROPERTY()
	TObjectPtr<UHorizontalBox> TrainingsRow;

	/** When the time starts, and in a simulated exam when its scenario and tasks show (#425). */
	UPROPERTY()
	TObjectPtr<UTextBlock> TimerNote;

	/** A simulated exam's one way in ("Prova simulada", #421), by voice. */
	UPROPERTY()
	TObjectPtr<UButton> SimulatedExamButton;

	/** Back to the room, over which a running simulated exam shows its brief (#425). */
	UPROPERTY()
	TObjectPtr<UButton> CloseButton;

	/** What a simulated exam is, or why it cannot start. */
	UPROPERTY()
	TObjectPtr<UTextBlock> SimulatedExamNote;

	UPROPERTY()
	TObjectPtr<UButton> TextButton;

	UPROPERTY()
	TObjectPtr<UButton> VoiceButton;

	UPROPERTY()
	TObjectPtr<UTextBlock> VoiceNote;
};

/** One criterion's row in a Prova simulada's result: a click opens or closes what it holds. */
UCLASS()
class UStationCriterionRow : public UObject
{
	GENERATED_BODY()

public:
	UPROPERTY()
	TObjectPtr<UWidget> Details;

	UFUNCTION()
	void HandleClicked();
};

/** The "open" link of one released document: tells the HUD which one to show. */
UCLASS()
class UStationDocumentLink : public UObject
{
	GENERATED_BODY()

public:
	TWeakObjectPtr<class UStationHudWidget> Hud;
	FString ImpressoId;

	UFUNCTION()
	void HandleClicked();
};

UCLASS()
class UStationHudWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	void SetFlow(UStationRunFlow* InFlow) { Flow = InFlow; }

	/** Re-reads the training mode, the voice fallback notice, the conversation and the exam panel. */
	void Refresh();

	/** Shows a released document in the reader over the scene. */
	void OpenDocument(const FString& ImpressoId);

	/** Opens the side panel of the exam requests, in place of its tab. */
	void OpenExams();

	/** Closes the side panel of the exam requests and shows its tab again. */
	void CloseExams();

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeTick(const FGeometry& MyGeometry, float InDeltaTime) override;

private:
	// Test access: the HUD's states as images (StationHudSnapshotSpec.cpp) and
	// what it shows (StationHudSpec.cpp).
	friend class FStationHudSnapshotSpec;
	friend class FStationHudUnitSpec;

	void BuildConversation(UOverlay& Root);
	void RefreshConversation();
	/** One message of the conversation; `bInProgress` for a turn still being said or sent. */
	void AddMessage(EStationSpeaker Speaker, const FString& Text, bool bInProgress);
	void SendTypedTurn();
	void BuildExamTab(UOverlay& Root);
	void BuildExamDrawer(UOverlay& Root);
	void BuildMicrophone(UVerticalBox& Footer);
	void BuildDocumentViewer(UOverlay& Root);
	void RefreshExams();
	/** Rebuilds the request cards, only when what they show changed, so a hovered card keeps its state. */
	void RefreshExamCards();
	void AddExamCard(const FStationExamRequest& Request);
	void AddPendingExamCard(const FString& Text);
	/** A link that opens `Impresso`, labelled with its title unless `Label` is given. */
	void AddDocumentLink(UVerticalBox& Parent, const FStationImpresso& Impresso, const FText& Label = FText::GetEmpty());

	/** The microphone's look: idle, arming or recording, with the recording time. */
	void RefreshMicrophone();
	/** The talk button's label and look (#419): idle, talking, or how to cut the patient. */
	void RefreshTalk();
	void RequestExam();

	UFUNCTION()
	void HandleSend();

	UFUNCTION()
	void HandleTurnCommitted(const FText& Text, ETextCommit::Type CommitMethod);

	UFUNCTION()
	void HandleOpenExams();

	UFUNCTION()
	void HandleCloseExams();

	UFUNCTION()
	void HandleCloseDocument();

	UFUNCTION()
	void HandleRequestExam();

	UFUNCTION()
	void HandlePressTalk();

	UFUNCTION()
	void HandleReleaseTalk();

	UFUNCTION()
	void HandleAskExamAloud();

	UFUNCTION()
	void HandleReleaseExamAloud();

	UFUNCTION()
	void HandleExamCommitted(const FText& Text, ETextCommit::Type CommitMethod);

	UFUNCTION()
	void HandleFinish();

	/** A simulated exam's brief, over the room (#425). */
	UFUNCTION()
	void HandleOpenBrief();

	UPROPERTY()
	TObjectPtr<UStationRunFlow> Flow;

	UPROPERTY()
	TObjectPtr<UScrollBox> TranscriptScroll;

	UPROPERTY()
	TObjectPtr<UVerticalBox> TranscriptBox;

	UPROPERTY()
	TObjectPtr<UTextBlock> TurnErrorText;

	/** The typed turn: `TurnInput` and `SendButton`, hidden in a simulated exam (#422). */
	UPROPERTY()
	TObjectPtr<UWidget> TurnRow;

	UPROPERTY()
	TObjectPtr<UEditableTextBox> TurnInput;

	UPROPERTY()
	TObjectPtr<UButton> SendButton;

	/** Push-to-talk (#419): held, like the space bar, to talk to the patient. */
	UPROPERTY()
	TObjectPtr<UButton> TalkButton;

	UPROPERTY()
	TObjectPtr<UTextBlock> TalkText;

	/** Whether the talk button is styled as talking; unset before its first style. */
	TOptional<bool> TalkLookTalking;

	UPROPERTY()
	TObjectPtr<UButton> ExamTab;

	UPROPERTY()
	TObjectPtr<UTextBlock> ExamTabText;

	UPROPERTY()
	TObjectPtr<UWidget> ExamDrawer;

	UPROPERTY()
	TObjectPtr<UVerticalBox> ExamCardBox;

	UPROPERTY()
	TObjectPtr<UTextBlock> ExamErrorText;

	UPROPERTY()
	TObjectPtr<UWidget> ExamTypedRow;

	UPROPERTY()
	TObjectPtr<UEditableTextBox> ExamInput;

	UPROPERTY()
	TObjectPtr<UButton> ExamButton;

	UPROPERTY()
	TObjectPtr<UWidget> MicrophoneBox;

	UPROPERTY()
	TObjectPtr<UButton> AskAloudButton;

	UPROPERTY()
	TObjectPtr<UBorder> MicrophoneRing;

	UPROPERTY()
	TObjectPtr<UTextBlock> ExamAloudText;

	UPROPERTY()
	TObjectPtr<UWidget> DocumentViewer;

	UPROPERTY()
	TObjectPtr<UTextBlock> DocumentCategoryText;

	UPROPERTY()
	TObjectPtr<UTextBlock> DocumentTitleText;

	UPROPERTY()
	TObjectPtr<UScrollBox> DocumentScroll;

	UPROPERTY()
	TObjectPtr<UVerticalBox> DocumentBody;

	/** One per "open" link of the current cards; rebuilt with them. */
	UPROPERTY()
	TArray<TObjectPtr<UStationDocumentLink>> DocumentLinks;

	/** What the conversation last showed (`RefreshConversation`). */
	FString ConversationKey;

	/** What the request cards last showed (`RefreshExamCards`). */
	FString ExamCardsKey;

	/** The learner holds the microphone button. */
	bool bMicrophoneHeld = false;

	/** The flow took the current press; a refused one never records. */
	bool bMicrophoneAccepted = false;

	/** `Waiting`: held while the previous spoken request still waits for Phoenix. */
	enum class EMicrophoneLook : uint8 { Idle, Waiting, Arming, Recording };
	EMicrophoneLook MicrophoneLook = EMicrophoneLook::Idle;

	/** `FPlatformTime::Seconds()` when the current recording started. */
	double RecordingSince = 0.0;

	UPROPERTY()
	TObjectPtr<UTextBlock> ModeText;

	/** The Station Timer; a simulated exam has the desk clock instead (#425). */
	UPROPERTY()
	TObjectPtr<UTextBlock> TimerText;

	/** Opens a simulated exam's brief where a training shows its timer (#425). */
	UPROPERTY()
	TObjectPtr<UButton> BriefButton;

	UPROPERTY()
	TObjectPtr<UTextBlock> FallbackText;

	UPROPERTY()
	TObjectPtr<UTextBlock> VoiceStatusText;

	UPROPERTY()
	TObjectPtr<UButton> FinishButton;
};

/**
 * A run that lost Phoenix (#196), or a simulated exam that lost its voice (#422): it is
 * over, with nothing to show but why and the restart.
 */
UCLASS()
class UStationInvalidatedWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	FSimpleDelegate OnRestart;

	void SetFlow(UStationRunFlow* InFlow) { Flow = InFlow; }
	/** Names the run's Station Mode and why it ended. */
	void Refresh();

protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;

private:
	friend class FStationHudUnitSpec;

	UFUNCTION()
	void HandleRestart();

	UPROPERTY()
	TObjectPtr<UStationRunFlow> Flow;

	UPROPERTY()
	TObjectPtr<UTextBlock> TitleText;

	UPROPERTY()
	TObjectPtr<UTextBlock> BodyText;
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
	friend class FStationHudUnitSpec;

	void AddSummary(const FStationResult& Result);
	void AddCriterion(int32 Ordinal, const FStationCriterionResult& Criterion);
	/** What a criterion's card ends with in either mode: its level, evidence and recommendation. */
	void AddCriterionDetails(UVerticalBox& Card, const FStationCriterionResult& Criterion, int32 TextSize);

	// A Prova simulada's result (#426), laid out as docs/design/screens/html/ResultExam.dc.html.

	/** The screen, with no result in it yet. */
	UWidget* BuildExamScreen();
	void ShowExamResult(const FStationResult& Result);
	void AddExamSummary(const FStationResult& Result);
	void AddExamCriterion(int32 Ordinal, const FStationCriterionResult& Criterion);

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

	/** Under the scrolling result, so the restart stays in view however many criteria there are. */
	UPROPERTY()
	TObjectPtr<UVerticalBox> FooterBox;

	UPROPERTY()
	TObjectPtr<UButton> RestartButton;

	/** Everything but a Prova simulada's result: grading, its failures and a training's result. */
	UPROPERTY()
	TObjectPtr<UWidget> CardScreen;

	UPROPERTY()
	TObjectPtr<UWidget> ExamScreen;

	/** "Exemplo — dados fictícios" over a placeholder result. */
	UPROPERTY()
	TObjectPtr<UWidget> ExamSampleMark;

	/** The total and its certainty, in the left column. */
	UPROPERTY()
	TObjectPtr<UVerticalBox> ExamSummaryBox;

	/** One lit segment per certainty level. */
	UPROPERTY()
	TObjectPtr<UHorizontalBox> ExamMeter;

	UPROPERTY()
	TObjectPtr<UTextBlock> ExamErrorText;

	UPROPERTY()
	TObjectPtr<UButton> ExamBackButton;

	UPROPERTY()
	TObjectPtr<UTextBlock> ExamPointsText;

	UPROPERTY()
	TObjectPtr<UVerticalBox> ExamCriteriaBox;

	/** Keeps each row's click handler alive with the row. */
	UPROPERTY()
	TArray<TObjectPtr<UStationCriterionRow>> ExamRows;
};
