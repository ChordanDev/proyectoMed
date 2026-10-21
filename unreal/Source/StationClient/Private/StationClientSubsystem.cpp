#include "StationClientSubsystem.h"

#include "StationClient.h"

void UStationClientSubsystem::Initialize(FSubsystemCollectionBase& Collection)
{
	Super::Initialize(Collection);
	Client = NewObject<UStationClient>(this);
}
