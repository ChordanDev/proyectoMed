#include "Station/StationPlayerController.h"

#include "Blueprint/UserWidget.h"
#include "Animation/AnimSequence.h"
#include "Camera/CameraActor.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"
#include "Framework/Application/NavigationConfig.h"
#include "Framework/Application/SlateApplication.h"
#include "Kismet/KismetSystemLibrary.h"
#include "Station/StationDeskClock.h"
#include "Station/StationRunFlow.h"
#include "Station/StationScreens.h"
#include "Station/Voice/StationMicrophone.h"
#include "Station/Voice/StationPatientVoice.h"
#include "StationClient.h"
#include "StationClientSubsystem.h"

DEFINE_LOG_CATEGORY_STATIC(LogStationPlayer, Log, All);

const FName AStationPlayerController::StationViewTag(TEXT("StationView"));
const FName AStationPlayerController::MenuViewTag(TEXT("MenuView"));

namespace
{
	/** The MetaHuman Blueprint names its face mesh component `Face`. */
	const FName FaceComponentName(TEXT("Face"));
}

void AStationPlayerController::BeginPlay()
{
	Super::BeginPlay();
	if (!IsLocalController())
	{
		return;
	}

	StationCamera = FindCamera(StationViewTag);
	MenuCamera = FindCamera(MenuViewTag);
	if (!StationCamera.IsValid())
	{
		UE_LOG(LogStationPlayer, Warning, TEXT("No camera tagged '%s' in this level; the view stays at the controller."),
			*StationViewTag.ToString());
	}

	UStationClientSubsystem* Subsystem = GetGameInstance()->GetSubsystem<UStationClientSubsystem>();
	Flow = NewObject<UStationRunFlow>(this);

	MicrophoneScreen = CreateWidget<UStationMicrophoneWidget>(this, UStationMicrophoneWidget::StaticClass());
	Menu = CreateWidget<UStationMenuWidget>(this, UStationMenuWidget::StaticClass());
	Notice = CreateWidget<UStationNoticeWidget>(this, UStationNoticeWidget::StaticClass());
	Brief = CreateWidget<UStationBriefWidget>(this, UStationBriefWidget::StaticClass());
	Hud = CreateWidget<UStationHudWidget>(this, UStationHudWidget::StaticClass());
	Feedback = CreateWidget<UStationFeedbackWidget>(this, UStationFeedbackWidget::StaticClass());
	Invalidated = CreateWidget<UStationInvalidatedWidget>(this, UStationInvalidatedWidget::StaticClass());
	Brief->SetFlow(Flow);
	Hud->SetFlow(Flow);
	Feedback->SetFlow(Flow);
	Invalidated->SetFlow(Flow);
	Menu->OnModeChosen.BindWeakLambda(this, [this](EStationSessionMode Mode) { Flow->ChooseMode(Mode); });
	Menu->OnQuit.BindWeakLambda(this, [this]() { UKismetSystemLibrary::QuitGame(this, this, EQuitPreference::Quit, false); });
	Notice->OnAcknowledged.BindWeakLambda(this, [this]() { Flow->AcknowledgeNotice(); });
	MicrophoneScreen->OnAnswered.BindWeakLambda(this, [this](bool bAllow) { Flow->AnswerMicrophone(bAllow); });
	Invalidated->OnRestart.BindWeakLambda(this, [this]() { Flow->Restart(); });
	MicrophoneScreen->AddToViewport();
	Menu->AddToViewport();
	Notice->AddToViewport();
	Hud->AddToViewport();
	// Over the HUD: a running simulated exam shows its brief over the room (#425).
	Brief->AddToViewport(1);
	Feedback->AddToViewport();
	Invalidated->AddToViewport();

	Microphone = NewObject<UStationMicrophone>(this);
	PreparePatientVoice();

	// The room's clock and its start and end beeps (#425).
	TActorIterator<AStationDeskClock> Clock(GetWorld());
	DeskClock = Clock ? *Clock : nullptr;
	Flow->OnExamCue.AddWeakLambda(this, [this](EStationExamCue Cue)
	{
		if (AStationDeskClock* Room = DeskClock.Get())
		{
			Room->PlayCue(Cue);
		}
	});

	if (FSlateApplication::IsInitialized())
	{
		// The space bar is the talk key (#419): it must not also press the focused button.
		PreviousNavigation = FSlateApplication::Get().GetNavigationConfig();
		TSharedRef<FNavigationConfig> Navigation = MakeShared<FNavigationConfig>();
		Navigation->KeyActionRules.Remove(EKeys::SpaceBar);
		FSlateApplication::Get().SetNavigationConfig(Navigation);
		ActivationHandle = FSlateApplication::Get().OnApplicationActivationStateChanged()
			.AddUObject(this, &AStationPlayerController::HandleActivation);
	}

	bShowMouseCursor = true;
	Flow->OnChanged.AddUObject(this, &AStationPlayerController::Render);
	Flow->Begin(Subsystem->GetClient());
	Render();
}

