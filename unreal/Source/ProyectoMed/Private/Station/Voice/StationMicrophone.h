#pragma once

#include "CoreMinimal.h"
#include "Generators/AudioGenerator.h"
#include "UObject/Object.h"

#include "StationMicrophone.generated.h"

class FStationVoiceLink;
class UAudioCapture;

/**
 * The learner's microphone during a voice run (#191): captures the default input
 * device and pushes it into the run's voice link. Capturing starts only when the
 * learner opted into a voice run and stops when the run ends; nothing is
 * recorded or kept.
 */
UCLASS(Transient)
class UStationMicrophone : public UObject
{
	GENERATED_BODY()

public:
	/** Opens the default input device and starts feeding `Link`. False when no device opens. */
	bool Start(TWeakPtr<FStationVoiceLink, ESPMode::ThreadSafe> Link);
	void Stop();
	bool IsCapturing() const;

	virtual void BeginDestroy() override;

private:
	UPROPERTY(Transient)
	TObjectPtr<UAudioCapture> Capture;

	FAudioGeneratorHandle Handle;
};
