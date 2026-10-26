// The operating system's microphone permission (#191).

#pragma once

#include "CoreMinimal.h"

/** Whether the operating system lets this app use the microphone. */
enum class EStationMicPermission : uint8
{
	Granted,
	Denied,
	/** Never asked: the first request shows the system's prompt. */
	NotDetermined,
};

namespace StationMicPermission
{
	PROYECTOMED_API EStationMicPermission Get();

	/**
	 * Shows the system's microphone prompt when it was never answered, otherwise
	 * answers at once. `OnDone` runs on the game thread. On Windows the privacy
	 * settings decide and no prompt exists, so the answer is `Granted`.
	 */
	PROYECTOMED_API void Request(TFunction<void(EStationMicPermission)> OnDone);
}
