#pragma once

#include "CoreMinimal.h"
#include "ILiveLinkSource.h"

class ILiveLinkClient;

/**
 * Live Link source that publishes MetaHuman raw face controls under one subject,
 * in the same Basic-role layout as Epic's MetaHuman audio source, so a MetaHuman
 * consumes it by selecting the subject as its Live Link face source.
 */
class FPatientVoiceLiveLinkSource : public ILiveLinkSource
{
public:
	explicit FPatientVoiceLiveLinkSource(FName InSubjectName);

	/** Thread-safe. The first call also publishes the subject's static data. */
	void PushRawControls(const TMap<FString, float>& RawControls);

	void SetStatus(const FString& InStatus);

	// ILiveLinkSource
	virtual void ReceiveClient(ILiveLinkClient* InClient, FGuid InSourceGuid) override;
	virtual bool IsSourceStillValid() const override;
	virtual bool RequestSourceShutdown() override;
	virtual FText GetSourceType() const override;
	virtual FText GetSourceMachineName() const override;
	virtual FText GetSourceStatus() const override;

private:
	FName SubjectName;
	ILiveLinkClient* Client = nullptr;
	FGuid SourceGuid;

	mutable FCriticalSection Lock;
	TArray<FString> ControlNames;
	FString Status = TEXT("Idle");
	bool bShutdown = false;
};
