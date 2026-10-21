#include "LiveKitPatientStream.h"
#include "Modules/ModuleManager.h"
#include "PatientVoiceSpikeLog.h"

#if PLATFORM_WINDOWS
#include "HAL/PlatformProcess.h"
#include "Misc/Paths.h"
#endif

DEFINE_LOG_CATEGORY(LogPatientVoiceSpike);

class FPatientVoiceSpikeModule : public IModuleInterface
{
public:
	virtual void StartupModule() override
	{
#if PLATFORM_WINDOWS
		// Both DLLs are delay-loaded and staged next to the project binaries, which
		// are not on the default DLL search path of the editor executable.
		const FString BinDir = FPaths::Combine(FPaths::ProjectDir(), TEXT("Binaries/Win64"));
		for (const TCHAR* Dll : { TEXT("livekit_ffi.dll"), TEXT("livekit.dll") })
		{
			void* Handle = FPlatformProcess::GetDllHandle(*FPaths::Combine(BinDir, Dll));
			if (!Handle)
			{
				UE_LOG(LogPatientVoiceSpike, Error, TEXT("Failed to load %s from %s"), Dll, *BinDir);
			}
			DllHandles.Add(Handle);
		}
#endif
	}

	virtual void ShutdownModule() override
	{
		FLiveKitPatientStream::ShutdownSdk();
#if PLATFORM_WINDOWS
		for (void* Handle : DllHandles)
		{
			if (Handle)
			{
				FPlatformProcess::FreeDllHandle(Handle);
			}
		}
		DllHandles.Reset();
#endif
	}

private:
	TArray<void*> DllHandles;
};

IMPLEMENT_MODULE(FPatientVoiceSpikeModule, PatientVoiceSpike)
