// Whether a joined voice link can still be heard (#191). Game thread.

#pragma once

#include "CoreMinimal.h"
#include "StationVoice.h"

/**
 * The state a voice link shows, from what LiveKit reports. A link that started
 * joining has `ConnectSeconds` to publish the microphone, or the voice is lost and
 * the link is `Failed`; the first report ends that wait. While LiveKit retries the
 * room connection, or once the voice worker that answered has left, the link is
 * `Reconnecting`; after `GraceSeconds` of that the voice is lost for good. The
 * worker has `FirstJoinSeconds` from the first report to join, or the voice is lost
 * too.
 */
class FStationVoiceLiveness
{
public:
	/**
	 * Longer than a healthy join, shorter than the SDK can take to give up: it retries
	 * a join three times, and only its signal and ICE steps have their own timeouts.
	 */
	static constexpr double ConnectSeconds = 30.0;
	static constexpr double GraceSeconds = 10.0;
	static constexpr double FirstJoinSeconds = 20.0;

	/** The rule that made the voice lost. */
	enum class EFailure : uint8
	{
		None,
		/** Joining and publishing did not finish within `ConnectSeconds`. */
		NeverConnected,
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

	/** The link started joining at `Now`, in seconds, and has `Seconds` to publish. */
	void BeginConnecting(double Now, double Seconds = ConnectSeconds);

	/** The state to show once LiveKit reported `Signals` at `Now`, in seconds. */
	EStationVoiceState Update(const FSignals& Signals, double Now);

	/** The state to show at `Now` with no news from LiveKit. */
	EStationVoiceState Tick(double Now);

	/** Which rule fired once the state is `Failed`, `None` before. */
	EFailure GetFailure() const { return Failure; }

	/** Whether the first report since `BeginConnecting` is still to come. */
	bool IsConnecting() const { return State == EStationVoiceState::Connecting; }

private:
	EFailure Failure = EFailure::None;
	EStationVoiceState State = EStationVoiceState::WaitingForWorker;
	bool bWorkerAnswered = false;
	TOptional<double> WaitingSince;
	double LostSince = 0.0;
	double ConnectDeadline = 0.0;
};
