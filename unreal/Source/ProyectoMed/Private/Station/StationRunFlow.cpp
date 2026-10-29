#include "Station/StationRunFlow.h"

#include "HAL/PlatformTime.h"
#include "Misc/ConfigCacheIni.h"
#include "StationClient.h"

#define LOCTEXT_NAMESPACE "StationRunFlow"

DEFINE_LOG_CATEGORY_STATIC(LogStationRun, Log, All);

bool IsVoiceTrainingAvailable(const FStationSummary& Station)
{
	return Station.VoiceMode == EStationVoiceMode::Realtime;
}

FText SimulatedExamUnavailableText(const FStationSummary& Station, EStationMicPermission Permission)
{
	if (!IsVoiceTrainingAvailable(Station))
	{
		return LOCTEXT("SimulatedExamNoVoice",
			"A prova simulada é feita só por voz, que não está disponível agora. Você ainda pode fazer um treino.");
	}
	if (Permission == EStationMicPermission::Denied)
	{
		return LOCTEXT("SimulatedExamMicrophoneBlocked",
			"A prova simulada é feita só por voz e o microfone está bloqueado. Libere o acesso nos ajustes de privacidade do sistema e abra o app de novo. Você ainda pode fazer um treino.");
	}
	return FText::GetEmpty();
}

namespace
{
	/** Phoenix ended the run itself, at its deadline: the run is over for this client too. */
	bool IsRunOver(const FStationClientError& Error)
	{
		return Error.Code == TEXT("station_time_elapsed") || Error.Code == TEXT("session_completed");
	}

	/**
	 * Phoenix gave no answer: it is unreachable or did not answer in time, or a
	 * gateway answered for it without a Phoenix error code.
	 */
	bool IsUnanswered(const FStationClientError& Error)
	{
		return Error.Code == TEXT("network_error") || Error.Code == TEXT("http_502")
			|| Error.Code == TEXT("http_503") || Error.Code == TEXT("http_504");
	}
}

FText FormatStationTimer(const FTimespan& Remaining)
{
	const int64 Seconds = FMath::Max<int64>(0, FMath::CeilToInt64(Remaining.GetTotalSeconds()));
	return FText::FromString(FString::Printf(TEXT("%02lld:%02lld"), Seconds / 60, Seconds % 60));
}

namespace
{
	const TCHAR* VoiceSettingsSection = TEXT("StationVoice");

	/**
	 * How long a released exam button still listens: the first caption of a request
	 * spoken right before the release arrives within it.
	 */
	constexpr double SpokenExamReleaseGraceSeconds = 2.0;
	const TCHAR* DisclosureShownKey = TEXT("bMicrophoneDisclosureShown");
}

FStationMicrophoneSetup FStationMicrophoneSetup::System()
{
	FStationMicrophoneSetup Setup;
	Setup.GetPermission = []() { return StationMicPermission::Get(); };
	Setup.RequestPermission = [](TFunction<void(EStationMicPermission)> OnDone) { StationMicPermission::Request(MoveTemp(OnDone)); };
	Setup.WasDisclosureShown = []()
	{
		bool bShown = false;
		GConfig->GetBool(VoiceSettingsSection, DisclosureShownKey, bShown, GGameUserSettingsIni);
		return bShown;
	};
	Setup.RememberDisclosureShown = []()
	{
		GConfig->SetBool(VoiceSettingsSection, DisclosureShownKey, true, GGameUserSettingsIni);
		GConfig->Flush(false, GGameUserSettingsIni);
	};
	return Setup;
}

void UStationRunFlow::Begin(UStationClient* InClient, FStationMicrophoneSetup InMicrophone)
{
	Client = InClient;
	Microphone = MoveTemp(InMicrophone);
	Step = Microphone.WasDisclosureShown() ? EStationRunStep::Notice : EStationRunStep::Microphone;
	LoadStation();
}

void UStationRunFlow::AnswerMicrophone(bool bAllow)
{
	if (Step != EStationRunStep::Microphone)
	{
		return;
	}
	Microphone.RememberDisclosureShown();
	if (!bAllow)
	{
		Step = EStationRunStep::Notice;
		OnChanged.Broadcast();
		return;
	}
	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	Microphone.RequestPermission([WeakThis](EStationMicPermission)
	{
		if (UStationRunFlow* Self = WeakThis.Get(); Self && Self->Step == EStationRunStep::Microphone)
		{
			Self->Step = EStationRunStep::Notice;
			Self->OnChanged.Broadcast();
		}
	});
}

EStationMicPermission UStationRunFlow::GetMicrophonePermission() const
{
	return Microphone.GetPermission ? Microphone.GetPermission() : EStationMicPermission::Denied;
}

void UStationRunFlow::AcknowledgeNotice()
{
	if (Step != EStationRunStep::Notice)
	{
		return;
	}
	Step = EStationRunStep::Brief;
	OnChanged.Broadcast();
}

void UStationRunFlow::RetryLoadStation()
{
	if (!bLoadingStation && (Step == EStationRunStep::Notice || Step == EStationRunStep::Brief))
	{
		LoadStation();
	}
}

