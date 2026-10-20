// Prebuilt LiveKit C++ SDK (github.com/livekit/client-sdk-cpp, Apache-2.0).
// Fetch the binaries with scripts/fetch-livekit-sdk.sh; they are git-ignored.

using System.IO;
using UnrealBuildTool;

public class LiveKitSDK : ModuleRules
{
	public LiveKitSDK(ReadOnlyTargetRules Target) : base(Target)
	{
		Type = ModuleType.External;

		if (Target.Platform == UnrealTargetPlatform.Mac)
		{
			string Root = Path.Combine(ModuleDirectory, "Mac");
			RequireFetchedSdk(Root);
			PublicSystemIncludePaths.Add(Path.Combine(Root, "include"));

			string LibDir = Path.Combine(Root, "lib");
			PublicAdditionalLibraries.Add(Path.Combine(LibDir, "liblivekit.dylib"));
			foreach (string Dylib in new[] { "liblivekit.dylib", "liblivekit_ffi.dylib" })
			{
				// Both dylibs use @rpath install names; stage them next to the module binary.
				RuntimeDependencies.Add(Path.Combine("$(TargetOutputDir)", Dylib), Path.Combine(LibDir, Dylib));
			}
			PublicRuntimeLibraryPaths.Add(LibDir);
		}
		else if (Target.Platform == UnrealTargetPlatform.Win64)
		{
			string Root = Path.Combine(ModuleDirectory, "Win64");
			RequireFetchedSdk(Root);
			PublicSystemIncludePaths.Add(Path.Combine(Root, "include"));
			PublicAdditionalLibraries.Add(Path.Combine(Root, "lib", "livekit.lib"));

			foreach (string Dll in new[] { "livekit_ffi.dll", "livekit.dll" })
			{
				PublicDelayLoadDLLs.Add(Dll);
				RuntimeDependencies.Add(Path.Combine("$(TargetOutputDir)", Dll), Path.Combine(Root, "bin", Dll));
			}
		}
		else
		{
			throw new BuildException("LiveKitSDK supports only Mac and Win64 (ADR-013).");
		}
	}

	private static void RequireFetchedSdk(string Root)
	{
		if (!Directory.Exists(Path.Combine(Root, "include")))
		{
			throw new BuildException("LiveKit SDK missing at " + Root + ". Run scripts/fetch-livekit-sdk.sh.");
		}
	}
}
