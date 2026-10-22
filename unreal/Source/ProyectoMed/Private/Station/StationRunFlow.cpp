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

namespace
{
	/** Phoenix ended the run itself, at its deadline: the run is over for this client too. */
	bool IsRunOver(const FStationClientError& Error)
	{
		return Error.Code == TEXT("station_time_elapsed") || Error.Code == TEXT("session_completed");
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
	if (!CanEnter(InMode))
	{
		return;
	}

	ResetRun();
	Mode = InMode;
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
				Self->ErrorText = LOCTEXT("MicrophoneBlocked", "Sem acesso ao microfone, o treino por voz não pode começar.");
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
	Client->StartSession(Mode == EStationTrainingMode::Voice, [WeakThis](const TStationResult<FStationSession>& Started)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self)
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
		Self->Client->RequestVoiceCredential([WeakThis](const TStationResult<FStationVoiceCredential>& Credential)
		{
			UStationRunFlow* Flow = WeakThis.Get();
			if (!Flow)
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
	Client->SendTurn(Turn, EStationTurnModality::Text, [WeakThis, Turn](const TStationResult<FStationTurnReply>& Reply)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self)
		{
			return;
		}
		Self->PendingTurn.Reset();
		if (Reply.HasError())
		{
			Self->UnsentTurn = Turn;
			// Phoenix may have taken the turn without this client hearing back.
			if (Reply.GetError().Code == TEXT("network_error"))
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
	Client->RequestImpresso(Attempt.Text, Attempt.RequestId, [WeakThis, Attempt](const TStationResult<FStationImpressoReply>& Reply)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self)
		{
			return;
		}
		Self->PendingExamRequest.Reset();
		if (Reply.HasError())
		{
			Self->UnsentExamRequest = Attempt.Text;
			if (Reply.GetError().Code == TEXT("network_error"))
			{
				Self->UnansweredExamRequest = Attempt;
			}
			Self->SetExamError(Reply.GetError());
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
}

void UStationRunFlow::ReloadTranscript(const FString& Turn)
{
	// No new turn until the record is read, so a late answer cannot replace it.
	bReloadingTranscript = true;

	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	Client->RefreshSession([WeakThis, Turn](const TStationResult<FStationSession>& Refreshed)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self)
		{
			return;
		}
		Self->bReloadingTranscript = false;
		if (!Refreshed.HasError())
		{
			Self->Transcript = Refreshed.GetValue().Messages;
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
	Client->FinishSession(FinishReason, [WeakThis](const TStationResult<FStationSession>& Finished)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self)
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
			Self->FailResult(Finished.GetError());
			return;
		}
		Self->LoadResult();
	});
}

void UStationRunFlow::LoadResult()
{
	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	Client->FetchResult([WeakThis](const TStationResult<FStationResult>& Loaded)
	{
		UStationRunFlow* Self = WeakThis.Get();
		if (!Self)
		{
			return;
		}
		if (Loaded.HasError())
		{
			Self->FailResult(Loaded.GetError());
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
	ErrorText = FText::GetEmpty();
	bVoiceFallback = false;
	VoiceCredential.Reset();
	Voice = FStationVoiceView();
	VoiceTurnId = 0;
	bVoiceLearnerCommitted = false;
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
			Self->Voice.State = State;
			Self->Voice.bLost |= State == EStationVoiceState::Failed;
			Self->OnChanged.Broadcast();
		}
	};
	// Runs on a LiveKit thread: copy the handler so the flow is never touched there.
	Handlers.OnPatientPcm = [PatientAudio = PatientAudio](TConstArrayView<int16> Samples, int32 SampleRate, int32 NumChannels)
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
		Voice.bLost = true;
	}
}

void UStationRunFlow::HandleVoiceEvent(const FStationVoiceEvent& Event)
{
	if (Event.Kind == EStationVoiceEventKind::Fatal)
	{
		Voice.bLost = true;
		OnChanged.Broadcast();
		return;
	}
	if (Event.TurnId < VoiceTurnId)
	{
		return; // a late event of an earlier turn
	}
	if (Event.TurnId > VoiceTurnId)
	{
		// A reply whose end never arrived is still kept.
		CommitVoiceReply();
		VoiceTurnId = Event.TurnId;
		bVoiceLearnerCommitted = false;
		Voice.LearnerText.Reset();
		Voice.bExaminerNoted = false;
	}
	switch (Event.Kind)
	{
	case EStationVoiceEventKind::Learner:
		if (bVoiceLearnerCommitted)
		{
			return;
		}
		if (Event.bFinal)
		{
			// Spoken turns join the same conversation as typed ones.
			AddLine(EStationSpeaker::Learner, Event.Text);
			bVoiceLearnerCommitted = true;
			Voice.LearnerText.Reset();
		}
		else
		{
			Voice.LearnerText = Event.Text;
		}
		break;
	case EStationVoiceEventKind::PatientText:
		Voice.PatientText = Event.Segment > 0 && !Voice.PatientText.IsEmpty()
			? Voice.PatientText + TEXT(" ") + Event.Text
			: Event.Text;
		if (Event.Segment == INDEX_NONE)
		{
			// A reply sent whole, not sentence by sentence.
			CommitVoiceReply();
		}
		break;
	case EStationVoiceEventKind::PatientComplete:
		CommitVoiceReply();
		break;
	case EStationVoiceEventKind::ExaminerAcknowledged:
		Voice.bExaminerNoted = true;
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
	return Step == EStationRunStep::Running && Link
		&& (Link->GetState() == EStationVoiceState::WaitingForWorker || Link->GetState() == EStationVoiceState::Ready);
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