bool UStationRunFlow::CanEnter(EStationTrainingMode InMode) const
{
	return Step == EStationRunStep::Brief
		&& Station.IsSet()
		&& (InMode == EStationTrainingMode::Text
			|| (IsVoiceTrainingAvailable(Station.GetValue()) && GetMicrophonePermission() != EStationMicPermission::Denied));
}

void UStationRunFlow::Enter(EStationTrainingMode InMode)
{
	if (CanEnter(InMode))
	{
		BeginEntry(InMode, EStationSessionMode::Training);
	}
}

bool UStationRunFlow::CanEnterSimulatedExam() const
{
	return Step == EStationRunStep::Brief
		&& Station.IsSet()
		&& SimulatedExamUnavailableText(Station.GetValue(), GetMicrophonePermission()).IsEmpty();
}

void UStationRunFlow::EnterSimulatedExam()
{
	if (CanEnterSimulatedExam())
	{
		BeginEntry(EStationTrainingMode::Voice, EStationSessionMode::SimulatedExam);
	}
}

void UStationRunFlow::BeginEntry(EStationTrainingMode InMode, EStationSessionMode InSessionMode)
{
	ResetRun();
	Mode = InMode;
	SessionMode = InSessionMode;
	Step = EStationRunStep::Starting;
	OnChanged.Broadcast();

	if (InMode == EStationTrainingMode::Voice && GetMicrophonePermission() == EStationMicPermission::NotDetermined)
	{
		// The learner skipped the first-launch request; choosing voice is the moment to ask.
		TWeakObjectPtr<UStationRunFlow> WeakThis(this);
		Microphone.RequestPermission([WeakThis](EStationMicPermission Permission)
		{
			UStationRunFlow* Self = WeakThis.Get();
			if (!Self || Self->Step != EStationRunStep::Starting)
			{
				return;
			}
			if (Permission != EStationMicPermission::Granted)
			{
				Self->Step = EStationRunStep::Brief;
				Self->ErrorText = Self->SessionMode == EStationSessionMode::SimulatedExam
					? LOCTEXT("SimulatedExamMicrophoneRefused",
						"Sem acesso ao microfone, a prova simulada não pode começar. Você ainda pode fazer um treino.")
					: LOCTEXT("MicrophoneBlocked", "Sem acesso ao microfone, o treino por voz não pode começar.");
				Self->OnChanged.Broadcast();
				return;
			}
			Self->StartSession();
		});
		return;
	}
	StartSession();
}

void UStationRunFlow::StartSession()
{
	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	const uint32 ThisRun = Run;
	Client->StartSession(Mode == EStationTrainingMode::Voice, SessionMode, [WeakThis, ThisRun](const TStationResult<FStationSession>& Started)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self || Self->Run != ThisRun)
		{
			return;
		}
		if (Started.HasError())
		{
			Self->Step = EStationRunStep::Brief;
			Self->SetError(Started.GetError(),
				LOCTEXT("StartFailed", "Não foi possível iniciar a estação. Tente novamente."));
			return;
		}

		if (Self->Mode == EStationTrainingMode::Text)
		{
			Self->Step = EStationRunStep::Running;
			Self->OnChanged.Broadcast();
			return;
		}

		// The run has started either way; without a credential it continues as text.
		Self->Client->RequestVoiceCredential([WeakThis, ThisRun](const TStationResult<FStationVoiceCredential>& Credential)
		{
			UStationRunFlow* Flow = WeakThis.Get();
			if (!Flow || Flow->Run != ThisRun)
			{
				return;
			}
			if (Credential.HasError())
			{
				UE_LOG(LogStationRun, Warning, TEXT("No voice credential (%d %s); the run continues as text."),
					Credential.GetError().HttpStatus, *Credential.GetError().Code);
				Flow->bVoiceFallback = true;
			}
			else
			{
				Flow->VoiceCredential = Credential.GetValue();
				UE_LOG(LogStationRun, Log, TEXT("Voice credential received for room %s, valid until %s."),
					*Credential.GetValue().Room, *Credential.GetValue().ExpiresAt.ToIso8601());
			}
			Flow->Step = EStationRunStep::Running;
			if (Flow->VoiceCredential.IsSet())
			{
				Flow->ConnectVoice();
			}
			Flow->OnChanged.Broadcast();
			if (Credential.HasError() && IsUnanswered(Credential.GetError()))
			{
				Flow->CheckPhoenix();
			}
		});
	});
}

bool UStationRunFlow::CanSendTurn() const
{
	return Step == EStationRunStep::Running && !PendingTurn.IsSet() && !bReloadingTranscript;
}

FString UStationRunFlow::TakeUnsentTurn()
{
	if (bReloadingTranscript)
	{
		return FString();
	}
	FString Turn = MoveTemp(UnsentTurn);
	UnsentTurn.Reset();
	return Turn;
}

