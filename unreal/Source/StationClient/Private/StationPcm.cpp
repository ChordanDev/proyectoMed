#include "StationPcm.h"

void FStationPcmFramer::Push(TConstArrayView<float> Samples, int32 InSampleRate, int32 NumChannels,
	TFunctionRef<void(TConstArrayView<int16>)> OnFrame)
{
	if (InSampleRate <= 0 || NumChannels <= 0)
	{
		return;
	}
	if (InSampleRate != InputRate)
	{
		Reset();
		InputRate = InSampleRate;
	}

	const int32 InputFrames = Samples.Num() / NumChannels;
	Pending.Reserve(Pending.Num() + InputFrames);
	for (int32 Index = 0; Index < InputFrames; ++Index)
	{
		float Sum = 0.f;
		for (int32 Channel = 0; Channel < NumChannels; ++Channel)
		{
			Sum += Samples[Index * NumChannels + Channel];
		}
		Pending.Add(Sum / NumChannels);
	}

	const double Step = static_cast<double>(InputRate) / SampleRate;
	// Interpolation reads the sample after `Position`, so the last one waits for the next push.
	while (Position + 1.0 < Pending.Num() || (Step == 1.0 && Position < Pending.Num()))
	{
		const int32 Base = static_cast<int32>(Position);
		const float Fraction = static_cast<float>(Position - Base);
		const float Next = Base + 1 < Pending.Num() ? Pending[Base + 1] : Pending[Base];
		const float Value = FMath::Clamp(FMath::Lerp(Pending[Base], Next, Fraction), -1.f, 1.f);
		Frame.Add(static_cast<int16>(FMath::RoundToInt(Value * MAX_int16)));
		Position += Step;

		if (Frame.Num() == FrameSamples)
		{
			OnFrame(Frame);
			Frame.Reset();
		}
	}

	const int32 Consumed = FMath::Min(static_cast<int32>(Position), Pending.Num());
	Pending.RemoveAt(0, Consumed, EAllowShrinking::No);
	Position -= Consumed;
}

void FStationPcmFramer::Reset()
{
	Pending.Reset();
	Frame.Reset();
	Position = 0.0;
	InputRate = 0;
}
