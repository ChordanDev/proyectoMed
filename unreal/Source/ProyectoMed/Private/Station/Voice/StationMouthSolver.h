#pragma once

#include "CoreMinimal.h"
#include "Containers/Queue.h"
#include "HAL/Runnable.h"
#include "HAL/ThreadSafeBool.h"

class FEvent;
class FRunnableThread;
class ISpeechAnimationSolver;

/**
 * Turns the patient's voice into MetaHuman raw face controls on its own thread,
 * with Epic's streaming speech-to-animation solver (StreamingADA), the driver the
 * #189 spike measured. When the solver model cannot load it falls back to opening
 * the jaw with the loudness of the voice.
 */
class FStationMouthSolver : public FRunnable
{
public:
	/** Called on the solver thread with raw control name to value. */
	using FOnControls = TFunction<void(TMap<FName, float>&& RawControls)>;

	/** Game thread only: it loads the solver model asset. */
	FStationMouthSolver(const FString& NNEBackend, FOnControls InOnControls);
	virtual ~FStationMouthSolver() override;

	const FString& GetDescription() const { return Description; }

	/** Mono samples in [-1, 1]. One producer thread at a time. */
	void PushAudio(TArray<float>&& MonoSamples, int32 SampleRate);

	virtual uint32 Run() override;
	virtual void Stop() override;

private:
	struct FChunk
	{
		TArray<float> Samples;
		int32 SampleRate = 0;
	};

	void Solve(const FChunk& Chunk);

	/** Audio the solver looks ahead before committing a frame; the spike's measured setting. */
	static constexpr int32 LookaheadMs = 80;

	FOnControls OnControls;
	TSharedPtr<ISpeechAnimationSolver> Solver;
	FString Description;
	double LastSolvedTime = 0.0;
	float Envelope = 0.f;

	TQueue<FChunk, EQueueMode::Spsc> Pending;
	FEvent* WakeEvent = nullptr;
	FThreadSafeBool bStopping = false;
	FRunnableThread* Thread = nullptr;
};