bool UStationRunFlow::SendTypedTurn(const FString& Text)
{
	const FString Turn = Text.TrimStartAndEnd();
	if (Turn.IsEmpty() || !CanSendTurn())
	{
		return false;
	}

	PendingTurn = Turn;
	UnsentTurn.Reset();
	ErrorText = FText::GetEmpty();
	OnChanged.Broadcast();

	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	const uint32 ThisRun = Run;
	const int32 SentAfterVoiceTurn = VoiceTurnId;
	Client->SendTurn(Turn, EStationTurnModality::Text, [WeakThis, ThisRun, Turn, SentAfterVoiceTurn](const TStationResult<FStationTurnReply>& Reply)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self || Self->Run != ThisRun)
		{
			return;
		}
		Self->PendingTurn.Reset();
		if (Reply.HasError())
		{
			Self->UnsentTurn = Turn;
			// Phoenix may have taken the turn without this client hearing back. Reading
			// its record also checks that Phoenix is still there.
			if (IsUnanswered(Reply.GetError()))
			{
				Self->ReloadTranscript(Turn);
			}
			Self->SetError(Reply.GetError(),
				LOCTEXT("TurnFailed", "Não foi possível enviar sua mensagem. Tente novamente."));
			if (IsRunOver(Reply.GetError()))
			{
				Self->ExpireTimer();
			}
		}
		else
		{
			Self->AddLine(EStationSpeaker::Learner, Turn);
			const FStationTurnReply& Value = Reply.GetValue();
			// An examiner-addressed turn is kept with no patient reply.
			if (Value.Outcome == EStationTurnOutcome::PatientReply && !Value.ReplyText.IsEmpty())
			{
				Self->AddLine(EStationSpeaker::Patient, Value.ReplyText);
				// The voice worker speaks this reply too (#325): it is the newer reply that
				// lets the patient's voice through again (#193), unless the learner has
				// spoken since, and then the worker does not speak it.
				if (Self->VoiceTurnId == SentAfterVoiceTurn)
				{
					Self->ResumePatient();
				}
			}
			Self->OnChanged.Broadcast();
		}
		// A finish waits for this answer, so Phoenix grades the turn.
		Self->ContinueFinish();
	});
	return true;
}

bool UStationRunFlow::CanRequestExam() const
{
	return Step == EStationRunStep::Running && !PendingExamRequest.IsSet();
}

bool UStationRunFlow::ShouldRequestExamsAloud() const
{
	return Mode == EStationTrainingMode::Voice && !bVoiceFallback && !Voice.bLost && !Voice.bMicrophoneUnavailable;
}

bool UStationRunFlow::CanAskExamAloud() const
{
	return Step == EStationRunStep::Running && ShouldRequestExamsAloud() && !bArmingSpokenExam
		&& !(IsListeningForExam() && !bSpokenExamReleased) && !IsSpokenExamInFlight();
}

bool UStationRunFlow::AskExamAloud()
{
	if (!CanAskExamAloud())
	{
		return false;
	}

	bArmingSpokenExam = true;
	bReleasedWhileArming = false;
	bSpokenExamReleased = false;
	ExamErrorText = FText::GetEmpty();
	OnChanged.Broadcast();

	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	const uint32 ThisRun = Run;
	Client->ArmExamMode([WeakThis, ThisRun](const TStationResult<FStationExamMode>& Armed)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self || Self->Run != ThisRun)
		{
			return;
		}
		Self->bArmingSpokenExam = false;
		if (Armed.HasError())
		{
			Self->SetExamError(Armed.GetError());
			if (IsUnanswered(Armed.GetError()))
			{
				Self->CheckPhoenix();
			}
			if (IsRunOver(Armed.GetError()))
			{
				Self->ExpireTimer();
			}
			return;
		}
		if (Self->Step != EStationRunStep::Running)
		{
			Self->DisarmSpokenExam();
			return;
		}
		// Phoenix's clock sets the expiry; this clock counts it down from now.
		const FTimespan Left = Armed.GetValue().ExpiresAt - Armed.GetValue().ServerNow;
		Self->SpokenExamExpiresAt = FPlatformTime::Seconds() + Left.GetTotalSeconds();
		if (Self->bReleasedWhileArming)
		{
			// The learner may already have spoken while Phoenix armed it.
			Self->bReleasedWhileArming = false;
			Self->bSpokenExamReleased = true;
			Self->SpokenExamExpiresAt = FMath::Min(Self->SpokenExamExpiresAt,
				Self->SpokenExamReleasedAt + SpokenExamReleaseGraceSeconds);
		}
		Self->OnChanged.Broadcast();
	});
	return true;
}

bool UStationRunFlow::IsListeningForExam() const
{
	return SpokenExamTurn == 0 && SpokenExamExpiresAt > 0.0 && FPlatformTime::Seconds() < SpokenExamExpiresAt;
}

