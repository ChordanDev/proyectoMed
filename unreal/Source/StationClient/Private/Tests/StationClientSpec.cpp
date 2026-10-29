// Station client tests. `ProyectoMed.StationClient.Unit` needs nothing else;
// `ProyectoMed.StationClient.Phoenix` needs a locally running Phoenix at
// $STATION_PHOENIX_URL (default http://127.0.0.1:4000). See
// docs/unreal-station-client.md for how to run them.

#include "Dom/JsonObject.h"
#include "Dom/JsonValue.h"
#include "Misc/AutomationTest.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "StationClient.h"
#include "StationClock.h"
#include "StationHttp.h"
#include "StationJson.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace StationClientTests
{
	TSharedRef<FJsonObject> ParseObject(const FString& Text)
	{
		TSharedPtr<FJsonObject> Object;
		FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text), Object);
		return Object.IsValid() ? Object.ToSharedRef() : MakeShared<FJsonObject>();
	}

	FString PhoenixUrl()
	{
		const FString FromEnv = FPlatformMisc::GetEnvironmentVariable(TEXT("STATION_PHOENIX_URL"));
		return FromEnv.IsEmpty() ? TEXT("http://127.0.0.1:4000") : FromEnv;
	}

	// A session body as Phoenix's create_session serializes it (microsecond precision).
	const TCHAR* SessionJson = TEXT(R"({
		"session_id": "abc123",
		"station_id": "chest-pain-initial-assessment",
		"station_version": "1.0.0",
		"audio_consent": true,
		"started_at": "2026-10-21T12:00:00.123456Z",
		"expires_at": "2026-10-21T12:30:00.123456Z",
		"deadline_at": "2026-10-21T12:10:00.123456Z",
		"server_now": "2026-10-21T12:00:00.200000Z"
	})");
}

