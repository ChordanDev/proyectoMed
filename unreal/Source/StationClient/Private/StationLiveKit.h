#pragma once

#include "CoreMinimal.h"

namespace StationLiveKit
{
	/** Initialises the LiveKit SDK once per process, or reuses it; true when it is ready. Any thread. */
	bool EnsureInitialized();

	/** Runs a room teardown on a background thread, so leaving never holds up the game. */
	void RunTeardown(TUniqueFunction<void()> Teardown);

	/**
	 * Waits briefly for teardowns still running, then shuts the SDK down if this
	 * module initialised it. Module shutdown only.
	 */
	void Shutdown();
}