void UStationRunFlow::ReleaseExamAloud()
{
	if (bArmingSpokenExam)
	{
		bReleasedWhileArming = true;
		SpokenExamReleasedAt = FPlatformTime::Seconds();
		return;
	}
	if (!IsListeningForExam() || bSpokenExamReleased)
	{
		return; // nothing armed, or the learner already spoke into it
	}
	bSpokenExamReleased = true;
	SpokenExamExpiresAt = FMath::Min(SpokenExamExpiresAt, FPlatformTime::Seconds() + SpokenExamReleaseGraceSeconds);
	OnChanged.Broadcast();
}

void UStationRunFlow::DisarmSpokenExam()
{
	if (!Client)
	{
		return;
	}
	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	const uint32 ThisRun = Run;
	Client->CancelExamMode([WeakThis, ThisRun](const TStationResult<FStationNone>& Cancelled)
	{
		// The mode also ends at its expiry: a failure here needs only the Phoenix check.
		UStationRunFlow* Self = WeakThis.Get();
		if (Self && Self->Run == ThisRun && Cancelled.HasError() && IsUnanswered(Cancelled.GetError()))
		{
			Self->CheckPhoenix();
		}
	});
}

FString UStationRunFlow::TakeUnsentExamRequest()
{
	FString Request = MoveTemp(UnsentExamRequest);
	UnsentExamRequest.Reset();
	return Request;
}

bool UStationRunFlow::RequestExam(const FString& Text)
{
	const FString Request = Text.TrimStartAndEnd();
	if (Request.IsEmpty() || !CanRequestExam())
	{
		return false;
	}

	// Phoenix may have recorded an unanswered request: asking again with its id
	// lets Phoenix answer it instead of recording a second one.
	FPendingExamRequest Attempt;
	Attempt.Text = Request;
	Attempt.RequestId = UnansweredExamRequest.IsSet() && UnansweredExamRequest->Text == Request
		? UnansweredExamRequest->RequestId
		: FGuid::NewGuid().ToString(EGuidFormats::DigitsWithHyphensLower);
	PendingExamRequest = Attempt;
	UnansweredExamRequest.Reset();
	UnsentExamRequest.Reset();
	ExamErrorText = FText::GetEmpty();
	OnChanged.Broadcast();

	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	const uint32 ThisRun = Run;
	Client->RequestImpresso(Attempt.Text, Attempt.RequestId, [WeakThis, ThisRun, Attempt](const TStationResult<FStationImpressoReply>& Reply)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self || Self->Run != ThisRun)
		{
			return;
		}
		Self->PendingExamRequest.Reset();
		if (Reply.HasError())
		{
			Self->UnsentExamRequest = Attempt.Text;
			const bool bUnanswered = IsUnanswered(Reply.GetError());
			if (bUnanswered)
			{
				Self->UnansweredExamRequest = Attempt;
			}
			Self->SetExamError(Reply.GetError());
			if (bUnanswered)
			{
				Self->CheckPhoenix();
			}
			if (IsRunOver(Reply.GetError()))
			{
				Self->ExpireTimer();
			}
		}
		else
		{
			FStationExamRequest& Answered = Self->ExamRequests.AddDefaulted_GetRef();
			Answered.Text = Attempt.Text;
			Answered.Reply = Reply.GetValue();
			Self->ReleasedImpressos = Reply.GetValue().ReleasedImpressos;
			Self->OnChanged.Broadcast();
		}
		Self->ContinueFinish();
	});
	return true;
}

void UStationRunFlow::AddLine(EStationSpeaker Speaker, const FString& Text)
{
	FStationMessage& Line = Transcript.AddDefaulted_GetRef();
	Line.Speaker = Speaker;
	Line.Text = Text;
	// The examiner's note belongs right after its own spoken turn; any later line ends it.
	Voice.bExaminerNoted = false;
}

void UStationRunFlow::ReloadTranscript(const FString& Turn)
{
	// No new turn until the record is read, so a late answer cannot replace it.
	bReloadingTranscript = true;

	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	const uint32 ThisRun = Run;
	Client->RefreshSession([WeakThis, ThisRun, Turn](const TStationResult<FStationSession>& Refreshed)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self || Self->Run != ThisRun)
		{
			return;
		}
		Self->bReloadingTranscript = false;
		if (Refreshed.HasError() && IsUnanswered(Refreshed.GetError()))
		{
			// Neither the turn nor the record reached this client: Phoenix is lost.
			Self->Invalidate();
			return;
		}
		if (!Refreshed.HasError())
		{
			Self->Transcript = Refreshed.GetValue().Messages;
			Self->VoiceLearnerLine = INDEX_NONE; // its index belongs to the replaced lines
			const int32 LastLearner = Self->Transcript.FindLastByPredicate(
				[](const FStationMessage& Line) { return Line.Speaker == EStationSpeaker::Learner; });
			if (LastLearner != INDEX_NONE && Self->Transcript[LastLearner].Text == Turn)
			{
				// Phoenix took it: giving it back would send it twice.
				Self->UnsentTurn.Reset();
				Self->ErrorText = FText::GetEmpty();
			}
		}
		Self->OnChanged.Broadcast();
		Self->ContinueFinish();
	});
}

