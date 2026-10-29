#include "Station/StationPlayerController.h"

#include "Blueprint/UserWidget.h"
#include "Animation/AnimSequence.h"
#include "Camera/CameraActor.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/GameInstance.h"
#include "EngineUtils.h"
#include "Kismet/KismetSystemLibrary.h"
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
	Menu->OnModeChosen.BindWeakLambda(this, [this](EStationSessionMode Mode) { Flow->ChooseMode(Mode); });
	Menu->OnQuit.BindWeakLambda(this, [this]() { UKismetSystemLibrary::QuitGame(this, this, EQuitPreference::Quit, false); });
	Notice->OnAcknowledged.BindWeakLambda(this, [this]() { Flow->AcknowledgeNotice(); });
	MicrophoneScreen->OnAnswered.BindWeakLambda(this, [this](bool bAllow) { Flow->AnswerMicrophone(bAllow); });
	Invalidated->OnRestart.BindWeakLambda(this, [this]() { Flow->Restart(); });
	MicrophoneScreen->AddToViewport();
	Menu->AddToViewport();
	Notice->AddToViewport();
	Brief->AddToViewport();
	Hud->AddToViewport();
	Feedback->AddToViewport();
	Invalidated->AddToViewport();

	Microphone = NewObject<UStationMicrophone>(this);
	PreparePatientVoice();

	bShowMouseCursor = true;
	Flow->OnChanged.AddUObject(this, &AStationPlayerController::Render);
	Flow->Begin(Subsystem->GetClient());
	Render();
}

void AStationPlayerController::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	if (Microphone)
	{
		Microphone->Stop();
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

	const EStationRunStep Step = Flow->GetStep();
	const bool bRunning = Step == EStationRunStep::Running;
	MicrophoneScreen->SetVisibility(Step == EStationRunStep::Microphone ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	Menu->SetVisibility(Step == EStationRunStep::Menu ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	Notice->SetVisibility(Step == EStationRunStep::Notice ? ESlateVisibility::Visible : ESlateVisibility::Collapsed);
	Brief->SetVisibility(Step == EStationRunStep::Brief || Step == EStationRunStep::Starting
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
	UpdateMicrophone();
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
