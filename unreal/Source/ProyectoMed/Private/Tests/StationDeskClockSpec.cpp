// The desk clock's hands (#425). Needs nothing else; how the clock looks on the desk
// is judged in the editor.

#include "Misc/AutomationTest.h"

#if WITH_DEV_AUTOMATION_TESTS

#include "Components/StaticMeshComponent.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Materials/MaterialInterface.h"
#include "Station/StationDeskClock.h"

BEGIN_DEFINE_SPEC(FStationDeskClockUnitSpec, "ProyectoMed.StationDeskClock.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
END_DEFINE_SPEC(FStationDeskClockUnitSpec)

void FStationDeskClockUnitSpec::Define()
{
	It("points the hands at the time of day, sweeping", [this]()
	{
		const FStationClockHands Three = StationClockHands(FDateTime(2026, 10, 29, 15, 0, 0));
		TestEqual("hour at three", Three.Hour, 90.0, 1e-6);
		TestEqual("minute at twelve", Three.Minute, 0.0, 1e-6);
		TestEqual("second at twelve", Three.Second, 0.0, 1e-6);

		const FStationClockHands Later = StationClockHands(FDateTime(2026, 10, 29, 10, 30, 15, 500));
		TestEqual("hour between ten and eleven", Later.Hour, 300.0 + 15.0 + 15.5 / 120.0, 1e-6);
		TestEqual("minute past the half", Later.Minute, 180.0 + 15.5 / 10.0, 1e-6);
		TestEqual("second at a quarter, and a half", Later.Second, 93.0, 1e-6);
	});

	It("turns a hand clockwise as seen from the front of the face", [this]()
	{
		const FVector Twelve(0.0, 0.0, 1.0);
		TestTrue("twelve stays up", StationClockHandRotation(0.0).RotateVector(Twelve).Equals(FVector(0.0, 0.0, 1.0), 1e-6));
		// The face looks along +X: from the front, the viewer's right is -Y.
		TestTrue("three on the viewer's right", StationClockHandRotation(90.0).RotateVector(Twelve).Equals(FVector(0.0, -1.0, 0.0), 1e-6));
		TestTrue("six down", StationClockHandRotation(180.0).RotateVector(Twelve).Equals(FVector(0.0, 0.0, -1.0), 1e-6));
	});

	It("shows the time it is given on its hands", [this]()
	{
		AStationDeskClock* Clock = GEngine->GetWorldContexts()[0].World()->SpawnActor<AStationDeskClock>();
		if (!TestNotNull("clock", Clock))
		{
			return;
		}
		Clock->ShowTime(FDateTime(2026, 10, 29, 15, 0, 0));
		const FVector Twelve(0.0, 0.0, 1.0);
		TestTrue("hour hand at three",
			Clock->HourHand->GetRelativeRotation().RotateVector(Twelve).Equals(FVector(0.0, -1.0, 0.0), 1e-4));
		TestTrue("minute hand at twelve",
			Clock->MinuteHand->GetRelativeRotation().RotateVector(Twelve).Equals(Twelve, 1e-4));
		Clock->Destroy();
	});

	It("paints its parts in plain colours, not the engine's grid", [this]()
	{
		AStationDeskClock* Clock = GEngine->GetWorldContexts()[0].World()->SpawnActor<AStationDeskClock>();
		if (!TestNotNull("clock", Clock))
		{
			return;
		}
		for (const TObjectPtr<UStaticMeshComponent>& Part : Clock->DialParts)
		{
			UMaterialInterface* Material = Part->GetMaterial(0);
			FLinearColor Color;
			TestTrue("tinted", Material && Material->GetVectorParameterValue(TEXT("Color"), Color) && Color.R > 0.5f);
			TestEqual("on the plain shape material", Material ? Material->GetBaseMaterial()->GetName() : FString(),
				FString(TEXT("BasicShapeMaterial")));
		}
		TestEqual("the second hand and its cap", Clock->SecondParts.Num(), 2);
		for (const TObjectPtr<UStaticMeshComponent>& Part : Clock->SecondParts)
		{
			FLinearColor Color;
			TestTrue("red", Part->GetMaterial(0)->GetVectorParameterValue(TEXT("Color"), Color) && Color.R > 0.5f && Color.G < 0.2f);
		}
		Clock->Destroy();
	});
}

#endif