BEGIN_DEFINE_SPEC(FStationClientUnitSpec, "ProyectoMed.StationClient.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
END_DEFINE_SPEC(FStationClientUnitSpec)

void FStationClientUnitSpec::Define()
{
	using namespace StationClientTests;

	Describe("FStationClock", [this]()
	{
		const FDateTime ServerNow(2026, 10, 21, 12, 0, 0);
		const FDateTime Deadline(2026, 10, 21, 12, 10, 0);

		It("counts down from the server deadline by local elapsed time", [this, ServerNow, Deadline]()
		{
			const FStationClock Clock = FStationClock::Anchor(ServerNow, 100.0);
			TestEqual("at the anchor", Clock.RemainingAt(Deadline, 100.0), FTimespan::FromMinutes(10));
			TestEqual("one minute later", Clock.RemainingAt(Deadline, 160.0), FTimespan::FromMinutes(9));
			TestEqual("server time", Clock.ServerTimeAt(130.5), ServerNow + FTimespan::FromSeconds(30.5));
		});

		It("never goes below zero after the deadline", [this, ServerNow, Deadline]()
		{
			const FStationClock Clock = FStationClock::Anchor(ServerNow, 0.0);
			TestEqual("past the deadline", Clock.RemainingAt(Deadline, 3600.0), FTimespan::Zero());
		});

		It("is not anchored until a server time is given", [this]()
		{
			TestFalse("default clock", FStationClock().IsAnchored());
		});
	});

	Describe("StationJson", [this]()
	{
		It("parses the active station", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(R"({
				"station_id": "chest-pain-initial-assessment",
				"version": "1.0.0",
				"language": "pt-BR",
				"display_title": "Dor torácica",
				"candidate_brief": {"scenario": "Você é o médico de plantão.", "tasks": ["Anamnese", "Exame físico"]},
				"voice_mode": "realtime"
			})"));

			FStationSummary Summary;
			TestTrue("parsed", StationJson::ParseSummary(*Json, Summary));
			TestEqual("id", Summary.StationId, TEXT("chest-pain-initial-assessment"));
			TestEqual("version", Summary.Version, TEXT("1.0.0"));
			TestEqual("language", Summary.Language, TEXT("pt-BR"));
			TestEqual("title", Summary.DisplayTitle, TEXT("Dor torácica"));
			TestEqual("scenario", Summary.Scenario, TEXT("Você é o médico de plantão."));
			TestEqual("task count", Summary.Tasks.Num(), 2);
			if (Summary.Tasks.Num() == 2)
			{
				TestEqual("task order", Summary.Tasks[1], TEXT("Exame físico"));
			}
			TestEqual("voice mode", Summary.VoiceMode, EStationVoiceMode::Realtime);
		});

		It("maps every voice mode", [this]()
		{
			const TPair<const TCHAR*, EStationVoiceMode> Cases[] = {
				{TEXT("realtime"), EStationVoiceMode::Realtime},
				{TEXT("turn"), EStationVoiceMode::Turn},
				{TEXT("off"), EStationVoiceMode::Off},
			};
			for (const TPair<const TCHAR*, EStationVoiceMode>& Case : Cases)
			{
				const TSharedRef<FJsonObject> Json = ParseObject(FString::Printf(TEXT(
					R"({"station_id":"s","version":"1","language":"pt-BR","display_title":"t","candidate_brief":{"scenario":"x","tasks":[]},"voice_mode":"%s"})"),
					Case.Key));
				FStationSummary Summary;
				TestTrue(FString::Printf(TEXT("parsed %s"), Case.Key), StationJson::ParseSummary(*Json, Summary));
				TestEqual(FString::Printf(TEXT("mode %s"), Case.Key), Summary.VoiceMode, Case.Value);
			}
		});

		It("rejects an active station without a candidate brief", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(
				R"({"station_id":"s","version":"1","language":"pt-BR","display_title":"t","voice_mode":"off"})"));
			FStationSummary Summary;
			TestFalse("parsed", StationJson::ParseSummary(*Json, Summary));
		});

		It("parses a session with microsecond timestamps", [this]()
		{
			FStationSession Session;
			FDateTime ServerNow;
			TestTrue("parsed", StationJson::ParseSession(*ParseObject(SessionJson), Session, ServerNow));
			TestEqual("id", Session.SessionId, TEXT("abc123"));
			TestEqual("station", Session.StationId, TEXT("chest-pain-initial-assessment"));
			TestEqual("version", Session.StationVersion, TEXT("1.0.0"));
			TestTrue("consent", Session.bAudioConsent);
			TestEqual("status defaults to active", Session.Status, EStationSessionStatus::Active);
			TestEqual("started", Session.StartedAt, FDateTime(2026, 10, 21, 12, 0, 0, 123));
			TestEqual("deadline", Session.DeadlineAt, FDateTime(2026, 10, 21, 12, 10, 0, 123));
			TestEqual("expires", Session.ExpiresAt, FDateTime(2026, 10, 21, 12, 30, 0, 123));
			TestEqual("server now", ServerNow, FDateTime(2026, 10, 21, 12, 0, 0, 200));
		});

		It("reads a session without a mode as a training, as Phoenix served it before #421", [this]()
		{
			FStationSession Session;
			FDateTime ServerNow;
			TestTrue("parsed", StationJson::ParseSession(*ParseObject(SessionJson), Session, ServerNow));
			TestEqual("mode", Session.Mode, EStationSessionMode::Training);

			const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
			Json->SetField(TEXT("mode"), MakeShared<FJsonValueNull>());
			TestTrue("parsed null", StationJson::ParseSession(*Json, Session, ServerNow));
			TestEqual("null mode", Session.Mode, EStationSessionMode::Training);
		});

		It("maps every Station Mode", [this]()
		{
			const TPair<const TCHAR*, EStationSessionMode> Cases[] = {
				{TEXT("training"), EStationSessionMode::Training},
				{TEXT("simulated_exam"), EStationSessionMode::SimulatedExam},
			};
			for (const TPair<const TCHAR*, EStationSessionMode>& Case : Cases)
			{
				const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
				Json->SetStringField(TEXT("mode"), Case.Key);
				FStationSession Session;
				FDateTime ServerNow;
				TestTrue(FString::Printf(TEXT("parsed %s"), Case.Key), StationJson::ParseSession(*Json, Session, ServerNow));
				TestEqual(FString::Printf(TEXT("mode %s"), Case.Key), Session.Mode, Case.Value);
			}
		});

		It("rejects a session with a mode it does not know", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
			Json->SetStringField(TEXT("mode"), TEXT("exam"));
			FStationSession Session;
			FDateTime ServerNow;
			TestFalse("parsed", StationJson::ParseSession(*Json, Session, ServerNow));
		});

		It("reads the status and completion reason of a shown session", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
			Json->SetStringField(TEXT("status"), TEXT("completed"));
			Json->SetStringField(TEXT("completion_reason"), TEXT("timer"));
			FStationSession Session;
			FDateTime ServerNow;
			TestTrue("parsed", StationJson::ParseSession(*Json, Session, ServerNow));
			TestEqual("status", Session.Status, EStationSessionStatus::Completed);
			TestEqual("reason", Session.CompletionReason, TEXT("timer"));
		});

		It("rejects a session without an id", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
			Json->RemoveField(TEXT("session_id"));
			FStationSession Session;
			FDateTime ServerNow;
			TestFalse("parsed", StationJson::ParseSession(*Json, Session, ServerNow));
		});

		It("rejects a session with a malformed deadline", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
			Json->SetStringField(TEXT("deadline_at"), TEXT("soon"));
			FStationSession Session;
			FDateTime ServerNow;
			TestFalse("parsed", StationJson::ParseSession(*Json, Session, ServerNow));
		});

		It("parses a voice credential", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(R"({
				"url": "ws://127.0.0.1:7880",
				"token": "eyJ.test.token",
				"room": "station-session-abc123",
				"identity": "learner-abc123",
				"expires_at": "2026-10-21T12:02:00.000000Z"
			})"));
			FStationVoiceCredential Credential;
			TestTrue("parsed", StationJson::ParseVoiceCredential(*Json, Credential));
			TestEqual("url", Credential.Url, TEXT("ws://127.0.0.1:7880"));
			TestEqual("token", Credential.Token, TEXT("eyJ.test.token"));
			TestEqual("room", Credential.Room, TEXT("station-session-abc123"));
			TestEqual("identity", Credential.Identity, TEXT("learner-abc123"));
			TestEqual("expires", Credential.ExpiresAt, FDateTime(2026, 10, 21, 12, 2, 0));
		});

		It("rejects a voice credential without a token", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(
				R"({"url":"ws://x","room":"r","identity":"i","expires_at":"2026-10-21T12:02:00Z"})"));
			FStationVoiceCredential Credential;
			TestFalse("parsed", StationJson::ParseVoiceCredential(*Json, Credential));
		});

		It("parses a patient reply", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(
				R"({"outcome":"patient_reply","reply_text":"Dói no peito, doutor.","reply_audio_url":null,"server_now":"2026-10-21T12:01:00Z"})"));
			FStationTurnReply Reply;
			TestTrue("parsed", StationJson::ParseTurnReply(*Json, Reply));
			TestEqual("outcome", Reply.Outcome, EStationTurnOutcome::PatientReply);
			TestEqual("text", Reply.ReplyText, TEXT("Dói no peito, doutor."));
			TestTrue("no audio", Reply.ReplyAudioUrl.IsEmpty());
		});

		It("treats a reply without outcome as a patient reply", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(
				R"({"reply_text":"Sim.","reply_audio_url":"/audio/1.mp3","server_now":"2026-10-21T12:01:00Z"})"));
			FStationTurnReply Reply;
			TestTrue("parsed", StationJson::ParseTurnReply(*Json, Reply));
			TestEqual("outcome", Reply.Outcome, EStationTurnOutcome::PatientReply);
			TestEqual("audio", Reply.ReplyAudioUrl, TEXT("/audio/1.mp3"));
		});

		It("parses an examiner-addressed turn with released impressos", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(R"({
				"outcome": "examiner_acknowledged", "reply_text": null, "reply_audio_url": null,
				"learner_turn": {"role": "learner", "modality": "text", "text": "Examino o tórax.", "at": "2026-10-21T12:01:00Z"},
				"newly_released": [{"id": "exame-fisico", "title": "Exame físico", "category": "exam", "content": "Ausculta normal."}],
				"server_now": "2026-10-21T12:01:00Z"
			})"));
			FStationTurnReply Reply;
			TestTrue("parsed", StationJson::ParseTurnReply(*Json, Reply));
			TestEqual("outcome", Reply.Outcome, EStationTurnOutcome::ExaminerAcknowledged);
			TestTrue("no patient text", Reply.ReplyText.IsEmpty());
			TestEqual("released", Reply.NewlyReleased.Num(), 1);
			if (Reply.NewlyReleased.Num() == 1)
			{
				TestEqual("content", Reply.NewlyReleased[0].Content, TEXT("Ausculta normal."));
			}
		});

		It("parses an impresso decision", [this]()
		{
			const TPair<const TCHAR*, EStationImpressoDecision> Cases[] = {
				{TEXT("released"), EStationImpressoDecision::Released},
				{TEXT("already_released"), EStationImpressoDecision::AlreadyReleased},
				{TEXT("unavailable"), EStationImpressoDecision::Unavailable},
			};
			for (const TPair<const TCHAR*, EStationImpressoDecision>& Case : Cases)
			{
				const TSharedRef<FJsonObject> Json = ParseObject(FString::Printf(TEXT(
					R"({"request_id":"r1","decision":"%s","released_impressos":[{"id":"ecg","title":"ECG","category":"report","content":"Ritmo sinusal."}],"newly_released":[],"feedback_message":"Ok."})"),
					Case.Key));
				FStationImpressoReply Reply;
				TestTrue(FString::Printf(TEXT("parsed %s"), Case.Key), StationJson::ParseImpressoReply(*Json, Reply));
				TestEqual(FString::Printf(TEXT("decision %s"), Case.Key), Reply.Decision, Case.Value);
				TestEqual("request id", Reply.RequestId, TEXT("r1"));
				TestEqual("released", Reply.ReleasedImpressos.Num(), 1);
				TestEqual("feedback", Reply.FeedbackMessage, TEXT("Ok."));
			}
		});

		It("parses the session transcript", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
			TArray<TSharedPtr<FJsonValue>> Messages;
			for (const TPair<const TCHAR*, const TCHAR*>& Line : {TPair<const TCHAR*, const TCHAR*>(TEXT("learner"), TEXT("Olá.")), TPair<const TCHAR*, const TCHAR*>(TEXT("patient"), TEXT("Oi, doutor."))})
			{
				const TSharedRef<FJsonObject> Message = MakeShared<FJsonObject>();
				Message->SetStringField(TEXT("role"), Line.Key);
				Message->SetStringField(TEXT("modality"), TEXT("text"));
				Message->SetStringField(TEXT("text"), Line.Value);
				Messages.Add(MakeShared<FJsonValueObject>(Message));
			}
			Json->SetArrayField(TEXT("messages"), Messages);

			FStationSession Session;
			FDateTime ServerNow;
			TestTrue("parsed", StationJson::ParseSession(*Json, Session, ServerNow));
			TestEqual("lines", Session.Messages.Num(), 2);
			if (Session.Messages.Num() == 2)
			{
				TestEqual("speaker", Session.Messages[1].Speaker, EStationSpeaker::Patient);
				TestEqual("text", Session.Messages[1].Text, TEXT("Oi, doutor."));
			}
		});

		It("skips transcript lines with a speaker it does not know", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(SessionJson);
			TArray<TSharedPtr<FJsonValue>> Messages;
			for (const TCHAR* Role : {TEXT("examiner"), TEXT("patient")})
			{
				const TSharedRef<FJsonObject> Message = MakeShared<FJsonObject>();
				Message->SetStringField(TEXT("role"), Role);
				Message->SetStringField(TEXT("text"), TEXT("Linha."));
				Messages.Add(MakeShared<FJsonValueObject>(Message));
			}
			Json->SetArrayField(TEXT("messages"), Messages);

			FStationSession Session;
			FDateTime ServerNow;
			TestTrue("session still parsed", StationJson::ParseSession(*Json, Session, ServerNow));
			TestEqual("known lines kept", Session.Messages.Num(), 1);
		});

		It("parses an educational result", [this]()
		{
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(R"({
				"schema_version": "2", "session_id": "abc123", "status": "completed", "placeholder": false,
				"criteria": [
					{"id": "c1", "description": "Pergunta sobre a dor", "max_points": "2.0", "evidence_ids": ["m1"],
					 "evidence": [{"id": "m1", "role": "learner", "text": "Onde dói?"}], "recommendation": "Bom.",
					 "status": "assessed", "reason": null, "level": "adequate", "level_description": "Adequado", "points": "2.0"},
					{"id": "c2", "description": "Solicita ECG", "max_points": "1.0", "evidence_ids": [], "evidence": [],
					 "recommendation": "Solicite o ECG.", "status": "not_observable", "reason": "Sem evidência na transcrição."}
				],
				"coverage": {"assessed": 1, "uncertain": 0, "not_observable": 1, "not_applicable": 0},
				"estimates": {"total": null, "scored_subtotal": "2.0", "scored_max": "2.0", "eligible_max": "3.0",
					"unresolved": [{"id": "c2", "status": "not_observable"}]}
			})"));
			FStationResult Result;
			TestTrue("parsed", StationJson::ParseResult(*Json, Result));
			TestEqual("session", Result.SessionId, TEXT("abc123"));
			TestFalse("placeholder", Result.bPlaceholder);
			TestTrue("no total while unresolved", Result.EstimatedTotal.IsEmpty());
			TestEqual("subtotal", Result.ScoredSubtotal, TEXT("2.0"));
			TestEqual("eligible", Result.EligibleMax, TEXT("3.0"));
			TestEqual("criteria", Result.Criteria.Num(), 2);
			if (Result.Criteria.Num() == 2)
			{
				const FStationCriterionResult& Assessed = Result.Criteria[0];
				TestEqual("assessed", Assessed.Status, EStationCriterionStatus::Assessed);
				TestEqual("points", Assessed.Points, TEXT("2.0"));
				TestEqual("level", Assessed.LevelDescription, TEXT("Adequado"));
				TestEqual("evidence", Assessed.Evidence.Num(), 1);
				if (Assessed.Evidence.Num() == 1)
				{
					TestEqual("excerpt", Assessed.Evidence[0].Text, TEXT("Onde dói?"));
				}
				const FStationCriterionResult& Missing = Result.Criteria[1];
				TestEqual("not observable", Missing.Status, EStationCriterionStatus::NotObservable);
				TestEqual("reason", Missing.Reason, TEXT("Sem evidência na transcrição."));
				TestTrue("no points", Missing.Points.IsEmpty());
			}
		});

		It("parses a finish body into the session", [this]()
		{
			FStationSession Session;
			Session.SessionId = TEXT("abc123");
			const TSharedRef<FJsonObject> Json = ParseObject(TEXT(
				R"({"session_id":"abc123","status":"completed","completed_at":"2026-10-21T12:05:00Z","completion_reason":"user","deadline_at":"2026-10-21T12:10:00Z","server_now":"2026-10-21T12:05:00Z"})"));
			TestTrue("parsed", StationJson::ParseFinish(*Json, Session));
			TestEqual("status", Session.Status, EStationSessionStatus::Completed);
			TestEqual("reason", Session.CompletionReason, TEXT("user"));
			TestEqual("completed", Session.CompletedAt, FDateTime(2026, 10, 21, 12, 5, 0));
		});
	});

	Describe("UStationClient without a session", [this]()
	{
		It("reports no remaining time", [this]()
		{
			UStationClient* Client = NewObject<UStationClient>();
			TestNull("session", Client->GetSession());
			TestEqual("remaining", Client->GetRemainingTime(), FTimespan::Zero());
		});

		It("refuses to refresh or discard with no_session", [this]()
		{
			UStationClient* Client = NewObject<UStationClient>();
			FString RefreshCode;
			FString DiscardCode;
			Client->RefreshSession([&RefreshCode](const TStationResult<FStationSession>& Result)
			{
				RefreshCode = Result.HasError() ? Result.GetError().Code : TEXT("ok");
			});
			Client->DiscardSession([&DiscardCode](const TStationResult<FStationNone>& Result)
			{
				DiscardCode = Result.HasError() ? Result.GetError().Code : TEXT("ok");
			});
			TestEqual("refresh", RefreshCode, TEXT("no_session"));
			TestEqual("discard", DiscardCode, TEXT("no_session"));
		});

		It("refuses every session operation with no_session", [this]()
		{
			UStationClient* Client = NewObject<UStationClient>();
			TArray<FString> Codes;
			auto Record = [&Codes](const auto& Result) { Codes.Add(Result.HasError() ? Result.GetError().Code : TEXT("ok")); };
			Client->RequestVoiceCredential(Record);
			Client->SendTurn(TEXT("Olá"), EStationTurnModality::Text, Record);
			Client->RequestImpresso(TEXT("ECG"), FString(), Record);
			Client->ListImpressos(Record);
			Client->FinishSession(EStationFinishReason::User, Record);
			Client->FetchResult(Record);
			TestEqual("calls", Codes.Num(), 6);
			for (const FString& Code : Codes)
			{
				TestEqual("code", Code, TEXT("no_session"));
			}
		});
	});
}

