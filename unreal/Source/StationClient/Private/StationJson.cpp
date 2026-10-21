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

	bool ParseSpeaker(const FString& Text, EStationSpeaker& Out)
	{
		if (Text == TEXT("learner"))
		{
			Out = EStationSpeaker::Learner;
			return true;
		}
		if (Text == TEXT("patient"))
		{
			Out = EStationSpeaker::Patient;
			return true;
		}
		return false;
	}

	/** An optional string field: absent and JSON null both read as empty. */
	FString OptionalString(const FJsonObject& Json, const TCHAR* Field)
	{
		FString Text;
		Json.TryGetStringField(Field, Text);
		return Text;
	}

	/** Parses every object of an array field with `ParseItem`; false if the field or any item is malformed. */
	template <typename T>
	bool ParseArray(const FJsonObject& Json, const TCHAR* Field, TArray<T>& Out,
		TFunctionRef<bool(const FJsonObject&, T&)> ParseItem)
	{
		const TArray<TSharedPtr<FJsonValue>>* Items = nullptr;
		if (!Json.TryGetArrayField(Field, Items))
		{
			return false;
		}
		Out.Reset(Items->Num());
		for (const TSharedPtr<FJsonValue>& Item : *Items)
		{
			const TSharedPtr<FJsonObject>* Object = nullptr;
			if (!Item.IsValid() || !Item->TryGetObject(Object) || !ParseItem(**Object, Out.AddDefaulted_GetRef()))
			{
				return false;
			}
		}
		return true;
	}

	bool ParseImpresso(const FJsonObject& Json, FStationImpresso& Out)
	{
		return Json.TryGetStringField(TEXT("id"), Out.Id)
			&& Json.TryGetStringField(TEXT("title"), Out.Title)
			&& Json.TryGetStringField(TEXT("category"), Out.Category)
			&& Json.TryGetStringField(TEXT("content"), Out.Content);
	}

	bool ParseMessage(const FJsonObject& Json, FStationMessage& Out)
	{
		FString Role;
		return Json.TryGetStringField(TEXT("role"), Role)
			&& ParseSpeaker(Role, Out.Speaker)
			&& Json.TryGetStringField(TEXT("text"), Out.Text);
	}

	bool ParseEvidence(const FJsonObject& Json, FStationEvidence& Out)
	{
		FString Role;
		return Json.TryGetStringField(TEXT("id"), Out.Id)
			&& Json.TryGetStringField(TEXT("role"), Role)
			&& ParseSpeaker(Role, Out.Speaker)
			&& Json.TryGetStringField(TEXT("text"), Out.Text);
	}

	bool ParseCriterionStatus(const FString& Text, EStationCriterionStatus& Out)
	{
		if (Text == TEXT("assessed"))
		{
			Out = EStationCriterionStatus::Assessed;
		}
		else if (Text == TEXT("uncertain"))
		{
			Out = EStationCriterionStatus::Uncertain;
		}
		else if (Text == TEXT("not_observable"))
		{
			Out = EStationCriterionStatus::NotObservable;
		}
		else if (Text == TEXT("not_applicable"))
		{
			Out = EStationCriterionStatus::NotApplicable;
		}
		else
		{
			return false;
		}
		return true;
	}

	bool ParseCriterion(const FJsonObject& Json, FStationCriterionResult& Out)
	{
		FString Status;
		if (!Json.TryGetStringField(TEXT("id"), Out.Id)
			|| !Json.TryGetStringField(TEXT("description"), Out.Description)
			|| !Json.TryGetStringField(TEXT("status"), Status)
			|| !ParseCriterionStatus(Status, Out.Status)
			|| !Json.TryGetStringField(TEXT("max_points"), Out.MaxPoints)
			|| !ParseArray<FStationEvidence>(Json, TEXT("evidence"), Out.Evidence, ParseEvidence))
		{
			return false;
		}
		Out.Recommendation = OptionalString(Json, TEXT("recommendation"));
		Out.Reason = OptionalString(Json, TEXT("reason"));
		Out.Level = OptionalString(Json, TEXT("level"));
		Out.LevelDescription = OptionalString(Json, TEXT("level_description"));
		Out.Points = OptionalString(Json, TEXT("points"));
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
	Out.CompletionReason = OptionalString(Json, TEXT("completion_reason"));

	// Only the show body carries the transcript. A line the client cannot read
	// (for example a speaker added to Phoenix later) is skipped rather than
	// failing the whole session.
	Out.Messages.Reset();
	const TArray<TSharedPtr<FJsonValue>>* Lines = nullptr;
	if (Json.TryGetArrayField(TEXT("messages"), Lines))
	{
		for (const TSharedPtr<FJsonValue>& Line : *Lines)
		{
			const TSharedPtr<FJsonObject>* Object = nullptr;
			FStationMessage Message;
			if (Line.IsValid() && Line->TryGetObject(Object) && ParseMessage(**Object, Message))
			{
				Out.Messages.Add(MoveTemp(Message));
			}
		}
	}
	return true;
}

