#pragma once

#include "CoreMinimal.h"
#include "HAL/Runnable.h"
#include "HAL/ThreadSafeBool.h"
#include "Containers/Queue.h"

class FRunnableThread;
class FEvent;
class ISpeechAnimationSolver;

enum class EPatientMouthDriver : uint8;

/** One solved face frame: MetaHuman raw controls plus timing for latency logs. */
struct FPatientMouthFrame
{
	TMap<FString, float> RawControls;
	/** FPlatformTime::Seconds() when the newest audio in this solve arrived. */
	double NewestAudioArrivalSeconds = 0.0;
	/** FPlatformTime::Seconds() when the solve finished. */
	double SolvedSeconds = 0.0;
};

/**
 * Turns mono float PCM into MetaHuman raw face controls on its own thread, using
 * either Epic's streaming speech-to-animation solver or an envelope jaw driver.
 */
class FPatientMouthSolver : public FRunnable
{
public:
	using FOnFrame = TFunction<void(FPatientMouthFrame&& Frame)>;

	/** Must be constructed on the game thread: it loads the solver model asset. */
	FPatientMouthSolver(EPatientMouthDriver InDriver, FString InNNEBackend, int32 InLookaheadMs, float InEnvelopeGain, FOnFrame InOnFrame);
	virtual ~FPatientMouthSolver() override;

	bool IsReady() const { return bReady; }
	FString GetDescription() const { return Description; }

	/** Thread-safe, single producer. Samples are mono, normalised to [-1, 1]. */
	void PushAudio(TArray<float>&& MonoSamples, int32 SampleRate, double ArrivalSeconds);

	/** Average solve time in milliseconds since the last call. */
	double ConsumeAverageSolveMs();

	// FRunnable
	virtual uint32 Run() override;
	virtual void Stop() override;

private:
	struct FChunk
	{
		TArray<float> Samples;
		int32 SampleRate = 0;
		double ArrivalSeconds = 0.0;
	};

	void SolveChunk(const FChunk& Chunk);

	EPatientMouthDriver Driver;
	int32 LookaheadMs = 80;
	float EnvelopeGain = 8.0f;
	float EnvelopeValue = 0.0f;
	double LastSolvedTime = 0.0;
	FOnFrame OnFrame;

	TSharedPtr<ISpeechAnimationSolver> Solver;
	bool bReady = false;
	FString Description;

	TQueue<FChunk, EQueueMode::Spsc> Pending;
	FEvent* WakeEvent = nullptr;
	FThreadSafeBool bStopping = false;
	FRunnableThread* Thread = nullptr;

	FCriticalSection StatsLock;
	double SolveMsTotal = 0.0;
	int32 SolveCount = 0;
};
