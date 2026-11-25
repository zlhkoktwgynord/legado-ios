#!/usr/bin/env python3
"""生成 LegadoIOS.xcodeproj（工程文件全部手写生成，便于在 Linux 上也保持一致）。

用法：python3 tools/gen_xcodeproj.py
"""
import hashlib
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_NAME = "LegadoIOS"
BUNDLE_ID = "com.legado.ios.reader"


def oid(key: str) -> str:
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def q(value: str) -> str:
    if value is None:
        return '""'
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


class Project:
    def __init__(self):
        self.objects = {}
        self.sections = {}

    def add(self, isa, key, props):
        identifier = oid(f"{isa}:{key}")
        entry = {"isa": isa}
        entry.update(props)
        self.objects[identifier] = entry
        self.sections.setdefault(isa, []).append(identifier)
        return identifier

    def render(self):
        lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {};",
                 "\tobjectVersion = 56;", "\tobjects = {"]
        for isa in sorted(self.sections):
            lines.append(f"\n/* Begin {isa} section */")
            for identifier in self.sections[isa]:
                entry = self.objects[identifier]
                body = []
                for key, value in entry.items():
                    if key == "isa":
                        continue
                    body.append(f"\t\t\t\t{key} = {self.format_value(value)};")
                lines.append(f"\t\t{identifier} /* {isa} */ = {{")
                lines.append(f"\t\t\tisa = {isa};")
                lines.extend(body)
                lines.append("\t\t};")
            lines.append(f"/* End {isa} section */")
        lines.append("\t};")
        lines.append(f"\trootObject = {self.root};")
        lines.append("}")
        lines.append("")
        return "\n".join(lines)

    @staticmethod
    def format_value(value):
        if isinstance(value, dict):
            inner = " ".join(f"{k} = {Project.format_value(v)};" for k, v in value.items())
            return "{ " + inner + " }"
        if isinstance(value, list):
            inner = ", ".join(Project.format_value(v) for v in value)
            return f"({inner})"
        if isinstance(value, bool):
            return "1" if value else "0"
        if isinstance(value, int):
            return str(value)
        text = str(value)
        if len(text) == 24 and all(c in "0123456789ABCDEF" for c in text):
            return text  # 对象 ID 不加引号
        return q(value)


def collect_swift_files():
    groups = {}
    for directory in ["App", "Core", "Models", "UI"]:
        path = os.path.join(ROOT, PROJECT_NAME, directory)
        files = sorted(f for f in os.listdir(path) if f.endswith(".swift"))
        groups[directory] = files
    vendor = os.path.join(ROOT, "Vendor", "SwiftSoup")
    groups["SwiftSoup"] = sorted(f for f in os.listdir(vendor) if f.endswith(".swift"))
    return groups


