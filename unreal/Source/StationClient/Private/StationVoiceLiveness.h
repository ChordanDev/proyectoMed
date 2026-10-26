// Whether a joined voice link can still be heard (#191). Game thread.

#pragma once

#include "CoreMinimal.h"
#include "StationVoice.h"

/**
 * The state a published voice link shows, from what LiveKit reports. While LiveKit
 * retries the room connection, or once the voice worker that answered has left,
 * the link is `Reconnecting`; after `GraceSeconds` of that the voice is lost for
 * good and the link is `Failed`. The worker has `FirstJoinSeconds` from the first
 * report to join, or the voice is lost too.
 */
class FStationVoiceLiveness
{
public:
	static constexpr double GraceSeconds = 10.0;
	static constexpr double FirstJoinSeconds = 20.0;

	/** The rule that made the voice lost. */
	enum class EFailure : uint8
	{
		None,
		/** The worker did not join within `FirstJoinSeconds`. */
		WorkerNeverJoined,
		/** The voice did not come back within `GraceSeconds`. */
		VoiceNotBack,
	};

	/** What LiveKit reports, read on its thread. */
	struct FSignals
	{
		bool bWorkerPresent = false;
		bool bReconnecting = false;
	};

	/** The state to show once LiveKit reported `Signals` at `Now`, in seconds. */
	EStationVoiceState Update(const FSignals& Signals, double Now);

	/** The state to show at `Now` with no news from LiveKit. */
	EStationVoiceState Tick(double Now);

	/** Which rule fired once the state is `Failed`, `None` before. */
	EFailure GetFailure() const { return Failure; }

private:
	EFailure Failure = EFailure::None;
	EStationVoiceState State = EStationVoiceState::WaitingForWorker;
	bool bWorkerAnswered = false;
	TOptional<double> WaitingSince;
	double LostSince = 0.0;
};
