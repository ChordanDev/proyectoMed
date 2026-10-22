#include "Station/Voice/StationMouthSolver.h"

#include "GuiToRawControlsUtils.h"
#include "HAL/Event.h"
#include "HAL/PlatformProcess.h"
#include "HAL/RunnableThread.h"
#include "NNEModelData.h"
#include "SpeechAnimationSolverTypes.h"
#include "SpeechAnimationSolverV4.h"
#include "UObject/UObjectGlobals.h"

DEFINE_LOG_CATEGORY_STATIC(LogStationMouth, Log, All);

namespace
{
	// The GUI control that opens the MetaHuman jaw, for the loudness fallback.
	const TCHAR* JawOpenControl = TEXT("CTRL_C_jaw.ty");
	// Loudness to jaw opening for the fallback, as tuned in the #189 spike.
	constexpr float EnvelopeGain = 8.f;
}

FStationMouthSolver::FStationMouthSolver(const FString& NNEBackend, FOnControls InOnControls)
	: OnControls(MoveTemp(InOnControls))
{
	check(IsInGameThread());

	const FString ModelPath = ISpeechAnimationSolver::GetLatestModelAssetPath();
	if (UNNEModelData* ModelData = LoadObject<UNNEModelData>(GetTransientPackage(), *ModelPath))
	{
		Solver = MakeShared<FSpeechAnimationSolverV4>(ModelData, NNEBackend);
		if (!Solver->Initialize())
		{
			Solver.Reset();
		}
	}
	Description = Solver
		? FString::Printf(TEXT("speech solver on %s, lookahead %d ms"), *NNEBackend, LookaheadMs)
		: FString::Printf(TEXT("jaw from loudness (speech solver unavailable at %s on %s)"), *ModelPath, *NNEBackend);
	UE_LOG(LogStationMouth, Log, TEXT("Patient mouth: %s"), *Description);

	WakeEvent = FPlatformProcess::GetSynchEventFromPool(false);
	Thread = FRunnableThread::Create(this, TEXT("StationMouthSolver"), 0, TPri_AboveNormal);
}

FStationMouthSolver::~FStationMouthSolver()
{
	if (Thread)
	{
		Thread->Kill(true);
		delete Thread;
		Thread = nullptr;
	}
	if (WakeEvent)
	{
		FPlatformProcess::ReturnSynchEventToPool(WakeEvent);
		WakeEvent = nullptr;
	}
}

void FStationMouthSolver::PushAudio(TArray<float>&& MonoSamples, int32 SampleRate)
{
	if (bStopping || !WakeEvent)
	{
		return;
	}
	Pending.Enqueue(FChunk{ MoveTemp(MonoSamples), SampleRate });
	WakeEvent->Trigger();
}

uint32 FStationMouthSolver::Run()
{
	while (!bStopping)
	{
		WakeEvent->Wait(50);
		FChunk Chunk;
		while (!bStopping && Pending.Dequeue(Chunk))
		{
			Solve(Chunk);
		}
	}
	return 0;
}

void FStationMouthSolver::Stop()
{
	bStopping = true;
	if (WakeEvent)
	{
		WakeEvent->Trigger();
	}
}

void FStationMouthSolver::Solve(const FChunk& Chunk)
{
	TMap<FString, float> GuiControls;
	if (Solver)
	{
		FSpeechAnimationAudioFrame AudioFrame;
		AudioFrame.AudioSamples = Chunk.Samples;
		AudioFrame.SamplesCount = Chunk.Samples.Num();
		AudioFrame.SampleRate = Chunk.SampleRate;
		AudioFrame.NumChannels = 1;
		AudioFrame.bContiguous = true;
		AudioFrame.Mood = EAudioDrivenAnimationMood::Neutral;
		AudioFrame.MoodIntensity = 1.0f;
		AudioFrame.Lookahead = LookaheadMs;

		FSpeechAnimationFrameData FrameData;
		if (!Solver->SolveAudioFrame(AudioFrame, FrameData))
		{
			return;
		}
		// The solver advances in 20 ms steps and repeats its last frame until the next one.
		if (FrameData.CurveValues.IsEmpty() || FrameData.SolvedTime == LastSolvedTime)
		{
			return;
		}
		LastSolvedTime = FrameData.SolvedTime;
		for (int32 Index = 0; Index < FrameData.CurveNames.Num(); ++Index)
		{
			GuiControls.Add(FrameData.CurveNames[Index].ToString(), FrameData.CurveValues[Index]);
		}
	}
	else
	{
		double SumSquares = 0.0;
		for (const float Sample : Chunk.Samples)
		{
			SumSquares += Sample * Sample;
		}
		const float Rms = Chunk.Samples.IsEmpty() ? 0.f : FMath::Sqrt(SumSquares / Chunk.Samples.Num());
		const float Target = FMath::Clamp(Rms * EnvelopeGain, 0.f, 1.f);
		// Fast attack, slower release, so the jaw does not chatter between syllables.
		Envelope += (Target - Envelope) * (Target > Envelope ? 0.6f : 0.2f);
		GuiControls.Add(JawOpenControl, Envelope);
	}

	TMap<FName, float> RawControls;
	for (const TPair<FString, float>& Control : GuiToRawControlsUtils::ConvertGuiToRawControls(GuiControls))
	{
		RawControls.Add(FName(*Control.Key), Control.Value);
	}
	OnControls(MoveTemp(RawControls));
}
