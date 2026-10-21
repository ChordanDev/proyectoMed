#include "StationJson.h"

#include "Dom/JsonObject.h"

namespace
{
	bool ParseVoiceMode(const FString& Text, EStationVoiceMode& Out)
	{
		if (Text == TEXT("realtime"))
		{
			Out = EStationVoiceMode::Realtime;
		}
		else if (Text == TEXT("turn"))
		{
			Out = EStationVoiceMode::Turn;
		}
		else if (Text == TEXT("off"))
		{
			Out = EStationVoiceMode::Off;
		}
		else
		{
			return false;
		}
		return true;
	}
}

bool StationJson::ParseDate(const FJsonObject& Json, const TCHAR* Field, FDateTime& Out)
{
	FString Text;
	return Json.TryGetStringField(Field, Text) && FDateTime::ParseIso8601(*Text, Out);
}

bool StationJson::ParseSummary(const FJsonObject& Json, FStationSummary& Out)
{
	const TSharedPtr<FJsonObject>* Brief = nullptr;
	const TArray<TSharedPtr<FJsonValue>>* Tasks = nullptr;
	FString VoiceMode;

	if (!Json.TryGetStringField(TEXT("station_id"), Out.StationId)
		|| !Json.TryGetStringField(TEXT("version"), Out.Version)
		|| !Json.TryGetStringField(TEXT("language"), Out.Language)
		|| !Json.TryGetStringField(TEXT("display_title"), Out.DisplayTitle)
		|| !Json.TryGetObjectField(TEXT("candidate_brief"), Brief)
		|| !(*Brief)->TryGetStringField(TEXT("scenario"), Out.Scenario)
		|| !(*Brief)->TryGetArrayField(TEXT("tasks"), Tasks)
		|| !Json.TryGetStringField(TEXT("voice_mode"), VoiceMode)
		|| !ParseVoiceMode(VoiceMode, Out.VoiceMode))
	{
		return false;
	}

	Out.Tasks.Reset(Tasks->Num());
	for (const TSharedPtr<FJsonValue>& Task : *Tasks)
	{
		FString Text;
		if (!Task.IsValid() || !Task->TryGetString(Text))
		{
			return false;
		}
		Out.Tasks.Add(MoveTemp(Text));
	}
	return true;
}

bool StationJson::ParseSession(const FJsonObject& Json, FStationSession& Out, FDateTime& OutServerNow)
{
	if (!Json.TryGetStringField(TEXT("session_id"), Out.SessionId)
		|| Out.SessionId.IsEmpty()
		|| !Json.TryGetStringField(TEXT("station_id"), Out.StationId)
		|| !Json.TryGetStringField(TEXT("station_version"), Out.StationVersion)
		|| !Json.TryGetBoolField(TEXT("audio_consent"), Out.bAudioConsent)
		|| !ParseDate(Json, TEXT("started_at"), Out.StartedAt)
		|| !ParseDate(Json, TEXT("deadline_at"), Out.DeadlineAt)
		|| !ParseDate(Json, TEXT("expires_at"), Out.ExpiresAt)
		|| !ParseDate(Json, TEXT("server_now"), OutServerNow))
	{
		return false;
	}

	// Only the show body carries status and completion_reason; a new session is active.
	FString Status;
	Out.Status = Json.TryGetStringField(TEXT("status"), Status) && Status == TEXT("completed")
		? EStationSessionStatus::Completed
		: EStationSessionStatus::Active;
	Out.CompletionReason.Reset();
	Json.TryGetStringField(TEXT("completion_reason"), Out.CompletionReason);
	return true;
}
