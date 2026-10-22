// Spike SDK ownership: `ProyectoMed.PatientVoiceSpike.Unit` needs nothing else.

#include "LiveKitPatientStream.h"
#include "Misc/AutomationTest.h"

THIRD_PARTY_INCLUDES_START
#include "livekit/livekit.h"
THIRD_PARTY_INCLUDES_END

#if WITH_DEV_AUTOMATION_TESTS

BEGIN_DEFINE_SPEC(FLiveKitPatientStreamUnitSpec, "ProyectoMed.PatientVoiceSpike.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
END_DEFINE_SPEC(FLiveKitPatientStreamUnitSpec)

void FLiveKitPatientStreamUnitSpec::Define()
{
	Describe("the LiveKit SDK", [this]()
	{
		It("stays up when the spike shuts down an SDK another module initialised", [this]()
		{
			// Another module (the station client) initialises the SDK first.
			const bool bOtherOwnsSdk = livekit::initialize(livekit::LogLevel::Warn);

			TestTrue("the spike finds the SDK ready", FLiveKitPatientStream::InitializeSdk());
			FLiveKitPatientStream::ShutdownSdk();

			// `initialize` answers false while the SDK is still up.
			const bool bSdkWasDown = livekit::initialize(livekit::LogLevel::Warn);
			TestFalse("the spike left the other module's SDK running", bSdkWasDown);

			if (bOtherOwnsSdk || bSdkWasDown)
			{
				livekit::shutdown();
			}
		});
	});
}

#endif
