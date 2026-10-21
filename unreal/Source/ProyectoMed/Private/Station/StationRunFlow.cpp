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

void UStationRunFlow::SetError(const FStationClientError& Error, const FText& Fallback)
{
	// Phoenix's messages are written for the learner in Brazilian Portuguese; the
	// client's own codes are not, so they get the fallback.
	ErrorText = Error.HttpStatus > 0 && !Error.Message.IsEmpty() ? FText::FromString(Error.Message) : Fallback;
	OnChanged.Broadcast();
}

#undef LOCTEXT_NAMESPACE