BEGIN_DEFINE_SPEC(FStationClientPhoenixSpec, "ProyectoMed.StationClient.Phoenix",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	UStationClient* Client = nullptr;
END_DEFINE_SPEC(FStationClientPhoenixSpec)

void FStationClientPhoenixSpec::Define()
{
	using namespace StationClientTests;

	const FTimespan Timeout = FTimespan::FromSeconds(20);

	BeforeEach([this]()
	{
		Client = NewObject<UStationClient>();
		Client->AddToRoot();
		Client->SetPhoenixBaseUrl(PhoenixUrl());
	});

	// Leave no session behind in Phoenix, whatever the test did.
	LatentAfterEach(Timeout, [this](const FDoneDelegate& Done)
	{
		if (!Client->GetSession())
		{
			Client->RemoveFromRoot();
			Done.Execute();
			return;
		}
		Client->DiscardSession([this, Done](const TStationResult<FStationNone>&)
		{
			Client->RemoveFromRoot();
			Done.Execute();
		});
	});

	LatentIt("fetches the active station Phoenix serves", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->FetchActiveStation([this, Done](const TStationResult<FStationSummary>& Result)
		{
			if (TestFalse(TEXT("error (is Phoenix running at $STATION_PHOENIX_URL?)"), Result.HasError()))
			{
				const FStationSummary& Summary = Result.GetValue();
				TestFalse("station id", Summary.StationId.IsEmpty());
				TestFalse("title", Summary.DisplayTitle.IsEmpty());
				TestFalse("scenario", Summary.Scenario.IsEmpty());
				TestTrue("tasks", Summary.Tasks.Num() > 0);
			}
			Done.Execute();
		});
	});

	LatentIt("starts an ephemeral session with a ten-minute server-owned timer", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(true, [this, Done](const TStationResult<FStationSession>& Result)
		{
			if (TestFalse("error", Result.HasError()))
			{
				const FStationSession& Session = Result.GetValue();
				TestFalse("session id", Session.SessionId.IsEmpty());
				TestTrue("consent echoed", Session.bAudioConsent);
				TestEqual("status", Session.Status, EStationSessionStatus::Active);
				TestEqual("timer length", Session.DeadlineAt - Session.StartedAt, FTimespan::FromMinutes(10));
				TestEqual("held by the client", Client->GetSession() ? Client->GetSession()->SessionId : FString(), Session.SessionId);

				const FTimespan Remaining = Client->GetRemainingTime();
				TestTrue("timer started", Remaining <= FTimespan::FromMinutes(10) && Remaining > FTimespan::FromMinutes(9.5));
			}
			Done.Execute();
		});
	});

	LatentIt("starts a training when no Station Mode is given, as before #421", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			TestEqual("mode", Started.GetValue().Mode, EStationSessionMode::Training);
			TestFalse("consent", Started.GetValue().bAudioConsent);
			Client->RefreshSession([this, Done](const TStationResult<FStationSession>& Refreshed)
			{
				if (TestFalse("refresh", Refreshed.HasError()))
				{
					TestEqual("mode kept", Refreshed.GetValue().Mode, EStationSessionMode::Training);
				}
				Done.Execute();
			});
		});
	});

	LatentIt("starts a simulated exam that keeps its Station Mode for the whole run", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(true, EStationSessionMode::SimulatedExam, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			TestEqual("mode", Started.GetValue().Mode, EStationSessionMode::SimulatedExam);
			TestEqual("held by the client", Client->GetSession() ? Client->GetSession()->Mode : EStationSessionMode::Training,
				EStationSessionMode::SimulatedExam);
			Client->RefreshSession([this, Done](const TStationResult<FStationSession>& Refreshed)
			{
				if (!TestFalse("refresh", Refreshed.HasError()))
				{
					Done.Execute();
					return;
				}
				TestEqual("mode kept on refresh", Refreshed.GetValue().Mode, EStationSessionMode::SimulatedExam);
				Client->FinishSession(EStationFinishReason::User, [this, Done](const TStationResult<FStationSession>& Finished)
				{
					if (TestFalse("finish", Finished.HasError()))
					{
						TestEqual("mode kept on finish", Finished.GetValue().Mode, EStationSessionMode::SimulatedExam);
					}
					Done.Execute();
				});
			});
		});
	});

	LatentIt("is refused a simulated exam without audio consent", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, EStationSessionMode::SimulatedExam, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (TestTrue("refused", Started.HasError()))
			{
				TestEqual("status", Started.GetError().HttpStatus, 400);
				TestEqual("code", Started.GetError().Code, TEXT("audio_consent_required"));
				TestFalse("message for the learner", Started.GetError().Message.IsEmpty());
			}
			TestNull("no session held", Client->GetSession());
			Done.Execute();
		});
	});

	LatentIt("refuses a second run while one is in progress", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& First)
		{
			if (!TestFalse("first start", First.HasError()))
			{
				Done.Execute();
				return;
			}
			const FString FirstId = First.GetValue().SessionId;
			Client->StartSession(false, [this, Done, FirstId](const TStationResult<FStationSession>& Second)
			{
				TestTrue("second start fails", Second.HasError());
				if (Second.HasError())
				{
					TestEqual("code", Second.GetError().Code, TEXT("session_in_progress"));
				}
				TestEqual("first run kept", Client->GetSession() ? Client->GetSession()->SessionId : FString(), FirstId);
				Done.Execute();
			});
		});
	});

	LatentIt("refuses a second start while the first is still in flight", Timeout, [this](const FDoneDelegate& Done)
	{
		TSharedRef<FString> SecondCode = MakeShared<FString>();
		Client->StartSession(false, [this, Done, SecondCode](const TStationResult<FStationSession>& First)
		{
			TestFalse("first start", First.HasError());
			TestEqual("second start", *SecondCode, TEXT("session_in_progress"));
			Done.Execute();
		});
		Client->StartSession(false, [SecondCode](const TStationResult<FStationSession>& Second)
		{
			*SecondCode = Second.HasError() ? Second.GetError().Code : TEXT("ok");
		});
	});

	LatentIt("refreshes the current session from Phoenix", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			const FStationSession StartedSession = Started.GetValue();
			Client->RefreshSession([this, Done, StartedSession](const TStationResult<FStationSession>& Refreshed)
			{
				if (TestFalse("refresh", Refreshed.HasError()))
				{
					TestEqual("same id", Refreshed.GetValue().SessionId, StartedSession.SessionId);
					TestEqual("same deadline", Refreshed.GetValue().DeadlineAt, StartedSession.DeadlineAt);
					TestFalse("consent echoed", Refreshed.GetValue().bAudioConsent);
				}
				Done.Execute();
			});
		});
	});

	LatentIt("discards the run in Phoenix before clearing it locally", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			const FString SessionId = Started.GetValue().SessionId;
			Client->DiscardSession([this, Done, SessionId](const TStationResult<FStationNone>& Discarded)
			{
				TestFalse("discard", Discarded.HasError());
				TestNull("cleared locally", Client->GetSession());

				const FString Url = Client->GetPhoenixBaseUrl() + TEXT("/api/stations/active/sessions/") + SessionId;
				StationHttp::Send(TEXT("GET"), Url, nullptr, [this, Done](const FStationHttpResponse& Response)
				{
					TestEqual("Phoenix forgot it", Response.Status, 404);
					Done.Execute();
				});
			});
		});
	});

	LatentIt("receives a LiveKit credential scoped to the run's room", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(true, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			const FString SessionId = Started.GetValue().SessionId;
			Client->RequestVoiceCredential([this, Done, SessionId](const TStationResult<FStationVoiceCredential>& Result)
			{
				if (TestFalse(TEXT("error (does Phoenix have LIVEKIT_* set?)"), Result.HasError()))
				{
					const FStationVoiceCredential& Credential = Result.GetValue();
					TestFalse("url", Credential.Url.IsEmpty());
					TestFalse("token", Credential.Token.IsEmpty());
					TestEqual("room", Credential.Room, TEXT("station-session-") + SessionId);
					TestEqual("identity", Credential.Identity, TEXT("learner-") + SessionId);
					const FTimespan Lifetime = Credential.ExpiresAt - FDateTime::UtcNow();
					TestTrue("short-lived", Lifetime > FTimespan::Zero() && Lifetime <= FTimespan::FromMinutes(5));
				}
				Done.Execute();
			});
		});
	});

	LatentIt("gets no LiveKit credential without audio consent", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			Client->RequestVoiceCredential([this, Done](const TStationResult<FStationVoiceCredential>& Result)
			{
				if (TestTrue("refused", Result.HasError()))
				{
					TestEqual("status", Result.GetError().HttpStatus, 403);
					TestEqual("code", Result.GetError().Code, TEXT("no_consent"));
				}
				Done.Execute();
			});
		});
	});

	LatentIt("requests and lists an impresso outside the patient dialogue", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			Client->RequestImpresso(TEXT("Gostaria de ver o eletrocardiograma"), FString(),
				[this, Done](const TStationResult<FStationImpressoReply>& Requested)
				{
					if (!TestFalse("request", Requested.HasError()))
					{
						Done.Execute();
						return;
					}
					TestFalse("request id generated", Requested.GetValue().RequestId.IsEmpty());
					TestFalse("feedback", Requested.GetValue().FeedbackMessage.IsEmpty());
					const int32 Released = Requested.GetValue().ReleasedImpressos.Num();
					Client->ListImpressos([this, Done, Released](const TStationResult<TArray<FStationImpresso>>& Listed)
					{
						if (TestFalse("list", Listed.HasError()))
						{
							TestEqual("same released set", Listed.GetValue().Num(), Released);
						}
						Done.Execute();
					});
				});
		});
	});

	LatentIt("finishes the run for good and refuses later turns", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			Client->FinishSession(EStationFinishReason::User, [this, Done](const TStationResult<FStationSession>& Finished)
			{
				if (TestFalse("finish", Finished.HasError()))
				{
					TestEqual("status", Finished.GetValue().Status, EStationSessionStatus::Completed);
					TestEqual("reason", Finished.GetValue().CompletionReason, TEXT("user"));
					TestEqual("held as completed", Client->GetSession() ? Client->GetSession()->Status : EStationSessionStatus::Active,
						EStationSessionStatus::Completed);
					TestEqual("timer stopped", Client->GetRemainingTime(), FTimespan::Zero());
				}
				Client->SendTurn(TEXT("Mais uma pergunta"), EStationTurnModality::Text,
					[this, Done](const TStationResult<FStationTurnReply>& Turn)
					{
						if (TestTrue("refused", Turn.HasError()))
						{
							TestEqual("code", Turn.GetError().Code, TEXT("session_completed"));
						}
						Done.Execute();
					});
			});
		});
	});

	LatentIt("is told the deadline is not reached when the timer finishes early", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			Client->FinishSession(EStationFinishReason::Timer, [this, Done](const TStationResult<FStationSession>& Finished)
			{
				if (TestTrue("refused", Finished.HasError()))
				{
					TestEqual("status", Finished.GetError().HttpStatus, 409);
					TestEqual("code", Finished.GetError().Code, TEXT("deadline_not_reached"));
				}
				TestEqual("still active", Client->GetSession() ? Client->GetSession()->Status : EStationSessionStatus::Completed,
					EStationSessionStatus::Active);
				Done.Execute();
			});
		});
	});

	LatentIt("gets no result before the run is finished", Timeout, [this](const FDoneDelegate& Done)
	{
		Client->StartSession(false, [this, Done](const TStationResult<FStationSession>& Started)
		{
			if (!TestFalse("start", Started.HasError()))
			{
				Done.Execute();
				return;
			}
			Client->FetchResult([this, Done](const TStationResult<FStationResult>& Result)
			{
				if (TestTrue("refused", Result.HasError()))
				{
					TestEqual("status", Result.GetError().HttpStatus, 422);
					TestEqual("code", Result.GetError().Code, TEXT("session_not_finished"));
				}
				Done.Execute();
			});
		});
	});

	LatentIt("maps a Phoenix error body to the error code", Timeout, [this](const FDoneDelegate& Done)
	{
		const FString Url = Client->GetPhoenixBaseUrl() + TEXT("/api/stations/active/sessions/no-such-session");
		StationHttp::Send(TEXT("GET"), Url, nullptr, [this, Done](const FStationHttpResponse& Response)
		{
			if (TestTrue("error", Response.Error.IsSet()))
			{
				TestEqual("status", Response.Error->HttpStatus, 404);
				TestEqual("code", Response.Error->Code, TEXT("session_not_found"));
				TestFalse("message", Response.Error->Message.IsEmpty());
			}
			Done.Execute();
		});
	});

	LatentIt("reports network_error when Phoenix is unreachable", Timeout, [this](const FDoneDelegate& Done)
	{
		// Port 9 (discard) is closed on a development machine.
		Client->SetPhoenixBaseUrl(TEXT("http://127.0.0.1:9"));
		Client->FetchActiveStation([this, Done](const TStationResult<FStationSummary>& Result)
		{
			if (TestTrue("error", Result.HasError()))
			{
				TestEqual("status", Result.GetError().HttpStatus, 0);
				TestEqual("code", Result.GetError().Code, TEXT("network_error"));
			}
			Done.Execute();
		});
	});
}

#endif // WITH_DEV_AUTOMATION_TESTS
