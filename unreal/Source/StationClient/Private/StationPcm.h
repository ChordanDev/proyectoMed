#pragma once

#include "CoreMinimal.h"

/**
 * Turns microphone audio of any rate and channel count into the 10 ms, 48 kHz
 * mono int16 frames that LiveKit's echo canceller and audio source take. Linear
 * resampling is enough for speech that only needs to be transcribed.
 */
class FStationPcmFramer
{
public:
	static constexpr int32 SampleRate = 48000;
	static constexpr int32 FrameSamples = SampleRate / 100;

	/** Calls `OnFrame` once per complete frame; a partial frame waits for the next push. */
	void Push(TConstArrayView<float> Samples, int32 InSampleRate, int32 NumChannels,
		TFunctionRef<void(TConstArrayView<int16>)> OnFrame);

	void Reset();

private:
	/** Mono input not yet resampled, at `InputRate`. */
	TArray<float> Pending;
	/** Position of the next output sample in `Pending`, in input samples. */
	double Position = 0.0;
	int32 InputRate = 0;
	TArray<int16> Frame;
};
