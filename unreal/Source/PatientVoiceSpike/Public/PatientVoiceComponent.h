#pragma once

#include "CoreMinimal.h"
#include "Components/ActorComponent.h"
#include "PatientVoiceComponent.generated.h"

class FLiveKitPatientStream;
class FPatientMouthSolver;
class FPatientVoiceLiveLinkSource;
class UAudioComponent;
class USoundWaveProcedural;

UENUM(BlueprintType)
enum class EPatientMouthDriver : uint8
{
	/** Epic's streaming speech-to-animation solver (StreamingADA). */
	SpeechSolver,
	/** Opens the jaw from the audio envelope. The fallback. */
	Envelope,
};

/**
 * Spike for #189. Joins a LiveKit room, plays the patient voice track, and
 * publishes MetaHuman face controls solved from that same audio as a Live Link
 * subject. Point the MetaHuman's Live Link face subject at SubjectName.
 *
 * The URL and token can be overridden at runtime with the console variables
 * patientvoice.Url and patientvoice.Token, so no token needs to be saved in a level.
 */
UCLASS(ClassGroup = (Spike), meta = (BlueprintSpawnableComponent))
class PATIENTVOICESPIKE_API UPatientVoiceComponent : public UActorComponent
{
	GENERATED_BODY()

public:
	UPatientVoiceComponent();

	UPROPERTY(EditAnywhere, Category = "LiveKit")
	FString ServerUrl = TEXT("ws://127.0.0.1:7880");

	/** Short-lived room token. Prefer the patientvoice.Token console variable. */
	UPROPERTY(EditAnywhere, Transient, Category = "LiveKit")
	FString Token;

	UPROPERTY(EditAnywhere, Category = "LiveKit")
	FString PublisherIdentity = TEXT("voice-worker");

	/** Empty attaches the publisher's first audio track (the `lk` test publisher names tracks after file paths). */
	UPROPERTY(EditAnywhere, Category = "LiveKit")
	FString TrackName = TEXT("patient-voice");

	UPROPERTY(EditAnywhere, Category = "Lip Sync")
	FName SubjectName = TEXT("PatientVoice");

	UPROPERTY(EditAnywhere, Category = "Lip Sync")
	EPatientMouthDriver MouthDriver = EPatientMouthDriver::SpeechSolver;

	/** Audio the solver looks ahead before committing a frame; adds mouth delay. */
	UPROPERTY(EditAnywhere, Category = "Lip Sync", meta = (ClampMin = 0, ClampMax = 400))
	int32 LookaheadMs = 80;

	/** Silence queued before the first audio, to delay the voice relative to the mouth. */
	UPROPERTY(EditAnywhere, Category = "Lip Sync", meta = (ClampMin = 0, ClampMax = 1000))
	int32 AudioDelayMs = 0;

	UPROPERTY(EditAnywhere, Category = "Lip Sync", meta = (EditCondition = "MouthDriver == EPatientMouthDriver::Envelope"))
	float EnvelopeGain = 8.0f;

	UPROPERTY(EditAnywhere, Category = "Debug")
	bool bShowOnScreenStats = true;

	UFUNCTION(BlueprintCallable, Category = "Patient Voice")
	void Connect();

	UFUNCTION(BlueprintCallable, Category = "Patient Voice")
	void Disconnect();

protected:
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	virtual void TickComponent(float DeltaTime, ELevelTick TickType, FActorComponentTickFunction* ThisTickFunction) override;

private:
	void HandlePcm(const int16* Samples, int32 SamplesPerChannel, int32 SampleRate, int32 NumChannels);
	void SetStatus(const FString& Status);
	void LogStats();

	UPROPERTY(Transient)
	TObjectPtr<UAudioComponent> AudioComponent;

	UPROPERTY(Transient)
	TObjectPtr<USoundWaveProcedural> VoiceWave;

	TSharedPtr<FLiveKitPatientStream> Stream;
	TSharedPtr<FPatientMouthSolver> MouthSolver;
	TSharedPtr<FPatientVoiceLiveLinkSource> LiveLinkSource;
	FGuid LiveLinkSourceGuid;

	FCriticalSection StateLock;
	FString LatestStatus;
	int32 StreamSampleRate = 0;
	int32 StreamChannels = 0;
	bool bQueuedInitialDelay = false;
	double PcmSecondsReceived = 0.0;
	double MouthLatencyMsTotal = 0.0;
	int32 MouthFrames = 0;
	int32 MouthFramesTotal = 0;
	double LastStatsSeconds = 0.0;
};
