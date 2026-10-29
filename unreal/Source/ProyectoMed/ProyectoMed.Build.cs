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

		// The patient's voice and the learner's microphone in a voice run (#191).
		PrivateDependencyModuleNames.AddRange(new string[] {
			"AudioCapture",
			"AudioExtensions",
			"AudioMixer",
			"AudioPlatformConfiguration",
			"MetaHumanCoreTech",
			"NNE",
			"SpeechAnimationSolver",
		});

		// The run flow tests serve a fake Phoenix that can leave a call unanswered (#196);
		// the HUD snapshots render widgets to images.
		if (Target.Configuration != UnrealTargetConfiguration.Shipping)
		{
			PrivateDependencyModuleNames.AddRange(new string[] { "HTTPServer", "RenderCore" });
		}

		// The system microphone prompt on macOS.
		if (Target.Platform == UnrealTargetPlatform.Mac)
		{
			PublicFrameworks.Add("AVFoundation");
		}

		// Uncomment if you are using online features
		// PrivateDependencyModuleNames.Add("OnlineSubsystem");

		// To include OnlineSubsystemSteam, add it to the plugins section in your uproject file with the Enabled attribute set to true
	}
}
