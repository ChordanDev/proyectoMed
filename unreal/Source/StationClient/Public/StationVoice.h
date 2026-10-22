// The run's LiveKit voice link (#191): publishes the learner's microphone to the
// run's room and delivers what the voice worker sends back, the patient's voice
// as PCM and the `transcript` events. Audio never goes through Phoenix. Its
// contract is documented in docs/unreal-station-client.md.

#pragma once

#include "CoreMinimal.h"
#include "StationClientTypes.h"
#include "Templates/SharedPointer.h"

/** What the voice worker said on the `transcript` topic, as the web client reads it. */
enum class EStationVoiceEventKind : uint8
{
	/** The learner's speech: an interim caption, or the final turn transcript. */
	Learner,
	/** One verified sentence of the patient reply, as spoken. */
	PatientText,
	/** Every sentence of a streamed reply was sent; carries no text. */
	PatientComplete,
	/** The turn was addressed to the examiner; Phoenix kept it unanswered. */
	ExaminerAcknowledged,
	/** The patient reply was refused; Phoenix kept the learner turn without one. */
	PatientUnanswered,
	/** A failure of one turn, for example `synthesis_failed`; the run goes on. */
	TurnFailure,
	/** The worker stopped listening to this run. */
	Fatal,
};

struct STATIONCLIENT_API FStationVoiceEvent
{
	EStationVoiceEventKind Kind = EStationVoiceEventKind::Learner;
	/** Phoenix's turn id; 0 only for `Fatal`. */
	int32 TurnId = 0;
	/** `Learner` only: false for an interim caption. */
	bool bFinal = false;
	/** `PatientText` only: the sentence index of a streamed reply, or INDEX_NONE. */
	int32 Segment = INDEX_NONE;
	/** `Learner` and `PatientText`: the text. Shown to the learner, never logged. */
	FString Text;
	/** `TurnFailure` and `Fatal`: the failure code. */
	FString Failure;
};

/**
 * Reads one `transcript` data message. Strict like the web parser
 * (web/src/features/station/hooks/voiceTranscriptEvents.ts): anything malformed,
 * or bound to another session, is dropped.
 */
STATIONCLIENT_API TOptional<FStationVoiceEvent> ParseStationVoiceEvent(TConstArrayView<uint8> Payload, const FString& SessionId);
