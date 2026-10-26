// Whether the voice worker is in the room (#191). Written by the connect and SDK threads, read by the game thread.

#pragma once

#include "CoreMinimal.h"

#include <atomic>

/**
 * Three-state presence of the voice worker. A join or leave event is news about now
 * and always wins; the scan of the participants already in the room on connect is
 * only a snapshot, so it may settle an unknown state but never overrides an event
 * that arrived while it ran. Unknown reads as absent.
 */
class FStationWorkerPresence
{
public:
	/** The worker joined the room. */
	void OnJoined() { State = EState::Present; }

	/** The worker left the room. */
	void OnLeft() { State = EState::Absent; }

	/** The connect-time scan found the worker. */
	void OnSeenInScan()
	{
		EState Expected = EState::Unknown;
		State.compare_exchange_strong(Expected, EState::Present);
	}

	bool IsPresent() const { return State == EState::Present; }

private:
	enum class EState : uint8
	{
		Unknown,
		Present,
		Absent,
	};

	std::atomic<EState> State{EState::Unknown};
};
