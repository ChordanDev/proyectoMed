// The single station client module from #190: the only code in the Unreal
// client that talks to Phoenix (and, from #191, to LiveKit). Scene and
// interface code depend on it and never call the network directly.

using UnrealBuildTool;

public class StationClient : ModuleRules
{
	public StationClient(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;

		PublicDependencyModuleNames.AddRange(new string[] {
			"Core",
			"CoreUObject",
			"Engine",
		});

		PrivateDependencyModuleNames.AddRange(new string[] {
			"HTTP",
			"Json",
		});

		// The automation tests serve a fake Phoenix to control response timing.
		if (Target.Configuration != UnrealTargetConfiguration.Shipping)
		{
			PrivateDependencyModuleNames.Add("HTTPServer");
		}
	}
}
