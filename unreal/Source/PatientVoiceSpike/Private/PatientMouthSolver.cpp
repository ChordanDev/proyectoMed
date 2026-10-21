#include "PatientMouthSolver.h"

#include "GuiToRawControlsUtils.h"
#include "HAL/Event.h"
#include "HAL/PlatformProcess.h"
#include "HAL/RunnableThread.h"
#include "NNEModelData.h"
#include "PatientVoiceComponent.h"
#include "PatientVoiceSpikeLog.h"
#include "SpeechAnimationSolverTypes.h"
#include "SpeechAnimationSolverV4.h"
#include "UObject/UObjectGlobals.h"

namespace
{
	// GUI control that opens the MetaHuman jaw; used by the envelope driver.
	const TCHAR* JawOpenControl = TEXT("CTRL_C_jaw.ty");
}

FPatientMouthSolver::FPatientMouthSolver(EPatientMouthDriver InDriver, FString InNNEBackend, int32 InLookaheadMs, float InEnvelopeGain, FOnFrame InOnFrame)
	: Driver(InDriver)
	, LookaheadMs(InLookaheadMs)
	, EnvelopeGain(InEnvelopeGain)
	, OnFrame(MoveTemp(InOnFrame))
{
	check(IsInGameThread());

	if (Driver == EPatientMouthDriver::SpeechSolver)
	{
		const FString ModelPath = ISpeechAnimationSolver::GetLatestModelAssetPath();
		UNNEModelData* ModelData = LoadObject<UNNEModelData>(GetTransientPackage(), *ModelPath);
		if (!ModelData)
		{
			Description = FString::Printf(TEXT("Speech solver model not found at %s"), *ModelPath);
		}
		else
		{
			Solver = MakeShared<FSpeechAnimationSolverV4>(ModelData, InNNEBackend);
			if (Solver->Initialize())
			{
				bReady = true;
				Description = FString::Printf(TEXT("Speech solver (%s, %d curves, lookahead %d ms)"), *InNNEBackend, Solver->GetNumCurves(), LookaheadMs);
			}
			else
			{
				Solver.Reset();
				Description = FString::Printf(TEXT("Speech solver failed to initialise on backend %s"), *InNNEBackend);
			}
		}
	}
	else
	{
		bReady = true;
		Description = FString::Printf(TEXT("Envelope jaw driver (gain %.1f)"), EnvelopeGain);
	}

	UE_LOG(LogPatientVoiceSpike, Log, TEXT("Mouth driver: %s"), *Description);

	if (bReady)
	{
		WakeEvent = FPlatformProcess::GetSynchEventFromPool(false);
		Thread = FRunnableThread::Create(this, TEXT("PatientMouthSolver"), 0, TPri_AboveNormal);
	}
}

FPatientMouthSolver::~FPatientMouthSolver()
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

void FPatientMouthSolver::PushAudio(TArray<float>&& MonoSamples, int32 SampleRate, double ArrivalSeconds)
{
	if (!bReady || bStopping)
	{
		return;
	}
	Pending.Enqueue(FChunk{ MoveTemp(MonoSamples), SampleRate, ArrivalSeconds });
	WakeEvent->Trigger();
}

double FPatientMouthSolver::ConsumeAverageSolveMs()
{
	FScopeLock Lock(&StatsLock);
	const double Average = SolveCount > 0 ? SolveMsTotal / SolveCount : 0.0;
	SolveMsTotal = 0.0;
	SolveCount = 0;
	return Average;
}

uint32 FPatientMouthSolver::Run()
{
	while (!bStopping)
	{
		WakeEvent->Wait(50);

		FChunk Chunk;
		while (!bStopping && Pending.Dequeue(Chunk))
		{
			SolveChunk(Chunk);
		}
	}
	return 0;
}

void FPatientMouthSolver::Stop()
{
	bStopping = true;
	if (WakeEvent)
	{
		WakeEvent->Trigger();
	}
}

void FPatientMouthSolver::SolveChunk(const FChunk& Chunk)
{
	const double Start = FPlatformTime::Seconds();
	TMap<FString, float> GuiControls;

	if (Driver == EPatientMouthDriver::SpeechSolver)
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
			UE_LOG(LogPatientVoiceSpike, Warning, TEXT("Speech solver failed on a %d-sample chunk."), Chunk.Samples.Num());
			return;
		}
		// The solver advances in 20 ms steps and always returns its last frame, so
		// a chunk that completed no step repeats the previous SolvedTime.
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
		const float Rms = Chunk.Samples.IsEmpty() ? 0.0f : FMath::Sqrt(SumSquares / Chunk.Samples.Num());
		const float Target = FMath::Clamp(Rms * EnvelopeGain, 0.0f, 1.0f);
		// Fast attack, slower release, so the jaw does not chatter between syllables.
		const float Rate = Target > EnvelopeValue ? 0.6f : 0.2f;
		EnvelopeValue += (Target - EnvelopeValue) * Rate;
		GuiControls.Add(JawOpenControl, EnvelopeValue);
	}

	FPatientMouthFrame Frame;
	Frame.RawControls = GuiToRawControlsUtils::ConvertGuiToRawControls(GuiControls);
	Frame.NewestAudioArrivalSeconds = Chunk.ArrivalSeconds;
	Frame.SolvedSeconds = FPlatformTime::Seconds();

	{
		FScopeLock Lock(&StatsLock);
		SolveMsTotal += (Frame.SolvedSeconds - Start) * 1000.0;
		++SolveCount;
	}

	OnFrame(MoveTemp(Frame));
}
