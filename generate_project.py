#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project (Python standard library only)."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def ident(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()


def main():
    sources = sorted(str(p.relative_to(ROOT)) for folder in ("App", "Sources") for p in (ROOT / folder).rglob("*.swift"))
    ui_sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / "UITests").glob("*.swift"))
    resources = ["App/Assets.xcassets", "App/PrivacyInfo.xcprivacy", "App/InfoPlist.strings"]
    objects = []

    def put(key, value):
        objects.append(f"\t\t{ident(key)} = {{ {value} }};")
        return ident(key)

    refs = []
    for name in sources + resources + ui_sources:
        if name == "App/InfoPlist.strings":
            children = []
            for language in ("en",):
                path = f"App/{language}.lproj/InfoPlist.strings"
                children.append(put(path, f'isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = {language}; path = {json.dumps(path)}; sourceTree = "<group>";'))
            refs.append(put(name, f'isa = PBXVariantGroup; children = ({",".join(children)},); name = InfoPlist.strings; sourceTree = "<group>";'))
            put("build:" + name, f"isa = PBXBuildFile; fileRef = {ident(name)};")
            continue
        kind = "sourcecode.swift" if name.endswith(".swift") else "text.xml" if name.endswith(".xcprivacy") else "folder.assetcatalog"
        refs.append(put(name, f"isa = PBXFileReference; lastKnownFileType = {kind}; path = {json.dumps(name)}; sourceTree = \"<group>\";"))
        put("build:" + name, f"isa = PBXBuildFile; fileRef = {ident(name)};")
    put("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = "Tankarr Reader.app"; sourceTree = BUILT_PRODUCTS_DIR;')
    put("uiProduct", 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = TankarrReaderUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    put("products", f'isa = PBXGroup; children = ({ident("product")},{ident("uiProduct")},); name = Products; sourceTree = "<group>";')
    put("root", f'isa = PBXGroup; children = ({",".join(refs + [ident("products")])},); sourceTree = "<group>";')
    for phase, names in (("Sources", sources), ("Resources", resources), ("Frameworks", [])):
        files = ",".join(ident("build:" + x) for x in names)
        put(phase, f"isa = PBX{phase}BuildPhase; buildActionMask = 2147483647; files = ({files}{',' if files else ''}); runOnlyForDeploymentPostprocessing = 0;")
    for phase, names in (("Sources", ui_sources), ("Resources", []), ("Frameworks", [])):
        files = ",".join(ident("build:" + x) for x in names)
        put("ui" + phase, f"isa = PBX{phase}BuildPhase; buildActionMask = 2147483647; files = ({files}{',' if files else ''}); runOnlyForDeploymentPostprocessing = 0;")
    for config in ("Debug", "Release"):
        project = 'CLANG_ENABLE_MODULES = YES; SDKROOT = iphoneos; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0;'
        project += ' DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_OPTIMIZATION_LEVEL = "-Onone";' if config == "Debug" else ' DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"; SWIFT_COMPILATION_MODE = wholemodule;'
        put("project:" + config, f"isa = XCBuildConfiguration; buildSettings = {{ {project} }}; name = {config};")
        target = '''PRODUCT_NAME = "Tankarr Reader"; PRODUCT_BUNDLE_IDENTIFIER = app.tankarr.reader;
            CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0.1;
            INFOPLIST_FILE = App/Info.plist; GENERATE_INFOPLIST_FILE = NO;
            TARGETED_DEVICE_FAMILY = "1,2"; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
            SUPPORTS_MACCATALYST = NO; ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
            ENABLE_USER_SCRIPT_SANDBOXING = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";'''
        target += ' CODE_SIGN_ENTITLEMENTS = App/Reader.entitlements;'
        target += ' APNS_ENVIRONMENT = development;' if config == "Debug" else ' APNS_ENVIRONMENT = production;'
        if config == "Debug":
            target += ' SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) DEBUG";'
        put("target:" + config, f"isa = XCBuildConfiguration; buildSettings = {{ {target} }}; name = {config};")
        ui_target = '''PRODUCT_NAME = TankarrReaderUITests; PRODUCT_BUNDLE_IDENTIFIER = app.tankarr.reader.uitests;
            GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_STYLE = Automatic; TARGETED_DEVICE_FAMILY = "1,2";
            SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; TEST_TARGET_NAME = "Tankarr Reader";
            LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks";'''
        put("ui:" + config, f"isa = XCBuildConfiguration; buildSettings = {{ {ui_target} }}; name = {config};")
    for prefix in ("project", "target", "ui"):
        put(prefix + "Configs", f"isa = XCConfigurationList; buildConfigurations = ({ident(prefix + ':Debug')},{ident(prefix + ':Release')},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;")
    put("target", f'''isa = PBXNativeTarget; buildConfigurationList = {ident("targetConfigs")};
        buildPhases = ({ident("Sources")},{ident("Frameworks")},{ident("Resources")},);
        buildRules = (); dependencies = (); name = "Tankarr Reader"; productName = "Tankarr Reader";
        productReference = {ident("product")}; productType = "com.apple.product-type.application";''')
    put("uiProxy", f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("target")}; remoteInfo = "Tankarr Reader";')
    put("uiDependency", f'isa = PBXTargetDependency; target = {ident("target")}; targetProxy = {ident("uiProxy")};')
    put("uiTarget", f'''isa = PBXNativeTarget; buildConfigurationList = {ident("uiConfigs")};
        buildPhases = ({ident("uiSources")},{ident("uiFrameworks")},{ident("uiResources")},);
        buildRules = (); dependencies = ({ident("uiDependency")},); name = TankarrReaderUITests;
        productName = TankarrReaderUITests; productReference = {ident("uiProduct")};
        productType = "com.apple.product-type.bundle.ui-testing";''')
    put("project", f'''isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }};
        buildConfigurationList = {ident("projectConfigs")}; compatibilityVersion = "Xcode 14.0";
        developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en,Base,);
        mainGroup = {ident("root")}; productRefGroup = {ident("products")}; projectDirPath = "";
        projectRoot = ""; targets = ({ident("target")},{ident("uiTarget")},);''')
    folder = ROOT / "TankarrReader.xcodeproj"
    folder.mkdir(exist_ok=True)
    (folder / "project.pbxproj").write_text("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n" + "\n".join(objects) + "\n\t};\n\trootObject = " + ident("project") + ";\n}\n")
    schemes = folder / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("target")}" BuildableName="Tankarr Reader.app" BlueprintName="Tankarr Reader" ReferencedContainer="container:TankarrReader.xcodeproj"/>'
    ui_reference = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident("uiTarget")}" BuildableName="TankarrReaderUITests.xctest" BlueprintName="TankarrReaderUITests" ReferencedContainer="container:TankarrReader.xcodeproj"/>'
    (schemes / "Tankarr Reader.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference}</BuildActionEntry><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="NO">{ui_reference}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{ui_reference}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')


if __name__ == "__main__":
    main()
