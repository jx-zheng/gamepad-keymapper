#!/usr/bin/env python3
"""Generate GamepadKeymapper.xcodeproj from the source tree."""

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    path.relative_to(ROOT).as_posix()
    for path in sorted((ROOT / "Sources" / "GamepadKeymapperCore").glob("*.swift"))
] + [
    path.relative_to(ROOT).as_posix()
    for path in sorted((ROOT / "App").rglob("*.swift"))
]


def pid(text: str) -> str:
    return hashlib.sha1(text.encode()).hexdigest()[:24].upper()


def main() -> None:
    project_id = pid("project")
    target_id = pid("target")
    sources_phase = pid("sources-phase")
    frameworks_phase = pid("frameworks-phase")
    resources_phase = pid("resources-phase")
    product_ref = pid("product")
    info_ref = pid("file:App/Info.plist")
    project_config_list = pid("project-configs")
    target_config_list = pid("target-configs")
    debug_project = pid("config:project:debug")
    release_project = pid("config:project:release")
    debug_target = pid("config:target:debug")
    release_target = pid("config:target:release")
    main_group = pid("group:main")
    source_group = pid("group:sources")
    app_group = pid("group:app")
    core_group = pid("group:core")
    products_group = pid("group:products")

    file_refs = {path: pid(f"file:{path}") for path in SOURCES}
    build_files = {path: pid(f"build:{path}") for path in SOURCES}

    def file_ref(path: str, ref: str) -> str:
        name = Path(path).name
        return (
            f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; "
            f"lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = \"<group>\"; }};"
        )

    objects = []
    objects.append(
        f"\t\t{project_id} /* Project object */ = {{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 1500; }}; "
        f"buildConfigurationList = {project_config_list}; compatibilityVersion = \"Xcode 14.0\"; "
        f"developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); "
        f"mainGroup = {main_group}; productRefGroup = {products_group}; projectDirPath = \"\"; projectRoot = \"\"; "
        f"targets = ({target_id} /* GamepadKeymapper */); }};"
    )
    objects.append(
        f"\t\t{target_id} /* GamepadKeymapper */ = {{isa = PBXNativeTarget; buildConfigurationList = {target_config_list}; "
        f"buildPhases = ({sources_phase} /* Sources */, {frameworks_phase} /* Frameworks */, {resources_phase} /* Resources */); "
        f"buildRules = (); dependencies = (); name = GamepadKeymapper; productName = GamepadKeymapper; "
        f"productReference = {product_ref} /* GamepadKeymapper.app */; productType = \"com.apple.product-type.application\"; }};"
    )
    objects.append(
        f"\t\t{product_ref} /* GamepadKeymapper.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; "
        f"includeInIndex = 0; path = GamepadKeymapper.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    objects.append(
        f"\t\t{info_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};"
    )
    for path, ref in file_refs.items():
        objects.append(file_ref(path, ref))

    build_entries = "\n".join(
        f"\t\t{build_files[path]} /* {Path(path).name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {Path(path).name} */; }};"
        for path in SOURCES
    )
    objects.append(build_entries)
    source_files = "\n".join(
        f"\t\t\t\t{build_files[path]} /* {Path(path).name} in Sources */,"
        for path in SOURCES
    )
    objects.append(
        f"\t\t{sources_phase} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (\n{source_files}\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};"
    )
    objects.append(
        f"\t\t{frameworks_phase} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};"
    )
    objects.append(
        f"\t\t{resources_phase} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};"
    )

    core_children = "\n".join(
        f"\t\t\t\t{file_refs[path]} /* {Path(path).name} */,"
        for path in SOURCES
        if path.startswith("Sources/")
    )
    app_children = "\n".join(
        f"\t\t\t\t{file_refs[path]} /* {Path(path).name} */,"
        for path in SOURCES
        if path.startswith("App/")
    )
    objects.append(
        f"\t\t{core_group} /* GamepadKeymapperCore */ = {{isa = PBXGroup; children = (\n{core_children}\n\t\t\t); path = Sources/GamepadKeymapperCore; sourceTree = \"<group>\"; }};"
    )
    objects.append(
        f"\t\t{app_group} /* App */ = {{isa = PBXGroup; children = (\n{app_children}\n\t\t\t\t{info_ref} /* Info.plist */,\n\t\t\t); path = App; sourceTree = \"<group>\"; }};"
    )
    objects.append(
        f"\t\t{products_group} /* Products */ = {{isa = PBXGroup; children = ({product_ref} /* GamepadKeymapper.app */,); name = Products; sourceTree = \"<group>\"; }};"
    )
    objects.append(
        f"\t\t{source_group} /* Source */ = {{isa = PBXGroup; children = ({core_group} /* GamepadKeymapperCore */, {app_group} /* App */); name = Source; sourceTree = \"<group>\"; }};"
    )
    objects.append(
        f"\t\t{main_group} = {{isa = PBXGroup; children = ({source_group} /* Source */, {products_group} /* Products */); sourceTree = \"<group>\"; }};"
    )

    def config(ref: str, name: str, body: str) -> str:
        return (
            f"\t\t{ref} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{\n{body}\n\t\t\t}}; name = {name}; }};"
        )

    project_common = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_NS_ASSERTIONS = YES;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_VERSION = 5.0;"""
    objects.append(config(debug_project, "Debug", project_common + "\n\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n\t\t\t\tONLY_ACTIVE_ARCH = YES;"))
    objects.append(config(release_project, "Release", project_common.replace("ENABLE_NS_ASSERTIONS = YES;", "ENABLE_NS_ASSERTIONS = NO;") + "\n\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";\n\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";"))
    target_common = """\t\t\t\tCODE_SIGNING_ALLOWED = NO;
