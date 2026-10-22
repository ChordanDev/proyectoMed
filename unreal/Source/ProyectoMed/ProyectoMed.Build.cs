// Copyright Epic Games, Inc. All Rights Reserved.

using UnrealBuildTool;

public class ProyectoMed : ModuleRules
{
	public ProyectoMed(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
	
		// Scene and interface code reach Phoenix and LiveKit only through StationClient.
		PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "InputCore", "EnhancedInput", "StationClient" });

		PrivateDependencyModuleNames.AddRange(new string[] { "UMG", "Slate", "SlateCore" });

		// The patient's voice and its lip sync in a voice run (#191).
		PrivateDependencyModuleNames.AddRange(new string[] {
			"AudioMixer",
			"AudioPlatformConfiguration",
			"MetaHumanCoreTech",
			"NNE",
			"SpeechAnimationSolver",
		});

		// Uncomment if you are using online features
		// PrivateDependencyModuleNames.Add("OnlineSubsystem");

		// To include OnlineSubsystemSteam, add it to the plugins section in your uproject file with the Enabled attribute set to true
	}
}
