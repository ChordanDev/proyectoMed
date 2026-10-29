// Renders the full-screen cards around the run (microphone disclosure, notice,
// brief, invalidated run, feedback) to PNG files, to look at their design
// without playing a run to each one. Runs only with an RHI and
// when $STATION_HUD_SNAPSHOT_DIR names the folder for the images:
//   STATION_HUD_SNAPSHOT_DIR=/tmp/hud UnrealEditor ProyectoMed.uproject \
//     -ExecCmds="Automation RunTests ProyectoMed.StationCards.Snapshot; Quit" -unattended
// It asserts nothing about the look; the images are for a person to judge.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Blueprint/UserWidget.h"
#include "Blueprint/WidgetTree.h"
#include "Components/ScrollBox.h"
#include "Engine/Engine.h"
#include "Engine/TextureRenderTarget2D.h"
#include "ImageUtils.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "RenderingThread.h"
#include "Slate/WidgetRenderer.h"
#include "Station/StationRunFlow.h"
#include "Station/StationScreens.h"
#include "TextureResource.h"
#include "Widgets/Colors/SColorBlock.h"
#include "Widgets/SOverlay.h"

BEGIN_DEFINE_SPEC(FStationCardSnapshotSpec, "ProyectoMed.StationCards.Snapshot",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	FString OutDir;

	UStationRunFlow* MakeFlow(EStationMicPermission Permission) const;
	UStationBriefWidget* MakeBrief(UStationRunFlow* Flow) const;
	UStationFeedbackWidget* MakeFeedback(UStationRunFlow* Flow) const;
	void Save(UUserWidget* Screen, const FString& Name);
END_DEFINE_SPEC(FStationCardSnapshotSpec)

UStationRunFlow* FStationCardSnapshotSpec::MakeFlow(EStationMicPermission Permission) const
{
	// The brief of the reference station (backend/priv/stations/acute-appendicitis).
	FStationSummary Station;
	Station.DisplayTitle = TEXT("Abdome agudo inflamatório — apendicite aguda");
	Station.Scenario = TEXT("Você é o médico ou a médica de plantão em um pronto-socorro de hospital geral. "
		"Rafael Nogueira, 27 anos, auxiliar administrativo, chega sem acompanhante e procura atendimento por dor abdominal.");
	Station.Tasks = {
		TEXT("Apresentar-se, confirmar a identificação do paciente e obter anamnese dirigida."),
		TEXT("Solicitar e interpretar o exame físico abdominal e as manobras pertinentes."),
		TEXT("Solicitar e interpretar exames laboratoriais e de imagem adequados ao caso."),
		TEXT("Formular a hipótese diagnóstica principal e indicar medidas de suporte e tratamento inicial."),
		TEXT("Explicar a necessidade de avaliação cirúrgica e tratamento definitivo, respondendo às dúvidas do paciente."),
	};
	Station.VoiceMode = EStationVoiceMode::Realtime;

	UStationRunFlow* Flow = NewObject<UStationRunFlow>();
	Flow->Step = EStationRunStep::Brief;
	Flow->Station = Station;
	Flow->Microphone.GetPermission = [Permission]() { return Permission; };
	return Flow;
}

UStationBriefWidget* FStationCardSnapshotSpec::MakeBrief(UStationRunFlow* Flow) const
{
	UWorld* World = GEngine->GetWorldContexts()[0].World();
	UStationBriefWidget* Brief = CreateWidget<UStationBriefWidget>(World);
	Brief->TakeWidget();
	Brief->SetFlow(Flow);
	Brief->Refresh();
	return Brief;
}

UStationFeedbackWidget* FStationCardSnapshotSpec::MakeFeedback(UStationRunFlow* Flow) const
{
	UWorld* World = GEngine->GetWorldContexts()[0].World();
	UStationFeedbackWidget* Feedback = CreateWidget<UStationFeedbackWidget>(World);
	Feedback->TakeWidget();
	Feedback->SetFlow(Flow);
	Feedback->Refresh();
	return Feedback;
}

void FStationCardSnapshotSpec::Save(UUserWidget* Screen, const FString& Name)
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

void FStationCardSnapshotSpec::Define()
{
	BeforeEach([this]()
	{
		OutDir = FPlatformMisc::GetEnvironmentVariable(TEXT("STATION_HUD_SNAPSHOT_DIR"));
	});

	It("renders the microphone disclosure, the notice and the brief", [this]()
	{
		if (OutDir.IsEmpty() || !FApp::CanEverRender())
		{
			AddInfo(TEXT("Skipped: set STATION_HUD_SNAPSHOT_DIR and run with an RHI."));
			return;
		}

		UWorld* World = GEngine->GetWorldContexts()[0].World();
		Save(CreateWidget<UStationMicrophoneWidget>(World), TEXT("pre-1-microphone"));
		Save(CreateWidget<UStationNoticeWidget>(World), TEXT("pre-2-notice"));
		Save(MakeBrief(MakeFlow(EStationMicPermission::NotDetermined)), TEXT("pre-3-brief"));
		Save(MakeBrief(MakeFlow(EStationMicPermission::Denied)), TEXT("pre-4-brief-microphone-blocked"));

		UStationRunFlow* Loading = MakeFlow(EStationMicPermission::NotDetermined);
		Loading->Station.Reset();
		Loading->bLoadingStation = true;
		Save(MakeBrief(Loading), TEXT("pre-5-brief-loading"));

		UStationRunFlow* Failed = MakeFlow(EStationMicPermission::NotDetermined);
		Failed->Station.Reset();
		Failed->ErrorText = FText::FromString(TEXT("Não foi possível carregar o cenário e as tarefas da estação."));
		Save(MakeBrief(Failed), TEXT("pre-6-brief-error"));
	});

	It("renders the invalidated run and the feedback", [this]()
	{
		if (OutDir.IsEmpty() || !FApp::CanEverRender())
		{
			AddInfo(TEXT("Skipped: set STATION_HUD_SNAPSHOT_DIR and run with an RHI."));
			return;
		}

		UWorld* World = GEngine->GetWorldContexts()[0].World();
		Save(CreateWidget<UStationInvalidatedWidget>(World), TEXT("post-1-invalidated"));

		UStationRunFlow* Finishing = MakeFlow(EStationMicPermission::Granted);
		Finishing->Step = EStationRunStep::Finishing;
		Save(MakeFeedback(Finishing), TEXT("post-2-feedback-loading"));

		FStationCriterionResult Assessed;
		Assessed.Description = TEXT("Apresenta-se e confirma a identificação do paciente.");
		Assessed.Status = EStationCriterionStatus::Assessed;
		Assessed.LevelDescription = TEXT("Adequado: apresenta-se e confirma nome e idade.");
		Assessed.Points = TEXT("0.5");
		Assessed.MaxPoints = TEXT("0.5");
		FStationEvidence Excerpt;
		Excerpt.Speaker = EStationSpeaker::Learner;
		Excerpt.Text = TEXT("Bom dia, eu sou o doutor. Qual é o seu nome?");
		Assessed.Evidence.Add(Excerpt);
		Assessed.Recommendation = TEXT("Mantenha a apresentação no início do atendimento.");
		FStationCriterionResult Uncertain;
		Uncertain.Description = TEXT("Pesquisa sinais de irritação peritoneal.");
		Uncertain.Status = EStationCriterionStatus::Uncertain;
		Uncertain.Recommendation = TEXT("Solicite o exame físico do abdome e as manobras pertinentes.");

		FStationResult Result;
		Result.Criteria = {Assessed, Uncertain};
		Result.ScoredSubtotal = TEXT("0.5");
		Result.ScoredMax = TEXT("0.5");
		Result.EligibleMax = TEXT("1.5");

		UStationRunFlow* Graded = MakeFlow(EStationMicPermission::Granted);
		Graded->Step = EStationRunStep::Feedback;
		Graded->Result = Result;
		Save(MakeFeedback(Graded), TEXT("post-3-feedback"));

		UStationFeedbackWidget* Scrolled = MakeFeedback(Graded);
		Scrolled->WidgetTree->ForEachWidget([](UWidget* Widget)
		{
			if (UScrollBox* Scroll = Cast<UScrollBox>(Widget))
			{
				Scroll->SetScrollOffset(10000.f);
			}
		});
		Save(Scrolled, TEXT("post-4-feedback-scrolled"));
	});
}

#endif
