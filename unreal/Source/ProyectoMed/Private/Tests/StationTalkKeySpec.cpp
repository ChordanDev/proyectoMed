// Specs of the talk key of a voice training (#419).

#include "Misc/AutomationTest.h"
#include "Station/StationTalkKey.h"

BEGIN_DEFINE_SPEC(FStationTalkKeySpec, "ProyectoMed.StationTalkKey",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	FStationTalkKey Key;
END_DEFINE_SPEC(FStationTalkKeySpec)

void FStationTalkKeySpec::Define()
{
	constexpr double Tail = FStationTalkKey::TailSeconds;
	constexpr double Gap = FStationTalkKey::DoubleTapSeconds;

	BeforeEach([this]() { Key = FStationTalkKey(); });

	It("starts closed", [this]()
	{
		TestFalse("closed", Key.IsOpen(0.0));
		TestFalse("not held", Key.IsHeld());
	});

	It("sends while the key is held and for a short tail after its release", [this, Tail]()
	{
		TestTrue("a press opens", Key.Press(10.0, false));
		TestTrue("held", Key.IsHeld());
		TestTrue("open while held", Key.IsOpen(12.0));
		Key.Release(12.0);
		TestFalse("not held once released", Key.IsHeld());
		TestTrue("open during the tail", Key.IsOpen(12.0 + Tail * 0.5));
		TestFalse("closed after the tail", Key.IsOpen(12.0 + Tail));
	});

	It("ignores the key repeating while it is held", [this]()
	{
		Key.Press(1.0, false);
		TestFalse("a repeat opens nothing new", Key.Press(1.5, false));
		Key.Release(2.0);
		TestFalse("one release ends the press", Key.IsHeld());
	});

	It("does nothing on a single press while the patient answers", [this]()
	{
		TestFalse("a single press opens nothing", Key.Press(1.0, true));
		TestFalse("not held", Key.IsHeld());
		TestFalse("closed", Key.IsOpen(1.1));
		Key.Release(1.2);
		TestFalse("still closed", Key.IsOpen(1.3));
	});

	It("opens on a tap followed by a press while the patient answers", [this, Gap]()
	{
		Key.Press(1.0, true);
		Key.Release(1.1);
		TestTrue("the second press opens", Key.Press(1.1 + Gap * 0.5, true));
		TestTrue("held", Key.IsHeld());
		Key.Release(3.0);
		TestFalse("a single press after it opens nothing again", Key.Press(3.0 + Gap * 2.0, true));
	});

	It("needs the second press within the double-tap gap", [this, Gap]()
	{
		Key.Press(1.0, true);
		Key.Release(1.1);
		TestFalse("a late second press opens nothing", Key.Press(1.1 + Gap * 1.5, true));
		Key.Release(2.0);
		TestTrue("but it counts as the first tap of the next pair", Key.Press(2.0 + Gap * 0.5, true));
	});

	It("ignores a release without a press", [this]()
	{
		Key.Release(1.0);
		TestFalse("closed", Key.IsOpen(1.0));
		TestTrue("the next press still opens", Key.Press(1.2, false));
	});

	It("forgets a held key on reset", [this]()
	{
		Key.Press(1.0, false);
		Key.Reset();
		TestFalse("closed", Key.IsOpen(1.0));
		TestFalse("not held", Key.IsHeld());
	});
}
