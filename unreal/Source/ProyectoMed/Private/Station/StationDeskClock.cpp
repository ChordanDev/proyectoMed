#include "Station/StationDeskClock.h"

#include "Components/StaticMeshComponent.h"
#include "Kismet/GameplayStatics.h"
#include "Sound/SoundBase.h"

FStationClockHands StationClockHands(const FDateTime& Time)
{
	const double Seconds = Time.GetSecond() + Time.GetMillisecond() / 1000.0;
	const double Minutes = Time.GetMinute() + Seconds / 60.0;
	const double Hours = Time.GetHour() % 12 + Minutes / 60.0;
	FStationClockHands Hands;
	Hands.Hour = Hours * 30.0;
	Hands.Minute = Minutes * 6.0;
	Hands.Second = Seconds * 6.0;
	return Hands;
}

FRotator StationClockHandRotation(double Degrees)
{
	// A roll about +X. A positive roll turns +Z towards +Y, which from the front is anticlockwise.
	return FRotator(0.0, 0.0, -Degrees);
}

AStationDeskClock::AStationDeskClock()
{
	PrimaryActorTick.bCanEverTick = false;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	Body = AddPart(TEXT("Body"));
	HourHand = AddPart(TEXT("HourHand"));
	MinuteHand = AddPart(TEXT("MinuteHand"));
	SecondHand = AddPart(TEXT("SecondHand"));
}

UStaticMeshComponent* AStationDeskClock::AddPart(const TCHAR* Name)
{
	UStaticMeshComponent* Part = CreateDefaultSubobject<UStaticMeshComponent>(Name);
	Part->SetupAttachment(RootComponent);
	// Scenery: nothing collides with it.
	Part->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Part->SetGenerateOverlapEvents(false);
	return Part;
}

void AStationDeskClock::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	ShowTime(FDateTime::Now());
}

void AStationDeskClock::ShowTime(const FDateTime& LocalTime)
{
	const FStationClockHands Hands = StationClockHands(LocalTime);
	HourHand->SetRelativeRotation(StationClockHandRotation(Hands.Hour));
	MinuteHand->SetRelativeRotation(StationClockHandRotation(Hands.Minute));
	SecondHand->SetRelativeRotation(StationClockHandRotation(Hands.Second));
}

void AStationDeskClock::PlayCue(EStationExamCue Cue)
{
	if (USoundBase* Sound = Cue == EStationExamCue::Start ? StartSound.Get() : EndSound.Get())
	{
		UGameplayStatics::PlaySound2D(this, Sound);
	}
}
