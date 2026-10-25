#pragma once

#include "Animation/AnimInstance.h"
#include "Animation/AnimInstanceProxy.h"
#include "CoreMinimal.h"

#include "StationPatientFaceAnim.generated.h"

class UAnimSequence;

/** The latest solved mouth and when the patient was last heard, shared across threads. */
struct FStationMouthState
{
	/** Keeps the jaw, mouth, lips, tongue and teeth controls; any thread. */
	void PushControls(TMap<FName, float>&& RawControls);
	/** Marks the patient as heard now; any thread. */
	void NoteSpeech();
	/** The patient stopped: the mouth goes back to the idle loop; any thread. */
	void Rest();
	/** Copies the mouth and says whether the patient is speaking; any thread. */
	bool Read(TMap<FName, float>& OutControls) const;

private:
	mutable FCriticalSection Lock;
	TMap<FName, float> Controls;
	double LastSpeechSeconds = -1.0;
	/** Since `Rest`: the solver's late controls are ignored until the patient is heard again. */
	bool bResting = false;
};

/** Plays the face idle loop and lays the speaking mouth over it (see `UStationPatientFaceAnim`). */
struct FStationPatientFaceProxy : public FAnimInstanceProxy
{
	FStationPatientFaceProxy() = default;
	explicit FStationPatientFaceProxy(UAnimInstance* Instance) : FAnimInstanceProxy(Instance) {}

	virtual void PreUpdate(UAnimInstance* InAnimInstance, float DeltaSeconds) override;
	virtual bool Evaluate(FPoseContext& Output) override;

	TObjectPtr<UAnimSequence> Idle;
	double IdleTime = 0.0;
	float SpeechWeight = 0.f;
	TMap<FName, float> MouthControls;
};

/**
 * The patient's face during a voice run (#191). It plays the idle face loop and,
 * while the patient speaks, overrides only the jaw, mouth, lips, tongue and teeth
 * controls with the ones solved from the voice. The eyes and brows keep the idle
 * loop. The MetaHuman's post-process Anim Blueprint turns the controls into the
 * face rig, as it does for its own Live Link input.
 */
UCLASS(Transient)
class UStationPatientFaceAnim : public UAnimInstance
{
	GENERATED_BODY()

public:
	/** Game thread. */
	void Setup(UAnimSequence* InIdle, TSharedPtr<FStationMouthState, ESPMode::ThreadSafe> InMouth)
	{
		Idle = InIdle;
		Mouth = MoveTemp(InMouth);
	}

protected:
	virtual FAnimInstanceProxy* CreateAnimInstanceProxy() override;
	virtual void DestroyAnimInstanceProxy(FAnimInstanceProxy* InProxy) override;

private:
	friend struct FStationPatientFaceProxy;

	UPROPERTY(Transient)
	TObjectPtr<UAnimSequence> Idle;

	TSharedPtr<FStationMouthState, ESPMode::ThreadSafe> Mouth;
};
