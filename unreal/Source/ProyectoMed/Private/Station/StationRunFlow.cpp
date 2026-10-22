#include "Station/StationRunFlow.h"

#include "StationClient.h"

#define LOCTEXT_NAMESPACE "StationRunFlow"

DEFINE_LOG_CATEGORY_STATIC(LogStationRun, Log, All);

bool IsVoiceTrainingAvailable(const FStationSummary& Station)
{
	return Station.VoiceMode == EStationVoiceMode::Realtime;
}

FText FormatStationTimer(const FTimespan& Remaining)
{
	const int64 Seconds = FMath::Max<int64>(0, FMath::CeilToInt64(Remaining.GetTotalSeconds()));
	return FText::FromString(FString::Printf(TEXT("%02lld:%02lld"), Seconds / 60, Seconds % 60));
}

void UStationRunFlow::Begin(UStationClient* InClient)
{
	Client = InClient;
	Step = EStationRunStep::Notice;
	LoadStation();
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
		&& (InMode == EStationTrainingMode::Text || IsVoiceTrainingAvailable(Station.GetValue()));
}

void UStationRunFlow::Enter(EStationTrainingMode InMode)
{
	if (!CanEnter(InMode))
	{
		return;
	}

	Mode = InMode;
	Step = EStationRunStep::Starting;
	ErrorText = FText::GetEmpty();
	bVoiceFallback = false;
	VoiceCredential.Reset();
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
	OnChanged.Broadcast();

	TWeakObjectPtr<UStationRunFlow> WeakThis(this);
	Client->StartSession(InMode == EStationTrainingMode::Voice, [WeakThis](const TStationResult<FStationSession>& Started)
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
			return;
		}

		Self->AddLine(EStationSpeaker::Learner, Turn);
		const FStationTurnReply& Value = Reply.GetValue();
		// An examiner-addressed turn is kept with no patient reply.
		if (Value.Outcome == EStationTurnOutcome::PatientReply && !Value.ReplyText.IsEmpty())
		{
			Self->AddLine(EStationSpeaker::Patient, Value.ReplyText);
		}
		Self->OnChanged.Broadcast();
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
			return;
		}

		FStationExamRequest& Answered = Self->ExamRequests.AddDefaulted_GetRef();
		Answered.Text = Attempt.Text;
		Answered.Reply = Reply.GetValue();
		Self->ReleasedImpressos = Reply.GetValue().ReleasedImpressos;
		Self->OnChanged.Broadcast();
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
	});
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
