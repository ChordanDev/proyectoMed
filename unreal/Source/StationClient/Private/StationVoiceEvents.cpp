#include "Dom/JsonObject.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "StationJson.h"
#include "StationVoice.h"

namespace
{
	/** A JSON number that is a whole number of at least `Min`. */
	bool ReadWholeNumber(const FJsonObject& Object, const TCHAR* Field, int32 Min, int32& Out)
	{
		const TSharedPtr<FJsonValue> Value = Object.TryGetField(Field);
		if (!Value.IsValid() || Value->Type != EJson::Number)
		{
			return false;
		}
		const double Number = Value->AsNumber();
		if (Number != FMath::FloorToDouble(Number) || Number < Min || Number > MAX_int32)
		{
			return false;
		}
		Out = static_cast<int32>(Number);
		return true;
	}

	bool ReadString(const FJsonObject& Object, const TCHAR* Field, FString& Out)
	{
		const TSharedPtr<FJsonValue> Value = Object.TryGetField(Field);
		if (!Value.IsValid() || Value->Type != EJson::String)
		{
			return false;
		}
		Out = Value->AsString();
		return true;
	}

	bool ReadNonBlank(const FJsonObject& Object, const TCHAR* Field, FString& Out)
	{
		return ReadString(Object, Field, Out) && !Out.TrimStartAndEnd().IsEmpty();
	}

	/** The outcome of a spoken exam request (#364): its `newly_released` items carry no `content`. */
	bool ReadImpressoOutcome(const FJsonObject& Object, FStationImpressoReply& Out)
	{
		FString Decision;
		const TArray<TSharedPtr<FJsonValue>>* Released = nullptr;
		if (!ReadNonBlank(Object, TEXT("request_id"), Out.RequestId)
			|| !ReadString(Object, TEXT("decision"), Decision)
			|| !StationJson::ParseImpressoDecision(Decision, Out.Decision)
			|| !Object.TryGetArrayField(TEXT("newly_released"), Released))
		{
			return false;
		}
		for (const TSharedPtr<FJsonValue>& Item : *Released)
		{
			const TSharedPtr<FJsonObject>* Impresso = nullptr;
			FStationImpresso& Read = Out.NewlyReleased.AddDefaulted_GetRef();
			if (!Item.IsValid() || !Item->TryGetObject(Impresso)
				|| !ReadNonBlank(**Impresso, TEXT("id"), Read.Id)
				|| !ReadString(**Impresso, TEXT("title"), Read.Title)
				|| !ReadString(**Impresso, TEXT("category"), Read.Category))
			{
				return false;
			}
		}
		// Phoenix always sends it; a missing one shows nothing rather than dropping the outcome.
		ReadString(Object, TEXT("feedback_message"), Out.FeedbackMessage);
		return true;
	}
}

TOptional<FStationVoiceEvent> ParseStationVoiceEvent(TConstArrayView<uint8> Payload, const FString& SessionId)
{
	const FUTF8ToTCHAR Text(reinterpret_cast<const ANSICHAR*>(Payload.GetData()), Payload.Num());
	TSharedPtr<FJsonObject> Body;
	if (!FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(FString(Text.Length(), Text.Get())), Body)
		|| !Body.IsValid())
	{
		return {};
	}

	FString EventSession;
	if (!ReadString(*Body, TEXT("session_id"), EventSession) || !EventSession.Equals(SessionId, ESearchCase::CaseSensitive))
	{
		return {};
	}

	FStationVoiceEvent Event;
	if (ReadNonBlank(*Body, TEXT("error"), Event.Failure) && !Body->HasField(TEXT("turn_id")))
	{
		Event.Kind = EStationVoiceEventKind::Fatal;
		return Event;
	}
	if (!ReadWholeNumber(*Body, TEXT("turn_id"), 1, Event.TurnId))
	{
		return {};
	}

	if (ReadNonBlank(*Body, TEXT("failure"), Event.Failure))
	{
		Event.Kind = EStationVoiceEventKind::TurnFailure;
		return Event;
	}

	FString Role;
	FString Status;
	ReadString(*Body, TEXT("status"), Status);
	if (Body->HasField(TEXT("role")))
	{
		if (!ReadString(*Body, TEXT("role"), Role))
		{
			return {};
		}
		if (Role.Equals(TEXT("patient"), ESearchCase::CaseSensitive))
		{
			if (Status.Equals(TEXT("complete"), ESearchCase::CaseSensitive))
			{
				Event.Kind = EStationVoiceEventKind::PatientComplete;
				return Event;
			}
			if (!ReadNonBlank(*Body, TEXT("text"), Event.Text))
			{
				return {};
			}
			if (Body->HasField(TEXT("segment")) && !ReadWholeNumber(*Body, TEXT("segment"), 0, Event.Segment))
			{
				return {};
			}
			Event.Kind = EStationVoiceEventKind::PatientText;
			return Event;
		}
		if (Role.Equals(TEXT("examiner"), ESearchCase::CaseSensitive))
		{
			if (Status.Equals(TEXT("acknowledged"), ESearchCase::CaseSensitive))
			{
				Event.Kind = EStationVoiceEventKind::ExaminerAcknowledged;
				return Event;
			}
			if (Status.Equals(TEXT("kept"), ESearchCase::CaseSensitive))
			{
				Event.Kind = EStationVoiceEventKind::PatientUnanswered;
				return Event;
			}
			if (Status.Equals(TEXT("impresso_requested"), ESearchCase::CaseSensitive))
			{
				if (!ReadImpressoOutcome(*Body, Event.Impresso))
				{
					return {};
				}
				Event.Kind = EStationVoiceEventKind::ExaminerImpresso;
				return Event;
			}
		}
		return {};
	}

	const TSharedPtr<FJsonValue> Final = Body->TryGetField(TEXT("final"));
	if (!Final.IsValid() || Final->Type != EJson::Boolean || !ReadString(*Body, TEXT("text"), Event.Text))
	{
		return {};
	}
	Event.bFinal = Final->AsBool();
	if (Event.bFinal && Event.Text.TrimStartAndEnd().IsEmpty())
	{
		return {};
	}
	Event.Kind = EStationVoiceEventKind::Learner;
	return Event;
}
