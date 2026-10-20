// Spike for #189: plays the LiveKit patient voice track and drives MetaHuman lip
// sync from it. Throwaway code that answers the spike; not the production client.

using UnrealBuildTool;

public class PatientVoiceSpike : ModuleRules
{
	public PatientVoiceSpike(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		// The LiveKit SDK headers use std::exception types.
		bEnableExceptions = true;

		PublicDependencyModuleNames.AddRange(new string[] {
			"Core",
			"CoreUObject",
			"Engine",
		});

		PrivateDependencyModuleNames.AddRange(new string[] {
			"Projects",
			"LiveLink",
			"LiveLinkInterface",
			"NNE",
			"AudioPlatformConfiguration",
			"SpeechAnimationSolver",
			"MetaHumanCoreTech",
			"LiveKitSDK",
		});
	}
}
