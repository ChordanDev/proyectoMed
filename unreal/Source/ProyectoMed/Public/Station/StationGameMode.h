// Game mode of the station client: no controllable pawn; the learner sees the
// consultation scene through its camera and acts through the station screens.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/GameModeBase.h"

#include "StationGameMode.generated.h"

UCLASS()
class PROYECTOMED_API AStationGameMode : public AGameModeBase
{
	GENERATED_BODY()

public:
	AStationGameMode();
};
