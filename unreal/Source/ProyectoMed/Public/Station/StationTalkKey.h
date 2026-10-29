// The learner's talk key in a voice training (#419).

#pragma once

#include "CoreMinimal.h"

/** What pressed the talk key. One input holds it at a time; only its release lets it go. */
enum class EStationTalkInput : uint8
{
	/** The space bar, or Shift + space bar for an exam request. */
	Keyboard,
	/** The HUD's talk button. */
	TalkButton,
	/** The HUD's exam microphone. */
	ExamButton,
};

/**
 * The talk key: the space bar, or the HUD's talk button on an iPad. The microphone
 * sends while the key is held and for a short tail after its release, so the last
 * word is not cut. While the patient answers, a single press does nothing: a tap
 * followed by a press opens the microphone, and that press cuts the patient. Times
 * are passed in, in seconds, so the specs drive it without waiting.
 */
class PROYECTOMED_API FStationTalkKey
{
public:
	/** Seconds the microphone keeps sending after the key is released. */
	static constexpr double TailSeconds = 0.15;
	/** Longest gap between a tap's release and the next press for that press to cut the patient. */
	static constexpr double DoubleTapSeconds = 0.4;

	/**
	 * The key went down on `Input`. True when this press opens the microphone. A press
	 * while another input holds the key changes nothing.
	 */
	bool Press(double Now, bool bPatientAnswering, EStationTalkInput Input = EStationTalkInput::Keyboard);
	/** The key went up on `Input`; ignored unless `Input` pressed it. */
	void Release(double Now, EStationTalkInput Input = EStationTalkInput::Keyboard);

	/** The key is down and its press opened the microphone. */
	bool IsHeld() const { return bDown && bOpened; }
	/** The microphone sends: the key is held, or was released less than `TailSeconds` ago. */
	bool IsOpen(double Now) const;
	/** Forgets every press, for a new run. */
	void Reset() { *this = FStationTalkKey(); }

private:
	bool bDown = false;
	bool bOpened = false;
	/** The input that holds the key while `bDown`. */
	EStationTalkInput DownInput = EStationTalkInput::Keyboard;
	/** When a press that opened the microphone was released. */
	double OpenReleasedAt = -1.0e9;
	/** When a press that opened nothing was released: the first tap of a cut. */
	double TapReleasedAt = -1.0e9;
};