bool UStationRunFlow::CanFinish() const
{
	return Step == EStationRunStep::Running;
}

void UStationRunFlow::Finish()
{
	if (CanFinish())
	{
		BeginFinish(EStationFinishReason::User);
	}
}

void UStationRunFlow::ExpireTimer()
{
	if (CanFinish())
	{
		BeginFinish(EStationFinishReason::Timer);
	}
}

void UStationRunFlow::CheckStationTimer()
{
	if (SpokenExamTurn == 0 && SpokenExamExpiresAt > 0.0 && FPlatformTime::Seconds() >= SpokenExamExpiresAt)
	{
		// Nothing was heard: after a release Phoenix is told; at its own expiry it disarmed it already.
		if (bSpokenExamReleased)
		{
			DisarmSpokenExam();
		}
		ResetSpokenExam();
		OnChanged.Broadcast();
	}
	if (CanFinish() && FPlatformTime::Seconds() >= TimerRetryNotBefore
		&& Client->GetRemainingTime() <= FTimespan::Zero())
	{
		ExpireTimer();
	}
}

void UStationRunFlow::BeginFinish(EStationFinishReason Reason)
{
	// Leaving `Running` stops every new turn and exam request at once.
	FinishReason = Reason;
	Step = EStationRunStep::Finishing;
	// Whatever the patient was saying stops with the run (#193).
	SilencePatient();
	OnChanged.Broadcast();
	ContinueFinish();
}

void UStationRunFlow::ContinueFinish()
{
	if (Step != EStationRunStep::Finishing || bFinishInFlight
		|| PendingTurn.IsSet() || bReloadingTranscript || PendingExamRequest.IsSet())
	{
		return;
	}

	bFinishInFlight = true;
	ErrorText = FText::GetEmpty();

	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	const uint32 ThisRun = Run;
	Client->FinishSession(FinishReason, [WeakThis, ThisRun](const TStationResult<FStationSession>& Finished)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self || Self->Run != ThisRun)
		{
			return;
		}
		Self->bFinishInFlight = false;
		if (Finished.HasError())
		{
			if (Self->FinishReason == EStationFinishReason::Timer && Finished.GetError().Code == TEXT("deadline_not_reached"))
			{
				// This clock ran ahead of Phoenix's: read the deadline again and
				// keep the run going until the timer reads zero once more.
				UE_LOG(LogStationRun, Log, TEXT("Phoenix's deadline is not reached yet; the run goes on."));
				Self->Step = EStationRunStep::Running;
				// The finish silenced the patient; the run goes on, so it may speak again.
				Self->ResumePatient();
				Self->TimerRetryNotBefore = FPlatformTime::Seconds() + 1.0;
				Self->Client->RefreshSession([WeakThis](const TStationResult<FStationSession>&)
				{
					if (UStationRunFlow* Flow = WeakThis.Get())
					{
						Flow->OnChanged.Broadcast();
					}
				});
				Self->OnChanged.Broadcast();
				return;
			}
			Self->FailResultUnlessLost(Finished.GetError());
			return;
		}
		Self->LoadResult();
	});
}

void UStationRunFlow::LoadResult()
{
	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	const uint32 ThisRun = Run;
	Client->FetchResult([WeakThis, ThisRun](const TStationResult<FStationResult>& Loaded)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self || Self->Run != ThisRun)
		{
			return;
		}
		if (Loaded.HasError())
		{
			Self->FailResultUnlessLost(Loaded.GetError());
			return;
		}
		Self->Step = EStationRunStep::Feedback;
		Self->Result = Loaded.GetValue();
		Self->OnChanged.Broadcast();
	});
}

void UStationRunFlow::FailResult(const FStationClientError& Error)
{
	Step = EStationRunStep::Feedback;
	SetError(Error, LOCTEXT("ResultUnavailable", "Não foi possível carregar o resultado da estação."));
}

void UStationRunFlow::FailResultUnlessLost(const FStationClientError& Error)
{
	if (!IsUnanswered(Error))
	{
		FailResult(Error);
		return;
	}
	CheckPhoenix([this, Error]() { FailResult(Error); });
}

bool UStationRunFlow::CanRestart() const
{
	return Step == EStationRunStep::Invalidated;
}

void UStationRunFlow::Restart()
{
	if (!CanRestart())
	{
		return;
	}
	// Phoenix may be back: let it forget the run, without waiting for it.
	Client->DiscardSession([](const TStationResult<FStationNone>&) {});
	Client->ForgetSession();
	Step = EStationRunStep::Brief;
	OnChanged.Broadcast();
}

void UStationRunFlow::CheckPhoenix(TFunction<void()> OnAnswered)
{
	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	const uint32 ThisRun = Run;
	Client->RefreshSession([WeakThis, ThisRun, OnAnswered = MoveTemp(OnAnswered)](const TStationResult<FStationSession>& Checked)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self || Self->Run != ThisRun)
		{
			return;
		}
		if (Checked.HasError() && IsUnanswered(Checked.GetError()))
		{
			// Once the feedback is in, Phoenix answered the finish and the result.
			if (Self->Step == EStationRunStep::Running || Self->Step == EStationRunStep::Finishing)
			{
				Self->Invalidate();
			}
			return;
		}
		if (OnAnswered)
		{
			OnAnswered();
		}
	});
}

