// Renders the in-run HUD in chosen states to PNG files, to look at the design
// without playing a run to each state. Runs only with an RHI and when
// $STATION_HUD_SNAPSHOT_DIR names the folder for the images:
//   STATION_HUD_SNAPSHOT_DIR=/tmp/hud UnrealEditor ProyectoMed.uproject \
//     -ExecCmds="Automation RunTests ProyectoMed.StationHud.Snapshot; Quit" -unattended
// It asserts nothing about the look; the images are for a person to judge.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Blueprint/UserWidget.h"
#include "Components/Border.h"
#include "Components/TextBlock.h"
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

BEGIN_DEFINE_SPEC(FStationHudSnapshotSpec, "ProyectoMed.StationHud.Snapshot",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	FString OutDir;

	UStationRunFlow* MakeFlow(EStationTrainingMode Mode) const;
	UStationHudWidget* MakeHud(UStationRunFlow* Flow) const;
	void Save(UStationHudWidget* Hud, const FString& Name);
END_DEFINE_SPEC(FStationHudSnapshotSpec)

namespace StationHudSnapshot
{
	// Two documents of the reference station (backend/priv/stations/acute-appendicitis).
	FStationImpresso PhysicalExam()
	{
		FStationImpresso Impresso;
		Impresso.Id = TEXT("impresso-1-exame-fisico");
		Impresso.Title = TEXT("IMPRESSO 1 — EXAME FÍSICO SEGMENTAR");
		Impresso.Category = TEXT("exame-fisico");
		Impresso.Content = TEXT(
			"- **Estado geral:** regular, consciente, orientado, fácies de dor; hidratado, sem cianose ou icterícia.\n"
			"- **Sinais vitais no exame:** PA 126/78 mmHg; FC 102 bpm; FR 18 irpm; temperatura 38,1 °C; SpO₂ 98% em ar ambiente.\n"
			"- **Aparelho cardiovascular:** bulhas normofonéticas, ritmo regular, sem sopros.\n"
			"- **Aparelho respiratório:** murmúrio vesicular presente bilateralmente, sem ruídos adventícios.\n"
			"- **Abdome — inspeção:** plano, sem cicatrizes, distensão, equimoses ou circulação colateral; movimentação reduzida durante a respiração profunda.\n"
			"- **Ausculta:** ruídos hidroaéreos presentes, discretamente diminuídos; sem sopros.\n"
			"- **Percussão:** timpanismo predominante; sem macicez anormal.\n"
			"- **Palpação superficial:** dor localizada no quadrante inferior direito, com defesa voluntária discreta.\n"
			"- **Palpação profunda:** dor acentuada na fossa ilíaca direita, especialmente no ponto de McBurney. Descompressão brusca dolorosa na fossa ilíaca direita: sinal de Blumberg positivo.\n"
			"- **Manobras:** sinal de Rovsing positivo; sinal do psoas negativo; sinal do obturador negativo. Sem dor à punho-percussão lombar.\n"
			"- **Neurológico:** alerta, orientado em tempo, espaço e pessoa; sem déficit motor grosseiro.\n");
		return Impresso;
	}

	FStationImpresso BloodCount()
	{
		FStationImpresso Impresso;
		Impresso.Id = TEXT("impresso-2-hemograma");
		Impresso.Title = TEXT("IMPRESSO 2 — EXAMES LABORATORIAIS — Hemograma completo");
		Impresso.Category = TEXT("laboratorio");
		Impresso.Content = TEXT(
			"**Hemograma completo:**\n\n"
			"- Hemoglobina: 14,6 g/dL. Referência adulto masculino: 13,0–17,0 g/dL.\n"
			"- Hematócrito: 43%. Referência adulto masculino: 40–52%.\n"
			"- Leucócitos: 15.800/mm³. Referência: 4.000–11.000/mm³.\n"
			"- Neutrófilos: 86%; bastonetes: 8%. Referências usuais: neutrófilos segmentados 40–75%; bastonetes 0–5%.\n"
			"- Plaquetas: 268.000/mm³. Referência: 150.000–450.000/mm³.\n");
		return Impresso;
	}

	FStationExamRequest Request(const TCHAR* Text, EStationImpressoDecision Decision, const TCHAR* Feedback,
		TOptional<FStationImpresso> Released = {})
	{
		FStationExamRequest Request;
		Request.Text = Text;
		Request.Reply.Decision = Decision;
		Request.Reply.FeedbackMessage = Feedback;
		if (Released)
		{
			Request.Reply.NewlyReleased.Add(*Released);
		}
		return Request;
	}
}

UStationRunFlow* FStationHudSnapshotSpec::MakeFlow(EStationTrainingMode Mode) const
{
	using namespace StationHudSnapshot;
	UStationRunFlow* Flow = NewObject<UStationRunFlow>();
	Flow->Step = EStationRunStep::Running;
	Flow->Mode = Mode;
	Flow->Voice.State = EStationVoiceState::Ready;
	Flow->Transcript.Add({EStationSpeaker::Learner, TEXT("Bom dia, eu sou o doutor. Qual é o seu nome? Bom dia.")});
	Flow->Transcript.Add({EStationSpeaker::Patient, TEXT("Bom dia, doutor. Meu nome é Rafael Nogueira.")});
	Flow->Transcript.Add({EStationSpeaker::Learner, TEXT("O que o senhor está sentindo?")});
	Flow->Transcript.Add({EStationSpeaker::Patient, TEXT("Estou com dor na barriga, doutor.")});
	Flow->Transcript.Add({EStationSpeaker::Learner, TEXT("Onde dói?")});
	Flow->Transcript.Add({EStationSpeaker::Patient, TEXT("Agora a dor está na parte de baixo do lado direito da barriga.")});
	Flow->ExamRequests.Add(Request(TEXT("Solicito exame físico do abdome"), EStationImpressoDecision::Released,
		TEXT("Impresso liberado: IMPRESSO 1 — EXAME FÍSICO SEGMENTAR"), PhysicalExam()));
	Flow->ExamRequests.Add(Request(TEXT("Hemograma"), EStationImpressoDecision::Released,
		TEXT("Impresso liberado: IMPRESSO 2 — EXAMES LABORATORIAIS — Hemograma completo"), BloodCount()));
	Flow->ExamRequests.Add(Request(TEXT("Raio X de tórax"), EStationImpressoDecision::Unavailable,
		TEXT("Este exame não está disponível nesta estação.")));
	Flow->ReleasedImpressos = {PhysicalExam(), BloodCount()};
	return Flow;
}

UStationHudWidget* FStationHudSnapshotSpec::MakeHud(UStationRunFlow* Flow) const
{
	UWorld* World = GEngine->GetWorldContexts()[0].World();
	UStationHudWidget* Hud = CreateWidget<UStationHudWidget>(World);
	Hud->TakeWidget();
	Hud->SetFlow(Flow);
	Hud->Refresh();
	Hud->TimerText->SetText(FText::FromString(TEXT("08:42")));
	return Hud;
}

void FStationHudSnapshotSpec::Save(UStationHudWidget* Hud, const FString& Name)
{
	const FVector2D Size(1600.0, 900.0);
	// A plain backdrop where the scene would be.
	TSharedRef<SWidget> Screen = SNew(SOverlay)
		+ SOverlay::Slot()[SNew(SColorBlock).Color(FLinearColor(0.16f, 0.17f, 0.18f, 1.f))]
		+ SOverlay::Slot()[Hud->TakeWidget()];
	// Slate encodes the colors once; a linear target keeps them as the screen shows them.
	FWidgetRenderer Renderer(true, true);
	UTextureRenderTarget2D* Target = FWidgetRenderer::CreateTargetFor(Size, TF_Bilinear, false);
	// The first pass lays the text out; the second draws it in place.
	Renderer.DrawWidget(Target, Screen, Size, 0.f);
	Renderer.DrawWidget(Target, Screen, Size, 0.016f);
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

void FStationHudSnapshotSpec::Define()
{
	BeforeEach([this]()
	{
		OutDir = FPlatformMisc::GetEnvironmentVariable(TEXT("STATION_HUD_SNAPSHOT_DIR"));
	});

	It("renders the exam panel, the microphone, the talk button and the document reader", [this]()
	{
		if (OutDir.IsEmpty() || !FApp::CanEverRender())
		{
			AddInfo(TEXT("Skipped: set STATION_HUD_SNAPSHOT_DIR and run with an RHI."));
			return;
		}

		UStationRunFlow* Voice = MakeFlow(EStationTrainingMode::Voice);
		Save(MakeHud(Voice), TEXT("1-voice-closed"));

		Voice->SpokenExamTurn = 7;
		Voice->SpokenExamText = TEXT("Solicito ultrassonografia de abdome");
		UStationHudWidget* Hud = MakeHud(Voice);
		Hud->OpenExams();
		Save(Hud, TEXT("2-voice-panel"));

		UStationRunFlow* Recording = MakeFlow(EStationTrainingMode::Voice);
		Recording->SpokenExamExpiresAt = FPlatformTime::Seconds() + 20.0;
		Hud = MakeHud(Recording);
		Hud->OpenExams();
		Hud->bMicrophoneHeld = true;
		Hud->RefreshMicrophone();
		Hud->RecordingSince -= 3.0;
		Hud->RefreshMicrophone();
		Hud->MicrophoneRing->SetRenderScale(FVector2D(1.1f));
		Hud->MicrophoneRing->SetRenderOpacity(0.5f);
		Save(Hud, TEXT("3-voice-recording"));

		Hud = MakeHud(MakeFlow(EStationTrainingMode::Voice));
		Hud->OpenExams();
		Hud->OpenDocument(TEXT("impresso-1-exame-fisico"));
		Save(Hud, TEXT("4-document-physical-exam"));

		Hud = MakeHud(MakeFlow(EStationTrainingMode::Voice));
		Hud->OpenExams();
		Hud->OpenDocument(TEXT("impresso-2-hemograma"));
		Save(Hud, TEXT("5-document-blood-count"));

		Hud = MakeHud(MakeFlow(EStationTrainingMode::Text));
		Hud->OpenExams();
		Save(Hud, TEXT("6-text-panel"));

		// #419: the talk button while the learner holds it, and while the patient answers.
		UStationRunFlow* Talking = MakeFlow(EStationTrainingMode::Voice);
		Talking->TalkKey.Press(FPlatformTime::Seconds(), false);
		Save(MakeHud(Talking), TEXT("7-voice-talking"));

		UStationRunFlow* Answering = MakeFlow(EStationTrainingMode::Voice);
		FStationVoiceEvent Sent;
		Sent.Kind = EStationVoiceEventKind::Learner;
		Sent.TurnId = 1;
		Sent.Text = TEXT("Onde dói?");
		Sent.bFinal = true;
		Answering->HandleVoiceEvent(Sent);
		Save(MakeHud(Answering), TEXT("8-voice-patient-answering"));
	});
}

#endif