void AStationPlayerController::PlayerTick(float DeltaTime)
{
	Super::PlayerTick(DeltaTime);
	if (Flow && DeskClock.IsValid())
	{
		DeskClock->ShowTime(Flow->GetDeskClockTime());
	}
}

void AStationPlayerController::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (Microphone)
	{
		Microphone->Stop();
	}
	if (FSlateApplication::IsInitialized())
	{
		FSlateApplication::Get().OnApplicationActivationStateChanged().Remove(ActivationHandle);
		if (PreviousNavigation)
		{
			FSlateApplication::Get().SetNavigationConfig(PreviousNavigation.ToSharedRef());
		}
	}
	// A run left mid-way or on its feedback is ephemeral: ask Phoenix to forget
	// it now instead of waiting for the session to expire.
	if (Flow && Flow->GetClient() && Flow->GetClient()->GetSession())
	{
		Flow->GetClient()->DiscardSession([](const TStationResult<FStationNone>&) {});
	}
	Super::EndPlay(EndPlayReason);
}

void AStationPlayerController::Render()
{
	if (!Flow || !Menu || !Notice || !Brief || !Hud || !Feedback || !Invalidated || !MicrophoneScreen)
	{
		return;
	}

	// First, since it can change the run: a microphone that will not open invalidates
	// a simulated exam (#422), which renders again inside this call. What follows then
	// reads the step that change left, not the one before it (Jorge J2 on #441).
	if (MicrophoneUpdate)
	{
		MicrophoneUpdate();
	}
	else
	{
		UpdateMicrophone();
	}

	const EStationRunStep Step = Flow->GetStep();
	const bool bRunning = Step == EStationRunStep::Running;
	MicrophoneScreen->SetVisibility(Step == EStationRunStep::Microphone ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	Menu->SetVisibility(Step == EStationRunStep::Menu ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	Notice->SetVisibility(Step == EStationRunStep::Notice ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	Brief->SetVisibility(Step == EStationRunStep::Brief || Step == EStationRunStep::Starting || Flow->IsBriefOpen()
		? ESlateVisibility::Visible
		: ESlateVisibility::Collapsed);
	Hud->SetVisibility(bRunning ? ESlateVisibility::SelfHitTestInvisible : ESlateVisibility::Collapsed);
	Feedback->SetVisibility(Step == EStationRunStep::Finishing || Step == EStationRunStep::Feedback
		? ESlateVisibility::Visible
		: ESlateVisibility::Collapsed);
	Invalidated->SetVisibility(Step == EStationRunStep::Invalidated ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	Brief->Refresh();
	Hud->Refresh();
	Feedback->Refresh();
	Invalidated->Refresh();
	UpdateCamera();

	// Only when the run starts or ends: applying an input mode releases the mouse
	// capture and moves the focus, which would let go of a held button (#364) or
	// leave a text box mid-word on every change of the run.
	if (!bAppliedRunInputMode.IsSet() || *bAppliedRunInputMode != bRunning)
	{
		bAppliedRunInputMode = bRunning;
		if (bRunning)
		{
			SetInputMode(FInputModeGameAndUI());
		}
		else
		{
			SetInputMode(FInputModeUIOnly());
		}
	}
}

void AStationPlayerController::PreparePatientVoice()
{
	for (TActorIterator<AActor> It(GetWorld()); It; ++It)
	{
		for (UActorComponent* Component : It->GetComponents())
		{
			USkeletalMeshComponent* Face = Cast<USkeletalMeshComponent>(Component);
			if (!Face || Face->GetFName() != FaceComponentName)
			{
				continue;
			}
			PatientVoice = NewObject<UStationPatientVoice>(*It);
			PatientVoice->RegisterComponent();
			// Speech layers over whatever idle loop the scene gives the face.
			UAnimSequence* Idle = Cast<UAnimSequence>(Face->AnimationData.AnimToPlay);
			TWeakObjectPtr<UStationPatientVoice> WeakVoice = PatientVoice;
			TWeakObjectPtr<USkeletalMeshComponent> WeakFace = Face;
			TWeakObjectPtr<UAnimSequence> WeakIdle = Idle;
			const TSharedRef<FStationPatientAudioSink, ESPMode::ThreadSafe> Sink = PatientVoice->GetSink();
			FStationPatientOutput Patient;
			Patient.Audio = [Sink](TConstArrayView<int16> Samples, int32 SampleRate, int32 NumChannels)
			{
				Sink->Handle(Samples, SampleRate, NumChannels);
			};
			Patient.Silence = [Sink]() { Sink->Silence(); };
			Patient.Resume = [Sink]() { Sink->Resume(); };
			Flow->SetPatientOutput(MoveTemp(Patient));
			Flow->OnChanged.AddWeakLambda(this, [this, WeakVoice, WeakFace, WeakIdle]()
			{
				UStationPatientVoice* Voice = WeakVoice.Get();
				const bool bSpeaking = Flow->GetStep() == EStationRunStep::Running && Flow->GetVoiceCredential() != nullptr;
				if (Voice && bSpeaking && !Voice->IsStarted())
				{
					Voice->Start(WeakFace.Get(), WeakIdle.Get());
				}
			});
			return;
		}
	}
	UE_LOG(LogStationPlayer, Warning, TEXT("No patient face (a skeletal mesh component named '%s') in this level; the patient will be silent."),
		*FaceComponentName.ToString());
}

void AStationPlayerController::SetupInputComponent()
{
	Super::SetupInputComponent();
	InputComponent->BindKey(EKeys::SpaceBar, IE_Pressed, this, &AStationPlayerController::PressTalkKey);
	InputComponent->BindKey(EKeys::SpaceBar, IE_Released, this, &AStationPlayerController::ReleaseTalkKey);
	// Shift + space bar asks for an exam aloud; this chord masks the plain space bar.
	const FInputChord ExamChord(EKeys::SpaceBar, /*bShift*/ true, false, false, false);
	InputComponent->BindKey(ExamChord, IE_Pressed, this, &AStationPlayerController::PressExamTalkKey);
	InputComponent->BindKey(ExamChord, IE_Released, this, &AStationPlayerController::ReleaseTalkKey);
}

void AStationPlayerController::PressTalkKey()
{
	if (Flow && !IsTyping())
	{
		Flow->PressTalkKey();
	}
}

void AStationPlayerController::PressExamTalkKey()
{
	if (Flow && !IsTyping())
	{
		Flow->PressTalkKey(/*bForExam*/ true);
	}
}

bool AStationPlayerController::IsTyping()
{
	// A text box takes the space as a character, and Slate still hands its key-down to the game.
	const TSharedPtr<SWidget> Focused = FSlateApplication::IsInitialized()
		? FSlateApplication::Get().GetKeyboardFocusedWidget()
		: nullptr;
	return Focused
		&& (Focused->GetType() == TEXT("SEditableText") || Focused->GetType() == TEXT("SMultiLineEditableText"));
}

void AStationPlayerController::ReleaseTalkKey()
{
	if (Flow)
	{
		Flow->ReleaseTalkKey();
	}
}

void AStationPlayerController::HandleActivation(bool bIsActive)
{
	if (!bIsActive)
	{
		ReleaseTalkKey();
	}
}

void AStationPlayerController::UpdateMicrophone()
{
	UStationClient* Client = Flow ? Flow->GetClient() : nullptr;
	FStationVoiceLink* Voice = Client ? Client->GetVoice() : nullptr;
	const bool bInRoom = Voice && Flow->IsListening();
	if (bInRoom && !Microphone->IsCapturing())
	{
		if (!Microphone->Start(Voice->AsShared()))
		{
			// Remembered for the run, so the next change does not try the device again.
			Flow->ReportMicrophoneUnavailable();
		}
	}
	else if (!bInRoom && Microphone->IsCapturing())
	{
		Microphone->Stop();
	}
}

AActor* AStationPlayerController::FindCamera(const FName& Tag) const
{
	for (TActorIterator<ACameraActor> It(GetWorld()); It; ++It)
	{
		if (It->ActorHasTag(Tag))
		{
			return *It;
		}
	}
	return nullptr;
}

void AStationPlayerController::UpdateCamera()
{
	AActor* Wanted = Flow->GetStep() == EStationRunStep::Menu && MenuCamera.IsValid() ? MenuCamera.Get() : StationCamera.Get();
	if (Wanted && GetViewTarget() != Wanted)
	{
		SetViewTarget(Wanted);
	}
}