void UStationRunFlow::Invalidate()
{
	UE_LOG(LogStationRun, Warning, TEXT("Phoenix does not answer; the run is invalidated."));
	// No handler of the room runs after this, and nothing it still delivers plays.
	Client->DisconnectVoice();
	SilencePatient();
	ResetRun();
	Step = EStationRunStep::Invalidated;
	OnChanged.Broadcast();
}

bool UStationRunFlow::CanDiscard() const
{
	return Step == EStationRunStep::Feedback && !bDiscarding;
}

void UStationRunFlow::Discard()
{
	if (!CanDiscard())
	{
		return;
	}

	bDiscarding = true;
	ErrorText = FText::GetEmpty();
	OnChanged.Broadcast();

	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	Client->DiscardSession([WeakThis](const TStationResult<FStationNone>& Discarded)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self)
		{
			return;
		}
		Self->bDiscarding = false;
		// Without a session there is nothing left for Phoenix to forget.
		if (Discarded.HasError() && Discarded.GetError().Code != TEXT("no_session"))
		{
			Self->SetError(Discarded.GetError(),
				LOCTEXT("DiscardFailed", "Não foi possível encerrar a sessão no servidor. Tente novamente."));
			return;
		}
		Self->ResetRun();
		Self->Step = EStationRunStep::Brief;
		Self->OnChanged.Broadcast();
	});
}

void UStationRunFlow::ResetRun()
{
	// Phoenix's answers for the last run arrive here no more.
	++Run;
	bFinishInFlight = false;
	ErrorText = FText::GetEmpty();
	bVoiceFallback = false;
	VoiceCredential.Reset();
	Voice = FStationVoiceView();
	VoiceTurnId = 0;
	bVoiceLearnerCommitted = false;
	VoiceLearnerLine = INDEX_NONE;
	bVoiceOutcome = false;
	PendingTurn.Reset();
	Transcript.Reset();
	UnsentTurn.Reset();
	bReloadingTranscript = false;
	PendingExamRequest.Reset();
	UnansweredExamRequest.Reset();
	ExamRequests.Reset();
	ReleasedImpressos.Reset();
	UnsentExamRequest.Reset();
	ExamErrorText = FText::GetEmpty();
	bArmingSpokenExam = false;
	bReleasedWhileArming = false;
	ResetSpokenExam();
	FinishReason = EStationFinishReason::User;
	Result.Reset();
	TimerRetryNotBefore = 0.0;
}

void UStationRunFlow::LoadStation()
{
	bLoadingStation = true;
	ErrorText = FText::GetEmpty();
	OnChanged.Broadcast();

	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	Client->FetchActiveStation([WeakThis](const TStationResult<FStationSummary>& Result)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self)
		{
			return;
		}
		Self->bLoadingStation = false;
		if (Result.HasError())
		{
			Self->SetError(Result.GetError(),
				LOCTEXT("StationUnavailable", "Não foi possível carregar o cenário e as tarefas da estação."));
			return;
		}
		Self->Station = Result.GetValue();
		Self->OnChanged.Broadcast();
	});
}

void UStationRunFlow::ConnectVoice()
{
	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	FStationVoiceHandlers Handlers;
	Handlers.OnEvent = [WeakThis](const FStationVoiceEvent& Event)
	{
		if (UStationRunFlow* Self = WeakThis.Get())
		{
			Self->HandleVoiceEvent(Event);
		}
	};
	Handlers.OnStateChanged = [WeakThis](EStationVoiceState State)
	{
		if (UStationRunFlow* Self = WeakThis.Get())
		{
			Self->HandleVoiceState(State);
		}
	};
	// Runs on a LiveKit thread: copy the handler so the flow is never touched there.
	Handlers.OnPatientPcm = [PatientAudio = Patient.Audio](TConstArrayView<int16> Samples, int32 SampleRate, int32 NumChannels)
	{
		if (PatientAudio)
		{
			PatientAudio(Samples, SampleRate, NumChannels);
		}
	};
	Voice.State = EStationVoiceState::Connecting;
	if (!Client->ConnectVoice(VoiceCredential.GetValue(), MoveTemp(Handlers)))
	{
		Voice.State = EStationVoiceState::Failed;
		LoseVoice();
	}
}

void UStationRunFlow::HandleVoiceState(EStationVoiceState State)
{
	Voice.State = State;
	if (State == EStationVoiceState::Failed)
	{
		LoseVoice();
	}
	OnChanged.Broadcast();
}

void UStationRunFlow::LoseVoice()
{
	if (Voice.bLost)
	{
		return;
	}
	Voice.bLost = true;
	// In a training the learner goes on in writing (#196), which needs Phoenix.
	if (Step == EStationRunStep::Running && Client)
	{
		CheckPhoenix();
	}
}