def build():
    project = Project()
    groups = collect_swift_files()

    # ---------- 文件引用 ----------
    file_refs = {}

    def file_ref(key, path, file_type, name=None):
        props = {
            "lastKnownFileType": file_type,
            "path": path,
            "sourceTree": "<group>",
        }
        if name:
            props["name"] = name
        identifier = project.add("PBXFileReference", key, props)
        file_refs[key] = identifier
        return identifier

    for directory, files in groups.items():
        for filename in files:
            file_ref(f"{directory}/{filename}", filename, "sourcecode.swift")

    asset_ref = project.add("PBXFileReference", "Assets.xcassets", {
        "lastKnownFileType": "folder.assetcatalog",
        "path": "Assets.xcassets",
        "sourceTree": "<group>",
    })
    info_ref = project.add("PBXFileReference", "Info.plist", {
        "lastKnownFileType": "text.plist.xml",
        "path": "Info.plist",
        "sourceTree": "<group>",
    })
    product_ref = project.add("PBXFileReference", "LegadoIOS.app", {
        "explicitFileType": "wrapper.application",
        "includeInIndex": 0,
        "path": f"{PROJECT_NAME}.app",
        "sourceTree": "BUILT_PRODUCTS_DIR",
    })

    # ---------- 分组 ----------
    group_ids = {}

    def make_group(name, children, path=None):
        props = {"children": children, "sourceTree": "<group>"}
        if path:
            props["path"] = path
        if name:
            props["name"] = name
        return project.add("PBXGroup", f"group:{name}:{path}", props)

    ui_children = [file_refs[f"UI/{f}"] for f in groups["UI"]]
    app_children = [file_refs[f"App/{f}"] for f in groups["App"]]
    core_children = [file_refs[f"Core/{f}"] for f in groups["Core"]]
    model_children = [file_refs[f"Models/{f}"] for f in groups["Models"]]
    soup_children = [file_refs[f"SwiftSoup/{f}"] for f in groups["SwiftSoup"]]

    ui_group = make_group("UI", ui_children, "UI")
    app_group = make_group("App", app_children, "App")
    core_group = make_group("Core", core_children, "Core")
    models_group = make_group("Models", model_children, "Models")
    resources_group = make_group("Resources", [asset_ref, info_ref], "Resources")
    soup_group = make_group("SwiftSoup", soup_children, "SwiftSoup")
    vendor_group = make_group("Vendor", [soup_group], "Vendor")
    app_root_group = make_group(PROJECT_NAME,
                                [app_group, core_group, models_group, ui_group, resources_group],
                                PROJECT_NAME)
    products_group = make_group("Products", [product_ref], None)
    main_group = make_group(None,
                            [app_root_group, vendor_group, products_group], None)

    # ---------- 编译文件 ----------
    source_build_files = []
    for directory, files in groups.items():
        for filename in files:
            ref = file_refs[f"{directory}/{filename}"]
            build_file = project.add("PBXBuildFile", f"build:{directory}/{filename}",
                                     {"fileRef": ref})
            source_build_files.append(build_file)

    asset_build_file = project.add("PBXBuildFile", "build:assets", {"fileRef": asset_ref})

    # ---------- 编译阶段 ----------
    sources_phase = project.add("PBXSourcesBuildPhase", "sources", {
        "buildActionMask": 2147483647,
        "files": source_build_files,
        "runOnlyForDeploymentPostprocessing": 0,
    })
    resources_phase = project.add("PBXResourcesBuildPhase", "resources", {
        "buildActionMask": 2147483647,
        "files": [asset_build_file],
        "runOnlyForDeploymentPostprocessing": 0,
    })
    frameworks_phase = project.add("PBXFrameworksBuildPhase", "frameworks", {
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0,
    })

    # ---------- 配置 ----------
    shared_settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "ENABLE_PREVIEWS": "YES",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": f"{PROJECT_NAME}/Resources/Info.plist",
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }

    debug_settings = dict(shared_settings)
    debug_settings.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    })

    release_settings = dict(shared_settings)
    release_settings.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "VALIDATE_PRODUCT": "YES",
    })

    def configuration_list(name, debug, release):
        debug_id = project.add("XCBuildConfiguration", f"config:{name}:Debug", {
            "buildSettings": debug,
            "name": "Debug",
        })
        release_id = project.add("XCBuildConfiguration", f"config:{name}:Release", {
            "buildSettings": release,
            "name": "Release",
        })
        return project.add("XCConfigurationList", f"configlist:{name}", {
            "buildConfigurations": [debug_id, release_id],
            "defaultConfigurationIsVisible": 0,
            "defaultConfigurationName": "Release",
        })

    project_settings = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_CXX_LANGUAGE_STANDARD": "gnu++20",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_UNDECLARED_SELECTOR": "YES",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_EMIT_LOC_STRINGS": "NO",
    }
    project_debug = dict(project_settings)
    project_debug.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    })
    project_release = dict(project_settings)
    project_release.update({
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": "-O",
        "VALIDATE_PRODUCT": "YES",
    })

    project_list = configuration_list("Project", project_debug, project_release)
    target_list = configuration_list("Target", debug_settings, release_settings)

    # ---------- 目标 ----------
    target = project.add("PBXNativeTarget", "target", {
        "buildConfigurationList": target_list,
        "buildPhases": [sources_phase, frameworks_phase, resources_phase],
        "buildRules": [],
        "dependencies": [],
        "name": PROJECT_NAME,
        "productName": PROJECT_NAME,
        "productReference": product_ref,
        "productType": "com.apple.product-type.application",
    })

    root = project.add("PBXProject", "project", {
        "attributes": {
            "BuildIndependentTargetsInParallel": "YES",
            "LastSwiftUpdateCheck": "1500",
            "LastUpgradeCheck": "1500",
            "TargetAttributes": {},
        },
        "buildConfigurationList": project_list,
        "compatibilityVersion": "Xcode 14.0",
        "developmentRegion": "zh-Hans",
        "hasScannedForEncodings": "0",
        "knownRegions": ["en", "Base", "zh-Hans"],
        "mainGroup": main_group,
        "productRefGroup": products_group,
        "projectDirPath": "",
        "projectRoot": "",
        "targets": [target],
    })
    project.root = root

    # ---------- 写文件 ----------
    path = os.path.join(ROOT, f"{PROJECT_NAME}.xcodeproj")
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "project.pbxproj"), "w", encoding="utf-8") as handle:
        handle.write(project.render())

    scheme_dir = os.path.join(path, "xcshareddata", "xcschemes")
    os.makedirs(scheme_dir, exist_ok=True)
    with open(os.path.join(scheme_dir, f"{PROJECT_NAME}.xcscheme"), "w",
              encoding="utf-8") as handle:
        handle.write(scheme(target, product_ref))

    print(f"已生成 {path}/project.pbxproj")
    print(f"源文件：{len(source_build_files)} 个")
    return path


def scheme(target, product_ref):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1500" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target}"
               BuildableName = "{PROJECT_NAME}.app"
               BlueprintName = "{PROJECT_NAME}"
               ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{PROJECT_NAME}.app"
            BlueprintName = "{PROJECT_NAME}"
            ReferencedContainer = "container:{PROJECT_NAME}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


if __name__ == "__main__":
    build()