bool StationJson::ParseVoiceCredential(const FJsonObject& Json, FStationVoiceCredential& Out)
{
	return Json.TryGetStringField(TEXT("url"), Out.Url) && !Out.Url.IsEmpty()
		&& Json.TryGetStringField(TEXT("token"), Out.Token) && !Out.Token.IsEmpty()
		&& Json.TryGetStringField(TEXT("room"), Out.Room)
		&& Json.TryGetStringField(TEXT("identity"), Out.Identity)
		&& ParseDate(Json, TEXT("expires_at"), Out.ExpiresAt);
}

bool StationJson::ParseTurnReply(const FJsonObject& Json, FStationTurnReply& Out)
{
	const FString Outcome = OptionalString(Json, TEXT("outcome"));
	Out.ReplyAudioUrl = OptionalString(Json, TEXT("reply_audio_url"));
	Out.NewlyReleased.Reset();

	if (Outcome == TEXT("examiner_acknowledged"))
	{
		Out.Outcome = EStationTurnOutcome::ExaminerAcknowledged;
		Out.ReplyText.Reset();
		return !Json.HasField(TEXT("newly_released"))
			|| ParseArray<FStationImpresso>(Json, TEXT("newly_released"), Out.NewlyReleased, ParseImpresso);
	}
	if (!Outcome.IsEmpty() && Outcome != TEXT("patient_reply"))
	{
		return false;
	}
	Out.Outcome = EStationTurnOutcome::PatientReply;
	return Json.TryGetStringField(TEXT("reply_text"), Out.ReplyText);
}

bool StationJson::ParseImpressoReply(const FJsonObject& Json, FStationImpressoReply& Out)
{
	FString Decision;
	if (!Json.TryGetStringField(TEXT("request_id"), Out.RequestId)
		|| !Json.TryGetStringField(TEXT("decision"), Decision)
		|| !ParseArray<FStationImpresso>(Json, TEXT("released_impressos"), Out.ReleasedImpressos, ParseImpresso)
		|| !ParseArray<FStationImpresso>(Json, TEXT("newly_released"), Out.NewlyReleased, ParseImpresso))
	{
		return false;
	}
	if (Decision == TEXT("released"))
	{
		Out.Decision = EStationImpressoDecision::Released;
	}
	else if (Decision == TEXT("already_released"))
	{
		Out.Decision = EStationImpressoDecision::AlreadyReleased;
	}
	else if (Decision == TEXT("unavailable"))
	{
		Out.Decision = EStationImpressoDecision::Unavailable;
	}
	else
	{
		return false;
	}
	Out.FeedbackMessage = OptionalString(Json, TEXT("feedback_message"));
	return true;
}

bool StationJson::ParseImpressoList(const FJsonObject& Json, TArray<FStationImpresso>& Out)
{
	return ParseArray<FStationImpresso>(Json, TEXT("released_impressos"), Out, ParseImpresso);
}

bool StationJson::ParseFinish(const FJsonObject& Json, FStationSession& InOut)
{
	FString Status;
	FDateTime CompletedAt;
	if (!Json.TryGetStringField(TEXT("status"), Status)
		|| Status != TEXT("completed")
		|| !ParseDate(Json, TEXT("completed_at"), CompletedAt))
	{
		return false;
	}
	InOut.Status = EStationSessionStatus::Completed;
	InOut.CompletedAt = CompletedAt;
	InOut.CompletionReason = OptionalString(Json, TEXT("completion_reason"));
	return true;
}

bool StationJson::ParseResult(const FJsonObject& Json, FStationResult& Out)
{
	const TSharedPtr<FJsonObject>* Estimates = nullptr;
	if (!Json.TryGetStringField(TEXT("session_id"), Out.SessionId)
		|| !ParseArray<FStationCriterionResult>(Json, TEXT("criteria"), Out.Criteria, ParseCriterion)
		|| !Json.TryGetObjectField(TEXT("estimates"), Estimates)
		|| !(*Estimates)->TryGetStringField(TEXT("scored_subtotal"), Out.ScoredSubtotal)
		|| !(*Estimates)->TryGetStringField(TEXT("scored_max"), Out.ScoredMax)
		|| !(*Estimates)->TryGetStringField(TEXT("eligible_max"), Out.EligibleMax))
	{
		return false;
	}
	Out.EstimatedTotal = OptionalString(**Estimates, TEXT("total"));
	Out.bPlaceholder = false;
	Json.TryGetBoolField(TEXT("placeholder"), Out.bPlaceholder);
	return true;
}

