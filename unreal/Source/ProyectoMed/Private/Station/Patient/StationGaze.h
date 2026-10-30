#pragma once

#include "CoreMinimal.h"
#include "Math/RandomStream.h"

/**
 * A direction in degrees from where the patient's face points: `Yaw` toward the
 * patient's left, `Pitch` up.
 */
struct FStationGazeAngles
{
	float Yaw = 0.f;
	float Pitch = 0.f;
};

/** What the conversation asks of the patient's gaze (#449). */
enum class EStationGazeMode : uint8
{
	/** No spoken run: the idle loops alone move the eyes and head. */
	Off,
	/** A spoken run with nobody speaking: the gaze rests, with a rare look at the learner. */
	Resting,
	/** The learner speaks: the patient looks at them most of the time. */
	Listening,
	/** The patient answers, or is about to: it looks at the learner a little less. */
	Answering,
};

/** What the gaze is doing now. */
enum class EStationGazePhase : uint8
{
	/** The idle loops have the eyes and head. */
	Rest,
	/** The patient looks at the learner. */
	Contact,
	/** A glance away: down, aside or at nothing, then back. */
	Away,
};

/** How the patient's gaze moves (#449). */
namespace StationGaze
{
	struct FSeconds
	{
		float Min = 0.f;
		float Max = 0.f;
	};

	/** How long the patient holds the learner's eyes in `Mode`. */
	FSeconds ContactSeconds(EStationGazeMode Mode);
	/** How long a glance away lasts in `Mode`; in `Resting`, how long the gaze rests. */
	FSeconds AwaySeconds(EStationGazeMode Mode);

	/** A glance away never strays further than this from the learner. */
	constexpr float MaxGlanceDegrees = 25.f;

	/** The eyes turn this far in the head at most: no rolled-back or cornered eyes. */
	constexpr float EyeMaxYaw = 30.f;
	constexpr float EyeMaxUp = 20.f;
	constexpr float EyeMaxDown = 25.f;

	/** A seated person turns the head this far toward someone across a desk. */
	constexpr float HeadMaxYaw = 25.f;
	constexpr float HeadMaxUp = 12.f;
	constexpr float HeadMaxDown = 20.f;

	/** Degrees per second: the eyes move quickly and the head slowly, never in a jump. */
	constexpr float EyeMaxSpeed = 250.f;
	constexpr float HeadMaxSpeed = 60.f;

	/** The direction `Angles` names, in the frame of `Forward`, `Left` and `Up`. */
	FVector Direction(const FVector& Forward, const FVector& Left, const FVector& Up, const FStationGazeAngles& Angles);
	/** The angles of `Direction` in the frame of `Forward`, `Left` and `Up`. */
	FStationGazeAngles AnglesOf(const FVector& Forward, const FVector& Left, const FVector& Up, const FVector& Direction);

	/**
	 * The MetaHuman eye-look controls that turn both eyes by `Eyes`. Both eyes get
	 * the same values, so they stay parallel and never cross.
	 */
	void EyeControls(const FStationGazeAngles& Eyes, TMap<FName, float>& OutControls);
	/** True for the raw MetaHuman eye-look controls, the only face controls the gaze moves. */
	bool IsEyeLookControl(FName RawControl);

	/**
	 * The local rotation that turns a bone by `Turn`, given in component space,
	 * about its own joint. `ParentComponent` is the parent's component-space rotation.
	 */
	FQuat TurnLocal(const FQuat& ParentComponent, const FQuat& Local, const FQuat& Turn);
}

/**
 * Decides where the patient looks from moment to moment (#449). During a spoken
 * exchange it holds the learner's eyes for stretches and breaks them now and then,
 * for irregular, bounded times. The turn is split between the head and the eyes,
 * clamped to a seated person's range and eased, so the gaze never snaps.
 */
class FStationGazeModel
{
public:
	explicit FStationGazeModel(int32 Seed = 0);

	/**
	 * Advances the gaze by `DeltaSeconds`. `ToLearner` is the learner's view as seen
	 * from where the face points before the gaze turns the head.
	 */
	void Tick(float DeltaSeconds, EStationGazeMode Mode, const FStationGazeAngles& ToLearner);

	/** How far the head turns, applied with `GetWeight`. */
	const FStationGazeAngles& GetHead() const { return Head; }
	/** How far the eyes turn in the head, applied with `GetWeight`. */
	const FStationGazeAngles& GetEyes() const { return Eyes; }
	/** How much the gaze overrides the idle loops, from 0 to 1. */
	float GetWeight() const { return Weight; }
	EStationGazePhase GetPhase() const { return Phase; }

private:
	void BeginPhase(EStationGazePhase NewPhase);

	FRandomStream Random;
	EStationGazeMode Mode = EStationGazeMode::Off;
	EStationGazePhase Phase = EStationGazePhase::Rest;
	float PhaseLeft = 0.f;
	/** Where a glance away goes, from the learner. */
	FStationGazeAngles Glance;
	/** What the head and eyes aim at together, held while the gaze rests. */
	FStationGazeAngles Aim;
	FStationGazeAngles Head;
	FStationGazeAngles Eyes;
	float Weight = 0.f;
};