void UStationRunFlow::HandleVoiceEvent(const FStationVoiceEvent& Event)
{
	if (Step == EStationRunStep::Invalidated)
	{
		return; // the run is over and kept nothing; the room is being left
	}
	if (Event.Kind == EStationVoiceEventKind::Fatal)
	{
		// The worker stopped, for example because the transcription failed.
		LoseVoice();
		OnChanged.Broadcast();
		return;
	}
	if (Event.TurnId < VoiceTurnId)
	{
		return; // a late event of an earlier turn
	}
	if (Event.TurnId > VoiceTurnId)
	{
		const bool bLearnerSpeaks = Event.Kind == EStationVoiceEventKind::Learner;
		if (bLearnerSpeaks && Event.Text.TrimStartAndEnd().IsEmpty())
		{
			return; // not speech yet: the worker supersedes nothing for it
		}
		if (!bVoiceOutcome)
		{
			DropSupersededVoiceTurn();
		}
		VoiceTurnId = Event.TurnId;
		bVoiceLearnerCommitted = false;
		VoiceLearnerLine = INDEX_NONE;
		bVoiceOutcome = false;
		Voice.LearnerText.Reset();
		Voice.PatientText.Reset();
		Voice.bExaminerNoted = false;
		if (bLearnerSpeaks)
		{
			// The learner speaks over the patient: the worker stops its voice, and
			// what is already buffered here stops too (#193).
			SilencePatient();
			if (IsListeningForExam())
			{
				// The armed exam mode takes this utterance: Phoenix sends it to the
				// impresso request, not to the patient (#364).
				SpokenExamTurn = Event.TurnId;
				SpokenExamText.Reset();
			}
		}
	}
	if (Event.TurnId == SpokenExamTurn && Event.Kind == EStationVoiceEventKind::TurnFailure)
	{
		// The request may or may not have reached Phoenix: the learner may ask again,
		// and what Phoenix released is read again.
		ResetSpokenExam();
		ExamErrorText = LOCTEXT("ExamRequestFailed", "Não foi possível enviar sua solicitação. Tente novamente.");
		ReloadReleasedImpressos();
		OnChanged.Broadcast();
		return;
	}
	if (Event.TurnId == SpokenExamTurn
		&& (Event.Kind == EStationVoiceEventKind::PatientText || Event.Kind == EStationVoiceEventKind::PatientComplete
			|| Event.Kind == EStationVoiceEventKind::ExaminerAcknowledged || Event.Kind == EStationVoiceEventKind::PatientUnanswered))
	{
		ReleaseSpokenExamAsDialogue();
	}
	switch (Event.Kind)
	{
	case EStationVoiceEventKind::Learner:
		if (bVoiceLearnerCommitted)
		{
			return;
		}
		if (Event.TurnId == SpokenExamTurn)
		{
			// The spoken exam request shows with the exam requests, never in the conversation.
			SpokenExamText = Event.Text;
			bVoiceLearnerCommitted = Event.bFinal;
		}
		else if (Event.bFinal)
		{
			// Spoken turns join the same conversation as typed ones.
			AddLine(EStationSpeaker::Learner, Event.Text);
			VoiceLearnerLine = Transcript.Num() - 1;
			bVoiceLearnerCommitted = true;
			Voice.LearnerText.Reset();
		}
		else
		{
			Voice.LearnerText = Event.Text;
		}
		break;
	case EStationVoiceEventKind::PatientText:
		// The worker sends a sentence's text before its voice.
		ResumePatient();
		Voice.PatientText = Event.Segment > 0 && !Voice.PatientText.IsEmpty()
			? Voice.PatientText + TEXT(" ") + Event.Text
			: Event.Text;
		if (Event.Segment == INDEX_NONE)
		{
			// A reply sent whole, not sentence by sentence.
			CommitVoiceReply();
			bVoiceOutcome = true;
		}
		break;
	case EStationVoiceEventKind::PatientComplete:
		CommitVoiceReply();
		bVoiceOutcome = true;
		break;
	case EStationVoiceEventKind::ExaminerAcknowledged:
		Voice.bExaminerNoted = true;
		bVoiceOutcome = true;
		break;
	case EStationVoiceEventKind::PatientUnanswered:
		// Phoenix kept the turn without a reply; nothing new is shown.
		bVoiceOutcome = true;
		return;
	case EStationVoiceEventKind::ExaminerImpresso:
		if (bVoiceOutcome)
		{
			return;
		}
		// An outcome like any other: a newer turn keeps this one (#193).
		TakeSpokenExamOutcome(Event);
		bVoiceOutcome = true;
		break;
	default:
		// A refused reply and a failed synthesis change nothing shown.
		return;
	}
	OnChanged.Broadcast();
}

bool UStationRunFlow::IsListening() const
{
	const FStationVoiceLink* Link = Client ? Client->GetVoice() : nullptr;
	return Step == EStationRunStep::Running && Link && !Voice.bMicrophoneUnavailable
		&& (Link->GetState() == EStationVoiceState::WaitingForWorker || Link->GetState() == EStationVoiceState::Ready);
}