\t\t\t\tCODE_SIGNING_REQUIRED = NO;
\t\t\t\tCODE_SIGN_IDENTITY = \"\";
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_APP_SANDBOX = NO;
\t\t\t\tENABLE_HARDENED_RUNTIME = NO;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = App/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t\"$(inherited)\",
\t\t\t\t\t\"@executable_path/../Frameworks\",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = app.gamepadkeymapper.GamepadKeymapper;
\t\t\t\tPRODUCT_NAME = GamepadKeymapper;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;"""
    objects.append(config(debug_target, "Debug", target_common + "\n\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;"))
    objects.append(config(release_target, "Release", target_common))
    objects.append(
        f"\t\t{project_config_list} /* Build configuration list for PBXProject */ = {{isa = XCConfigurationList; buildConfigurations = ({debug_project} /* Debug */, {release_project} /* Release */); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};"
    )
    objects.append(
        f"\t\t{target_config_list} /* Build configuration list for PBXNativeTarget */ = {{isa = XCConfigurationList; buildConfigurations = ({debug_target} /* Debug */, {release_target} /* Release */); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};"
    )

    pbx = "\n".join(objects)
    text = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

{pbx}

\t}};
\trootObject = {project_id} /* Project object */;
}}
"""
    project_dir = ROOT / "GamepadKeymapper.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    (project_dir / "project.pbxproj").write_text(text)
    scheme_dir = project_dir / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "GamepadKeymapper.app"
               BlueprintName = "GamepadKeymapper"
               ReferencedContainer = "container:GamepadKeymapper.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableReference
         BuildableIdentifier = "primary"
         BlueprintIdentifier = "{target_id}"
         BuildableName = "GamepadKeymapper.app"
         BlueprintName = "GamepadKeymapper"
         ReferencedContainer = "container:GamepadKeymapper.xcodeproj">
      </BuildableReference>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableReference
         BuildableIdentifier = "primary"
         BlueprintIdentifier = "{target_id}"
         BuildableName = "GamepadKeymapper.app"
         BlueprintName = "GamepadKeymapper"
         ReferencedContainer = "container:GamepadKeymapper.xcodeproj">
      </BuildableReference>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
    (scheme_dir / "GamepadKeymapper.xcscheme").write_text(scheme)
    print(f"Wrote {project_dir / 'project.pbxproj'} with {len(SOURCES)} Swift files")


if __name__ == "__main__":
    main()
