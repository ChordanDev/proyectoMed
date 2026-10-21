#pragma once

#include "CoreMinimal.h"

/**
 * Joins a LiveKit room and delivers the PCM of one remote audio track.
 * Keeps every LiveKit SDK type inside the .cpp so the rest of the module never
 * sees std:: or livekit:: types.
 */
class FLiveKitPatientStream
{
public:
	/** Called on a LiveKit dispatcher thread with interleaved int16 PCM. */
	using FOnPcm = TFunction<void(const int16* Samples, int32 SamplesPerChannel, int32 SampleRate, int32 NumChannels)>;
	/** Called on any thread with a human-readable status line. */
	using FOnStatus = TFunction<void(const FString& Status)>;

	struct FConfig
	{
		FString Url;
		FString Token;
		FString PublisherIdentity;
		FString TrackName;
	};

	FLiveKitPatientStream(FConfig InConfig, FOnPcm InOnPcm, FOnStatus InOnStatus);
	~FLiveKitPatientStream();

	/** Connects on a background thread; returns immediately. */
	void Start();

	/** Disconnects and waits for the background thread. Safe to call twice. */
	void Stop();

	/** Initialises the LiveKit SDK once per process. */
	static bool InitializeSdk();
	static void ShutdownSdk();

private:
	struct FImpl;
	TUniquePtr<FImpl> Impl;
};
