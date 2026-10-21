// Gives scene and interface code the game's single station client.

#pragma once

#include "CoreMinimal.h"
#include "Subsystems/GameInstanceSubsystem.h"

#include "StationClientSubsystem.generated.h"

class UStationClient;

UCLASS()
class STATIONCLIENT_API UStationClientSubsystem : public UGameInstanceSubsystem
{
	GENERATED_BODY()

public:
	virtual void Initialize(FSubsystemCollectionBase& Collection) override;

	UStationClient* GetClient() const { return Client; }

private:
	UPROPERTY(Transient)
	TObjectPtr<UStationClient> Client;
};
