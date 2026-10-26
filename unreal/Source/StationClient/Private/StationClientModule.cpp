#include "Async/Async.h"
#include "Modules/ModuleManager.h"
#include "StationClientLog.h"
#include "StationLiveKit.h"

THIRD_PARTY_INCLUDES_START
#include "livekit/livekit.h"
THIRD_PARTY_INCLUDES_END

#if PLATFORM_WINDOWS
#include "HAL/PlatformProcess.h"
#include "Misc/Paths.h"
#endif

DEFINE_LOG_CATEGORY(LogStationClient);

namespace
{
	/** True when this module initialised the SDK, and so shuts it down. */
	bool GOwnsLiveKit = false;
	bool GLiveKitReady = false;
	FCriticalSection GLiveKitLock;
	TArray<TFuture<void>> GTeardowns;

	/** How long quitting waits for rooms still being left before giving up on a clean SDK shutdown. */
	const FTimespan TeardownGrace = FTimespan::FromSeconds(2.0);
}

bool StationLiveKit::EnsureInitialized()
{
	FScopeLock Lock(&GLiveKitLock);
	if (!GLiveKitReady)
	{
		// `initialize` answers false when another module (the #189 spike) already did it.
		GOwnsLiveKit = livekit::initialize(livekit::LogLevel::Warn);
		GLiveKitReady = true;
	}
	return GLiveKitReady;
}

void StationLiveKit::RunTeardown(TUniqueFunction<void()> Teardown)
{
	FScopeLock Lock(&GLiveKitLock);
	GTeardowns.RemoveAll([](const TFuture<void>& Pending) { return Pending.IsReady(); });
	GTeardowns.Add(Async(EAsyncExecution::Thread, MoveTemp(Teardown)));
}

void StationLiveKit::Shutdown()
{
	FScopeLock Lock(&GLiveKitLock);
	bool bAllLeft = true;
	for (TFuture<void>& Pending : GTeardowns)
	{
		bAllLeft &= Pending.WaitFor(TeardownGrace);
	}
	GTeardowns.Reset();
	// A room still hanging on an unreachable server keeps the SDK; the process is ending anyway.
	if (GOwnsLiveKit && bAllLeft)
	{
		livekit::shutdown();
	}
	GOwnsLiveKit = false;
	GLiveKitReady = false;
}

class FStationClientModule : public IModuleInterface
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
				UE_LOG(LogStationClient, Error, TEXT("Failed to load %s from %s"), Dll, *BinDir);
			}
			DllHandles.Add(Handle);
		}
#endif
	}

	virtual void ShutdownModule() override
	{
		StationLiveKit::Shutdown();
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

IMPLEMENT_MODULE(FStationClientModule, StationClient)
