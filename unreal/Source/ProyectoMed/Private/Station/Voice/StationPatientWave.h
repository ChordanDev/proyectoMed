#pragma once

#include "CoreMinimal.h"
#include "Sound/SoundWaveProcedural.h"

#include "StationPatientWave.generated.h"

/**
 * The patient's voice for the speaker: 48 kHz mono int16 that the audio thread pulls
 * as it plays. Unlike `USoundWaveProcedural::ResetAudio`, which pops the engine's
 * single-consumer queue from the calling thread, `Clear` may run on any thread
 * while the audio thread plays (#193).
 */
UCLASS(Transient)
class UStationPatientWave : public USoundWaveProcedural
{
	GENERATED_BODY()

public:
	/** Any thread. */
	void Push(TConstArrayView<int16> Samples);
	/** Drops every sample not played yet. Any thread. */
	void Clear();

	virtual int32 OnGeneratePCMAudio(TArray<uint8>& OutAudio, int32 NumSamples) override;

private:
	FCriticalSection Lock;
	TArray<int16> Pending;
};
