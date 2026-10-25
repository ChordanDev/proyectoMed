#pragma once

#include "Components/ActorComponent.h"
#include "CoreMinimal.h"

#include "StationPatientVoice.generated.h"

class FStationMouthSolver;
class UAnimSequence;
class UAudioComponent;
class USkeletalMeshComponent;
class UStationPatientWave;
struct FStationMouthState;

/**
 * Where the patient's voice goes, from the LiveKit thread that delivers it: the
 * game's speaker and the mouth solver. `Detach` cuts it off before the objects it
 * feeds go away, so a late frame never reaches them.
 */
class FStationPatientAudioSink
{
public:
	/** Interleaved int16 PCM from `FStationVoiceHandlers::OnPatientPcm`; any thread. */
	void Handle(TConstArrayView<int16> Samples, int32 SampleRate, int32 NumChannels);

	void Attach(UStationPatientWave* InWave, TSharedPtr<FStationMouthSolver> InSolver,
		TSharedPtr<FStationMouthState, ESPMode::ThreadSafe> InMouth);
	void Detach();

	/**
	 * The learner spoke over the patient, or the run ended (#193): empties the voice
	 * still queued for the speaker, rests the mouth, and drops the audio that still
	 * arrives until `Resume`. Any thread.
	 */
	void Silence();
	/** The next reply may play. Any thread. */
	void Resume();

private:
	FCriticalSection Lock;
	UStationPatientWave* Wave = nullptr;
	TSharedPtr<FStationMouthSolver> Solver;
	TSharedPtr<FStationMouthState, ESPMode::ThreadSafe> Mouth;
	bool bSilenced = false;
};

/**
 * The patient's voice in the consultation scene (#191): plays the voice worker's
 * patient track at the patient and moves the MetaHuman's mouth with it. Added to
 * the patient actor for a voice run; the face goes back to its idle loop when it
 * stops.
 */
UCLASS(Transient)
class UStationPatientVoice : public UActorComponent
{
	GENERATED_BODY()

public:
	/** Starts on `Face`, keeping `IdleFace` on everything but the mouth. */
	void Start(USkeletalMeshComponent* Face, UAnimSequence* IdleFace);
	void Stop();
	bool IsStarted() const { return FaceMesh != nullptr; }

	/** Pass to `FStationVoiceHandlers::OnPatientPcm`. */
	TSharedRef<FStationPatientAudioSink, ESPMode::ThreadSafe> GetSink() const { return Sink; }

protected:
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

private:
	TSharedRef<FStationPatientAudioSink, ESPMode::ThreadSafe> Sink = MakeShared<FStationPatientAudioSink, ESPMode::ThreadSafe>();
	TSharedPtr<FStationMouthSolver> Solver;

	UPROPERTY(Transient)
	TObjectPtr<UStationPatientWave> Wave;

	UPROPERTY(Transient)
	TObjectPtr<UAudioComponent> Speaker;

	UPROPERTY(Transient)
	TObjectPtr<USkeletalMeshComponent> FaceMesh;

	UPROPERTY(Transient)
	TObjectPtr<UAnimSequence> Idle;
};
