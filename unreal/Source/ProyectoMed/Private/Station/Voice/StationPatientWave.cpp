#include "Station/Voice/StationPatientWave.h"

void UStationPatientWave::Push(TConstArrayView<int16> Samples)
{
	FScopeLock Guard(&Lock);
	Pending.Append(Samples.GetData(), Samples.Num());
}

void UStationPatientWave::Clear()
{
	FScopeLock Guard(&Lock);
	Pending.Reset();
}

int32 UStationPatientWave::OnGeneratePCMAudio(TArray<uint8>& OutAudio, int32 NumSamples)
{
	FScopeLock Guard(&Lock);
	const int32 Count = FMath::Min(NumSamples, Pending.Num());
	if (Count <= 0)
	{
		return 0; // the engine plays silence until the patient speaks
	}
	OutAudio.SetNumUninitialized(Count * sizeof(int16), EAllowShrinking::No);
	FMemory::Memcpy(OutAudio.GetData(), Pending.GetData(), Count * sizeof(int16));
	Pending.RemoveAt(0, Count, EAllowShrinking::No);
	return Count;
}
