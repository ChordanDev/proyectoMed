#include "Station/Voice/StationPatientVoice.h"

#include "Components/AudioComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Animation/AnimSequence.h"
#include "Sound/SoundWaveProcedural.h"
#include "Station/Voice/StationMouthSolver.h"
#include "Station/Voice/StationPatientFaceAnim.h"

namespace
{
	// LiveKit delivers remote audio as 48 kHz mono.
	constexpr int32 VoiceSampleRate = 48000;
	// Below this RMS the patient's track carries silence, not speech.
	constexpr float SpeechRms = 0.01f;

	FString SolverBackend()
	{
#if PLATFORM_WINDOWS
		return TEXT("NNERuntimeORTDml");
#else
		return TEXT("NNERuntimeORTCpu");
#endif
	}
}

void FStationPatientAudioSink::Attach(USoundWaveProcedural* InWave, TSharedPtr<FStationMouthSolver> InSolver,
	TSharedPtr<FStationMouthState, ESPMode::ThreadSafe> InMouth)
{
	FScopeLock Guard(&Lock);
	Wave = InWave;
	Solver = MoveTemp(InSolver);
	Mouth = MoveTemp(InMouth);
}

void FStationPatientAudioSink::Detach()
{
	FScopeLock Guard(&Lock);
	Wave = nullptr;
	Solver.Reset();
	Mouth.Reset();
}

void FStationPatientAudioSink::Handle(TConstArrayView<int16> Samples, int32 SampleRate, int32 NumChannels)
{
	if (NumChannels <= 0 || Samples.IsEmpty())
	{
		return;
	}
	TArray<float> Mono;
	Mono.SetNumUninitialized(Samples.Num() / NumChannels);
	double SumSquares = 0.0;
	for (int32 Index = 0; Index < Mono.Num(); ++Index)
	{
		float Sum = 0.f;
		for (int32 Channel = 0; Channel < NumChannels; ++Channel)
		{
			Sum += Samples[Index * NumChannels + Channel] / 32768.f;
		}
		Mono[Index] = Sum / NumChannels;
		SumSquares += Mono[Index] * Mono[Index];
	}

	FScopeLock Guard(&Lock);
	if (!Wave)
	{
		return;
	}
	if (SampleRate == VoiceSampleRate && NumChannels == 1)
	{
		Wave->QueueAudio(reinterpret_cast<const uint8*>(Samples.GetData()), Samples.Num() * sizeof(int16));
	}
	if (Mouth && Mono.Num() > 0 && FMath::Sqrt(SumSquares / Mono.Num()) > SpeechRms)
	{
		Mouth->NoteSpeech();
	}
	if (Solver)
	{
		Solver->PushAudio(MoveTemp(Mono), SampleRate);
	}
}

void UStationPatientVoice::Start(USkeletalMeshComponent* Face, UAnimSequence* IdleFace)
{
	Stop();
	if (!Face)
	{
		return;
	}
	FaceMesh = Face;
	Idle = IdleFace;

	const TSharedRef<FStationMouthState, ESPMode::ThreadSafe> Mouth = MakeShared<FStationMouthState, ESPMode::ThreadSafe>();
	Face->SetAnimationMode(EAnimationMode::AnimationBlueprint);
	Face->SetAnimInstanceClass(UStationPatientFaceAnim::StaticClass());
	if (UStationPatientFaceAnim* FaceAnim = Cast<UStationPatientFaceAnim>(Face->GetAnimInstance()))
	{
		FaceAnim->Setup(IdleFace, Mouth);
	}

	Solver = MakeShared<FStationMouthSolver>(SolverBackend(),
		[Mouth](TMap<FName, float>&& RawControls) { Mouth->PushControls(MoveTemp(RawControls)); });

	Wave = NewObject<USoundWaveProcedural>(this);
	Wave->SetSampleRate(VoiceSampleRate);
	Wave->NumChannels = 1;
	Wave->Duration = INDEFINITELY_LOOPING_DURATION;
	Wave->SoundGroup = SOUNDGROUP_Voice;
	Wave->bLooping = false;

	Speaker = NewObject<UAudioComponent>(GetOwner());
	Speaker->bAutoActivate = false;
	Speaker->bAllowSpatialization = false;
	Speaker->SetupAttachment(Face);
	Speaker->RegisterComponent();
	Speaker->SetSound(Wave);
	Speaker->Play();

	Sink->Attach(Wave, Solver, Mouth);
}

void UStationPatientVoice::Stop()
{
	Sink->Detach();
	if (Solver)
	{
		Solver->Stop();
		Solver.Reset();
	}
	if (Speaker)
	{
		Speaker->Stop();
		Speaker->DestroyComponent();
		Speaker = nullptr;
	}
	Wave = nullptr;
	if (FaceMesh && Idle)
	{
		// Back to the idle loop the scene starts with.
		FaceMesh->SetAnimationMode(EAnimationMode::AnimationSingleNode);
		FaceMesh->PlayAnimation(Idle, true);
	}
	FaceMesh = nullptr;
	Idle = nullptr;
}

void UStationPatientVoice::EndPlay(const EEndPlayReason::Type EndPlayReason)
{
	Stop();
	Super::EndPlay(EndPlayReason);
}
