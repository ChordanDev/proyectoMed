#include "Station/StationDeskClock.h"

#include "Components/StaticMeshComponent.h"
#include "Engine/StaticMesh.h"
#include "Kismet/GameplayStatics.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Sound/SoundBase.h"
#include "UObject/ConstructorHelpers.h"

namespace
{
	// Sizes in centimetres. The actor's origin is the middle of the foot, on the desk;
	// the face looks along +X.
	constexpr double CaseDiameter = 16.0;
	constexpr double CaseDepth = 4.0;
	constexpr double DialDiameter = 14.0;
	constexpr double FootHeight = 1.5;
	constexpr double FaceHeight = FootHeight + CaseDiameter / 2.0;

	const FLinearColor CaseColor(0.03f, 0.035f, 0.04f);
	const FLinearColor DialColor(0.85f, 0.84f, 0.8f);
	const FLinearColor InkColor(0.02f, 0.02f, 0.02f);
	const FLinearColor SecondColor(0.6f, 0.04f, 0.03f);

	/** The engine's basic shapes are 100 cm across. */
	FVector ShapeScale(double X, double Y, double Z)
	{
		return FVector(X, Y, Z) / 100.0;
	}

	void Paint(const TArray<TObjectPtr<UStaticMeshComponent>>& Parts, UMaterialInterface* Base, const FLinearColor& Color,
		UObject& Outer)
	{
		if (!Base)
		{
			return;
		}
		// Transient: the level keeps no copy; `BeginPlay` paints the parts again.
		UMaterialInstanceDynamic* Material = UMaterialInstanceDynamic::Create(Base, &Outer);
		Material->SetFlags(RF_Transient);
		Material->SetVectorParameterValue(TEXT("Color"), Color);
		for (UStaticMeshComponent* Part : Parts)
		{
			if (Part)
			{
				Part->SetMaterial(0, Material);
			}
		}
	}
}

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
	// The shapes themselves come with the engine's grid material, which takes no colour.
	static ConstructorHelpers::FObjectFinder<UMaterialInterface> Plain(TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
	PlainMaterial = Plain.Object;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));

	CaseParts.Add(AddPart(TEXT("Foot"), RootComponent, false, FVector(0.0, 0.0, FootHeight / 2.0),
		ShapeScale(6.0, 10.0, FootHeight)));
	CaseParts.Add(AddPart(TEXT("Case"), RootComponent, true, FVector(0.0, 0.0, FaceHeight),
		ShapeScale(CaseDiameter, CaseDiameter, CaseDepth), FRotator(90.0, 0.0, 0.0)));
	DialParts.Add(AddPart(TEXT("Dial"), RootComponent, true, FVector(CaseDepth / 2.0, 0.0, FaceHeight),
		ShapeScale(DialDiameter, DialDiameter, 0.4), FRotator(90.0, 0.0, 0.0)));

	// The hour marks, longer at twelve, three, six and nine.
	const FVector Centre(CaseDepth / 2.0 + 0.25, 0.0, FaceHeight);
	for (int32 Hour = 0; Hour < 12; ++Hour)
	{
		const bool bQuarter = Hour % 3 == 0;
		const double Length = bQuarter ? 1.6 : 1.1;
		const FRotator Turn = StationClockHandRotation(Hour * 30.0);
		const FVector Offset = Turn.RotateVector(FVector(0.0, 0.0, DialDiameter / 2.0 - 0.6 - Length / 2.0));
		InkParts.Add(AddPart(*FString::Printf(TEXT("Mark%d"), Hour), RootComponent, false, Centre + Offset,
			ShapeScale(0.1, bQuarter ? 0.55 : 0.3, Length), Turn));
	}

	Face = CreateDefaultSubobject<USceneComponent>(TEXT("Face"));
	Face->SetupAttachment(RootComponent);
	Face->SetRelativeLocation(Centre);
	HourHand = AddHand(TEXT("HourHand"), 3.8, 0.6, 0.0, InkParts);
	MinuteHand = AddHand(TEXT("MinuteHand"), 5.6, 0.4, 0.15, InkParts);
	SecondHand = AddHand(TEXT("SecondHand"), 6.0, 0.15, 0.3, SecondParts);
	SecondParts.Add(AddPart(TEXT("Cap"), Face, true, FVector(0.45, 0.0, 0.0), ShapeScale(0.8, 0.8, 0.3),
		FRotator(90.0, 0.0, 0.0)));
}

UStaticMeshComponent* AStationDeskClock::AddPart(const TCHAR* Name, USceneComponent* Parent, bool bCylinder,
	const FVector& Location, const FVector& Scale, const FRotator& Rotation)
{
	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cube(TEXT("/Engine/BasicShapes/Cube.Cube"));
	static ConstructorHelpers::FObjectFinder<UStaticMesh> Cylinder(TEXT("/Engine/BasicShapes/Cylinder.Cylinder"));

	UStaticMeshComponent* Part = CreateDefaultSubobject<UStaticMeshComponent>(Name);
	Part->SetupAttachment(Parent);
	Part->SetStaticMesh(bCylinder ? Cylinder.Object : Cube.Object);
	Part->SetRelativeLocation(Location);
	Part->SetRelativeRotation(Rotation);
	Part->SetRelativeScale3D(Scale);
	// Scenery: nothing collides with it.
	Part->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Part->SetGenerateOverlapEvents(false);
	return Part;
}

USceneComponent* AStationDeskClock::AddHand(const TCHAR* Name, double Length, double Width, double Depth,
	TArray<TObjectPtr<UStaticMeshComponent>>& Colour)
{
	USceneComponent* Pivot = CreateDefaultSubobject<USceneComponent>(Name);
	Pivot->SetupAttachment(Face);
	// A short tail past the centre, as on a real hand.
	constexpr double Tail = 0.9;
	UStaticMeshComponent* Bar = AddPart(*FString::Printf(TEXT("%sBar"), Name), Pivot, false,
		FVector(Depth, 0.0, (Length - Tail) / 2.0), ShapeScale(0.1, Width, Length + Tail));
	Colour.Add(Bar);
	return Pivot;
}

void AStationDeskClock::OnConstruction(const FTransform& Transform)
{
	Super::OnConstruction(Transform);
	PaintParts();
	ShowTime(FDateTime::Now());
}

void AStationDeskClock::BeginPlay()
{
	Super::BeginPlay();
	PaintParts();
}

void AStationDeskClock::PaintParts()
{
	Paint(CaseParts, PlainMaterial, CaseColor, *this);
	Paint(DialParts, PlainMaterial, DialColor, *this);
	Paint(InkParts, PlainMaterial, InkColor, *this);
	Paint(SecondParts, PlainMaterial, SecondColor, *this);
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
