#pragma once

#include "CoreMinimal.h"

/** How the patient's speaking mouth is layered over the idle face (#191). */
namespace StationFaceBlend
{
	/**
	 * True for the raw MetaHuman controls of the jaw, mouth, lips, tongue and teeth:
	 * the ones speech moves. The idle loop keeps the eyes, brows and the rest.
	 */
	bool IsMouthControl(FName RawControl);

	/**
	 * Moves the weight of the speaking mouth toward 1 while the patient is heard and
	 * back to 0 once the voice stops, smoothly, so the face never snaps between
	 * idle and speech.
	 */
	float StepSpeechWeight(float Weight, bool bSpeaking, float DeltaSeconds);

	/** How long after the last audio the patient still counts as speaking. */
	constexpr double SpeechHoldSeconds = 0.25;
}