void UStationRunFlow::ReportMicrophoneUnavailable()
{
	if (Voice.bMicrophoneUnavailable)
	{
		return;
	}
	Voice.bMicrophoneUnavailable = true;
	OnChanged.Broadcast();
}

void UStationRunFlow::DropSupersededVoiceTurn()
{
	Voice.PatientText.Reset();
	if (SpokenExamTurn != 0)
	{
		// The armed mode passes to the next utterance unless Phoenix already took
		// this one, whose outcome then never arrives: its impressos are read again.
		SpokenExamTurn = 0;
		SpokenExamText.Reset();
		ReloadReleasedImpressos();
	}
	if (Transcript.IsValidIndex(VoiceLearnerLine) && Transcript[VoiceLearnerLine].Speaker == EStationSpeaker::Learner)
	{
		Transcript.RemoveAt(VoiceLearnerLine);
	}
	VoiceLearnerLine = INDEX_NONE;
}

void UStationRunFlow::SilencePatient()
{
	if (Patient.Silence)
	{
		Patient.Silence();
	}
}

void UStationRunFlow::ResumePatient()
{
	// Until Phoenix closes the run the room stays, and its sentences still arrive.
	if (Step == EStationRunStep::Running && Patient.Resume)
	{
		Patient.Resume();
	}
}

void UStationRunFlow::ReleaseSpokenExamAsDialogue()
{
	const FString Text = SpokenExamText;
	ResetSpokenExam();
	if (bVoiceLearnerCommitted)
	{
		AddLine(EStationSpeaker::Learner, Text);
		VoiceLearnerLine = Transcript.Num() - 1;
	}
	else
	{
		Voice.LearnerText = Text; // its final transcript joins the conversation as usual
	}
}

void UStationRunFlow::TakeSpokenExamOutcome(const FStationVoiceEvent& Event)
{
	FString Text = Event.TurnId == SpokenExamTurn ? SpokenExamText : FString();
	if (Text.IsEmpty() && Transcript.IsValidIndex(VoiceLearnerLine) && Transcript[VoiceLearnerLine].Speaker == EStationSpeaker::Learner)
	{
		// The learner started speaking before the mode was armed, so the utterance
		// first showed as dialogue; it was the exam request.
		Text = Transcript[VoiceLearnerLine].Text;
		Transcript.RemoveAt(VoiceLearnerLine);
		VoiceLearnerLine = INDEX_NONE;
	}
	if (Text.IsEmpty())
	{
		Text = Voice.LearnerText;
	}
	Voice.LearnerText.Reset();
	// Phoenix used the mode for this request.
	ResetSpokenExam();

	FStationExamRequest& Answered = ExamRequests.AddDefaulted_GetRef();
	Answered.Text = Text;
	Answered.Reply = Event.Impresso;
	ReloadReleasedImpressos();
}

void UStationRunFlow::ResetSpokenExam()
{
	SpokenExamExpiresAt = 0.0;
	bSpokenExamReleased = false;
	SpokenExamTurn = 0;
	SpokenExamText.Reset();
}

void UStationRunFlow::ReloadReleasedImpressos()
{
	if (!Client)
	{
		return;
	}
	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	const uint32 ThisRun = Run;
	Client->ListImpressos([WeakThis, ThisRun](const TStationResult<TArray<FStationImpresso>>& Listed)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self || Self->Run != ThisRun)
		{
			return;
		}
		if (Listed.HasError())
		{
			if (IsUnanswered(Listed.GetError()))
			{
				Self->CheckPhoenix();
			}
			return;
		}
		Self->ReleasedImpressos = Listed.GetValue();
		Self->OnChanged.Broadcast();
	});
}

void UStationRunFlow::CommitVoiceReply()
{
	if (!Voice.PatientText.IsEmpty())
	{
		AddLine(EStationSpeaker::Patient, Voice.PatientText);
		Voice.PatientText.Reset();
	}
}

FText StationErrorText(const FStationClientError& Error, const FText& Fallback)
{
	// Phoenix writes its error messages for the learner in Brazilian Portuguese.
	// The client's own errors are English, including `invalid_response`, which
	// keeps the 2xx status of the answer it could not read.
	const bool bPhoenixError = Error.HttpStatus >= 400 && Error.HttpStatus < 600;
	return bPhoenixError && !Error.Message.IsEmpty() ? FText::FromString(Error.Message) : Fallback;
}

void UStationRunFlow::SetError(const FStationClientError& Error, const FText& Fallback)
{
	ErrorText = StationErrorText(Error, Fallback);
	OnChanged.Broadcast();
}

void UStationRunFlow::SetExamError(const FStationClientError& Error)
{
	ExamErrorText = StationErrorText(Error,
		LOCTEXT("ExamRequestFailed", "Não foi possível enviar sua solicitação. Tente novamente."));
	OnChanged.Broadcast();
}

#undef LOCTEXT_NAMESPACE
