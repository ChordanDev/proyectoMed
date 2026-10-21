#include "Station/StationGameMode.h"

#include "Station/StationPlayerController.h"

AStationGameMode::AStationGameMode()
{
	PlayerControllerClass = AStationPlayerController::StaticClass();
	DefaultPawnClass = nullptr;
}
