#include "StationVoiceLiveness.h"

void FStationVoiceLiveness::BeginConnecting(double Now, double Seconds)
{
	State = EStationVoiceState::Connecting;
	ConnectDeadline = Now + Seconds;
}

EStationVoiceState FStationVoiceLiveness::Update(const FSignals& Signals, double Now)
{
	if (State == EStationVoiceState::Failed)
	{
		return State;
	}
	if (!WaitingSince.IsSet())
	{
		WaitingSince = Now;
	}
	if (Signals.bReconnecting || (bWorkerAnswered && !Signals.bWorkerPresent))
	{
		if (State != EStationVoiceState::Reconnecting)
		{
			State = EStationVoiceState::Reconnecting;
			LostSince = Now;
		}
	}
	else if (Signals.bWorkerPresent)
	{
		State = EStationVoiceState::Ready;
		bWorkerAnswered = true;
	}
	else
	{
		State = EStationVoiceState::WaitingForWorker;
	}
	return Tick(Now);
}

EStationVoiceState FStationVoiceLiveness::Tick(double Now)
{
	const bool bNeverConnected = State == EStationVoiceState::Connecting && Now >= ConnectDeadline;
	const bool bNotBack = State == EStationVoiceState::Reconnecting && Now - LostSince >= GraceSeconds;
	const bool bNeverJoined = State == EStationVoiceState::WaitingForWorker && WaitingSince.IsSet()
		&& Now - WaitingSince.GetValue() >= FirstJoinSeconds;
	if (bNeverConnected || bNotBack || bNeverJoined)
	{
		Failure = bNeverConnected ? EFailure::NeverConnected : bNotBack ? EFailure::VoiceNotBack : EFailure::WorkerNeverJoined;
		State = EStationVoiceState::Failed;
	}
	return State;
}
