#include "PatientVoiceLiveLinkSource.h"

#include "ILiveLinkClient.h"
#include "LiveLinkTypes.h"
#include "Roles/LiveLinkBasicRole.h"

namespace
{
	// Trailing properties expected by the MetaHuman face, matching Epic's
	// MetaHuman local Live Link subject. Audio drives no head pose.
	const TArray<FName> TrailingProperties = {
		TEXT("HeadControlSwitch"), TEXT("HeadRoll"), TEXT("HeadPitch"), TEXT("HeadYaw"),
		TEXT("HeadTranslationX"), TEXT("HeadTranslationY"), TEXT("HeadTranslationZ"),
		TEXT("MHFDSVersion"), TEXT("DisableFaceOverride"),
	};
	const TArray<float> TrailingValues = { 0, 0, 0, 0, 0, 0, 0, 1, 1 };
}

FPatientVoiceLiveLinkSource::FPatientVoiceLiveLinkSource(FName InSubjectName)
	: SubjectName(InSubjectName)
{
}

void FPatientVoiceLiveLinkSource::PushRawControls(const TMap<FString, float>& RawControls)
{
	FScopeLock ScopeLock(&Lock);
	if (!Client || bShutdown)
	{
		return;
	}

	const FLiveLinkSubjectKey Key(SourceGuid, SubjectName);

	if (ControlNames.IsEmpty())
	{
		RawControls.GenerateKeyArray(ControlNames);

		FLiveLinkStaticDataStruct StaticDataStruct(FLiveLinkBaseStaticData::StaticStruct());
		FLiveLinkBaseStaticData& StaticData = *StaticDataStruct.Cast<FLiveLinkBaseStaticData>();
		for (const FString& Name : ControlNames)
		{
			StaticData.PropertyNames.Add(FName(Name));
		}
		StaticData.PropertyNames.Append(TrailingProperties);
		Client->PushSubjectStaticData_AnyThread(Key, ULiveLinkBasicRole::StaticClass(), MoveTemp(StaticDataStruct));
	}

	FLiveLinkFrameDataStruct FrameDataStruct(FLiveLinkBaseFrameData::StaticStruct());
	FLiveLinkBaseFrameData& FrameData = *FrameDataStruct.Cast<FLiveLinkBaseFrameData>();
	FrameData.PropertyValues.Reserve(ControlNames.Num() + TrailingValues.Num());
	for (const FString& Name : ControlNames)
	{
		const float* Value = RawControls.Find(Name);
		FrameData.PropertyValues.Add(Value ? *Value : 0.0f);
	}
	FrameData.PropertyValues.Append(TrailingValues);
	FrameData.WorldTime = FLiveLinkWorldTime(FPlatformTime::Seconds());
	Client->PushSubjectFrameData_AnyThread(Key, MoveTemp(FrameDataStruct));
}

void FPatientVoiceLiveLinkSource::SetStatus(const FString& InStatus)
{
	FScopeLock ScopeLock(&Lock);
	Status = InStatus;
}

void FPatientVoiceLiveLinkSource::ReceiveClient(ILiveLinkClient* InClient, FGuid InSourceGuid)
{
	FScopeLock ScopeLock(&Lock);
	Client = InClient;
	SourceGuid = InSourceGuid;
}

bool FPatientVoiceLiveLinkSource::IsSourceStillValid() const
{
	FScopeLock ScopeLock(&Lock);
	return Client != nullptr && !bShutdown;
}

bool FPatientVoiceLiveLinkSource::RequestSourceShutdown()
{
	FScopeLock ScopeLock(&Lock);
	bShutdown = true;
	Client = nullptr;
	return true;
}

FText FPatientVoiceLiveLinkSource::GetSourceType() const
{
	return FText::FromString(TEXT("Patient voice (LiveKit spike)"));
}

FText FPatientVoiceLiveLinkSource::GetSourceMachineName() const
{
	return FText::FromString(FPlatformProcess::ComputerName());
}

FText FPatientVoiceLiveLinkSource::GetSourceStatus() const
{
	FScopeLock ScopeLock(&Lock);
	return FText::FromString(Status);
}
