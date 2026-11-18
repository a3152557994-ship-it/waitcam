#!/usr/bin/env python3
"""Generate deterministic WaitCam.xcodeproj for iOS 18+ App, Widget Extension, and XCTest bundle."""

from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJ_DIR = ROOT / "WaitCam.xcodeproj"
PROJ_DIR.mkdir(parents=True, exist_ok=True)


def uid(tag: str) -> str:
    return hashlib.md5(f"waitcam::{tag}".encode("utf-8")).hexdigest()[:24].upper()


def rel_sources(subdir: str, ext: str = ".swift") -> list[str]:
    base = ROOT / subdir
    if not base.exists():
        return []
    return sorted([p.relative_to(ROOT).as_posix() for p in base.rglob(f"*{ext}")])


def main() -> None:
    shared_sources = rel_sources("Sources/Shared", ".swift")
    app_only_sources = [s for s in rel_sources("Sources", ".swift") if s not in shared_sources]
    app_sources = sorted(shared_sources + app_only_sources)
    widget_sources = sorted(shared_sources + rel_sources("Widgets", ".swift"))
    test_sources = rel_sources("Tests", ".swift")

    asset_catalog = "Resources/Assets.xcassets"
    privacy_manifest = "Resources/PrivacyInfo.xcprivacy"
    app_info_plist = "Config/Info.plist"
    widget_info_plist = "Config/Widget-Info.plist"
    app_entitlements = "Config/WaitCam.entitlements"
    widget_entitlements = "Config/WaitCamWidgets.entitlements"
    storekit_config = "Config/WaitCam.storekit"

    file_refs: dict[str, tuple[str, str, str, str]] = {}
    build_files: dict[str, tuple[str, str, str | None]] = {}

    def add_file(rel_path: str, file_type: str, name: str | None = None, path_attr: str | None = None) -> str:
        if rel_path in file_refs:
            return file_refs[rel_path][0]
        fid = uid(f"fileref::{rel_path}")
        file_refs[rel_path] = (fid, file_type, name or Path(rel_path).name, path_attr or rel_path)
        return fid

    for s in app_sources:
        fid = add_file(s, "sourcecode.swift")
        build_files[f"app_src::{s}"] = (uid(f"bf_app::{s}"), fid, None)

    for s in widget_sources:
        fid = add_file(s, "sourcecode.swift")
        build_files[f"widget_src::{s}"] = (uid(f"bf_widget::{s}"), fid, None)

    for s in test_sources:
        fid = add_file(s, "sourcecode.swift")
        build_files[f"test_src::{s}"] = (uid(f"bf_test::{s}"), fid, None)

    zh_strings_fid = add_file(
        "Resources/zh-Hans.lproj/InfoPlist.strings",
        "text.plist.strings",
        name="zh-Hans",
        path_attr="Resources/zh-Hans.lproj/InfoPlist.strings",
    )
    en_strings_fid = add_file(
        "Resources/en.lproj/InfoPlist.strings",
        "text.plist.strings",
        name="en",
        path_attr="Resources/en.lproj/InfoPlist.strings",
    )
    strings_vg_id = uid("variantgroup::InfoPlist.strings")
    build_files["app_res::InfoPlist.strings"] = (uid("bf_app_res::InfoPlist.strings"), strings_vg_id, None)

    assets_fid = add_file(asset_catalog, "folder.assetcatalog")
    build_files["app_res::Assets.xcassets"] = (uid("bf_app_res::Assets.xcassets"), assets_fid, None)

    privacy_fid = add_file(privacy_manifest, "text.xml")
    build_files["app_res::PrivacyInfo.xcprivacy"] = (uid("bf_app_res::PrivacyInfo.xcprivacy"), privacy_fid, None)
    build_files["widget_res::PrivacyInfo.xcprivacy"] = (uid("bf_widget_res::PrivacyInfo.xcprivacy"), privacy_fid, None)

    storekit_fid = add_file(storekit_config, "text.json")
    build_files["test_res::WaitCam.storekit"] = (uid("bf_test_res::WaitCam.storekit"), storekit_fid, None)

    add_file(app_info_plist, "text.plist.xml")
    add_file(widget_info_plist, "text.plist.xml")
    add_file(app_entitlements, "text.plist.entitlements")
    add_file(widget_entitlements, "text.plist.entitlements")

    app_product_id = uid("product::WaitCam.app")
    widget_product_id = uid("product::WaitCamWidgets.appex")
    test_product_id = uid("product::WaitCamTests.xctest")

    build_files["embed::WaitCamWidgets.appex"] = (
        uid("bf_embed::WaitCamWidgets.appex"),
        widget_product_id,
        "ATTRIBUTES = (RemoveHeadersOnCopy, );",
    )

    root_group_id = uid("group::root")
    sources_group_id = uid("group::Sources")
    widgets_group_id = uid("group::Widgets")
    tests_group_id = uid("group::Tests")
    resources_group_id = uid("group::Resources")
    config_group_id = uid("group::Config")
    products_group_id = uid("group::Products")

    app_sources_phase = uid("phase::app_sources")
    app_frameworks_phase = uid("phase::app_frameworks")
    app_resources_phase = uid("phase::app_resources")
    app_embed_phase = uid("phase::app_embed_extensions")

    widget_sources_phase = uid("phase::widget_sources")
    widget_frameworks_phase = uid("phase::widget_frameworks")
    widget_resources_phase = uid("phase::widget_resources")

    test_sources_phase = uid("phase::test_sources")
    test_frameworks_phase = uid("phase::test_frameworks")
    test_resources_phase = uid("phase::test_resources")

    project_id = uid("project::WaitCam")
    app_target_id = uid("target::WaitCam")
    widget_target_id = uid("target::WaitCamWidgets")
    test_target_id = uid("target::WaitCamTests")

    app_widget_dep_id = uid("target_dep::WaitCamWidgets")
    app_widget_proxy_id = uid("proxy::WaitCamWidgets")
    test_dep_id = uid("target_dep::WaitCam")
    test_proxy_id = uid("proxy::WaitCam")

    proj_cfg_list = uid("cfglist::project")
    app_cfg_list = uid("cfglist::app")
    widget_cfg_list = uid("cfglist::widget")
    test_cfg_list = uid("cfglist::test")

    proj_debug_cfg = uid("cfg::proj::Debug")
    proj_release_cfg = uid("cfg::proj::Release")
    app_debug_cfg = uid("cfg::app::Debug")
    app_release_cfg = uid("cfg::app::Release")
    widget_debug_cfg = uid("cfg::widget::Debug")
    widget_release_cfg = uid("cfg::widget::Release")
    test_debug_cfg = uid("cfg::test::Debug")
    test_release_cfg = uid("cfg::test::Release")

    lines: list[str] = []
    w = lines.append

    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {")
    w("\t};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")
    w("")

    # PBXBuildFile
    w("/* Begin PBXBuildFile section */")
    for key, (bf_id, f_id, settings) in sorted(build_files.items()):
        if settings:
            w(f"\t\t{bf_id} /* {key} */ = {{isa = PBXBuildFile; fileRef = {f_id}; settings = {{{settings} }}; }};")
        else:
            w(f"\t\t{bf_id} /* {key} */ = {{isa = PBXBuildFile; fileRef = {f_id}; }};")
    w("/* End PBXBuildFile section */")
    w("")

    # PBXContainerItemProxy
    w("/* Begin PBXContainerItemProxy section */")
    w(f"\t\t{app_widget_proxy_id} /* PBXContainerItemProxy */ = {{")
    w("\t\t\tisa = PBXContainerItemProxy;")
    w(f"\t\t\tcontainerPortal = {project_id};")
    w("\t\t\tproxyType = 1;")
    w(f"\t\t\tremoteGlobalIDString = {widget_target_id};")
    w("\t\t\tremoteInfo = WaitCamWidgets;")
    w("\t\t};")
    w(f"\t\t{test_proxy_id} /* PBXContainerItemProxy */ = {{")
    w("\t\t\tisa = PBXContainerItemProxy;")
    w(f"\t\t\tcontainerPortal = {project_id};")
    w("\t\t\tproxyType = 1;")
    w(f"\t\t\tremoteGlobalIDString = {app_target_id};")
    w("\t\t\tremoteInfo = WaitCam;")
    w("\t\t};")
    w("/* End PBXContainerItemProxy section */")
    w("")

    # PBXCopyFilesBuildPhase
    w("/* Begin PBXCopyFilesBuildPhase section */")
    w(f"\t\t{app_embed_phase} /* Embed Foundation Extensions */ = {{")
    w("\t\t\tisa = PBXCopyFilesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tdstPath = \"\";")
    w("\t\t\tdstSubfolderSpec = 13;")
    w("\t\t\tfiles = (")
    w(f"\t\t\t\t{build_files['embed::WaitCamWidgets.appex'][0]} /* WaitCamWidgets.appex in Embed Foundation Extensions */,")
    w("\t\t\t);")
    w("\t\t\tname = \"Embed Foundation Extensions\";")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXCopyFilesBuildPhase section */")
    w("")

    # PBXFileReference
    w("/* Begin PBXFileReference section */")
    w(f"\t\t{app_product_id} /* WaitCam.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = WaitCam.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    w(f"\t\t{widget_product_id} /* WaitCamWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = WaitCamWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};")
    w(f"\t\t{test_product_id} /* WaitCamTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = WaitCamTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for rel_path, (fid, ftype, fname, path_attr) in sorted(file_refs.items()):
        w(f"\t\t{fid} /* {rel_path} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = \"{fname}\"; path = \"{path_attr}\"; sourceTree = SOURCE_ROOT; }};")
    w("/* End PBXFileReference section */")
    w("")

    # PBXFrameworksBuildPhase
    w("/* Begin PBXFrameworksBuildPhase section */")
    w(f"\t\t{app_frameworks_phase} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")
    w(f"\t\t{widget_frameworks_phase} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")
    w(f"\t\t{test_frameworks_phase} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};")
    w("/* End PBXFrameworksBuildPhase section */")
    w("")

    # PBXGroup
    w("/* Begin PBXGroup section */")
    w(f"\t\t{root_group_id} = {{")
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{sources_group_id} /* Sources */,")
    w(f"\t\t\t\t{widgets_group_id} /* Widgets */,")
    w(f"\t\t\t\t{tests_group_id} /* Tests */,")
    w(f"\t\t\t\t{resources_group_id} /* Resources */,")
    w(f"\t\t\t\t{config_group_id} /* Config */,")
    w(f"\t\t\t\t{products_group_id} /* Products */,")
    w("\t\t\t);")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")

    def emit_group(gid: str, name: str, child_ids: list[tuple[str, str]]) -> None:
        w(f"\t\t{gid} /* {name} */ = {{")
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for cid, cname in child_ids:
            w(f"\t\t\t\t{cid} /* {cname} */,")
        w("\t\t\t);")
        w(f"\t\t\tname = {name};")
        w("\t\t\tsourceTree = \"<group>\";")
        w("\t\t};")

    emit_group(sources_group_id, "Sources", [(file_refs[s][0], s) for s in app_sources])
    emit_group(widgets_group_id, "Widgets", [(file_refs[s][0], s) for s in rel_sources("Widgets", ".swift")])
    emit_group(tests_group_id, "Tests", [(file_refs[s][0], s) for s in test_sources])
    emit_group(resources_group_id, "Resources", [
        (assets_fid, "Assets.xcassets"),
        (privacy_fid, "PrivacyInfo.xcprivacy"),
        (strings_vg_id, "InfoPlist.strings"),
    ])
    emit_group(config_group_id, "Config", [
        (file_refs[app_info_plist][0], "Info.plist"),
        (file_refs[widget_info_plist][0], "Widget-Info.plist"),
        (file_refs[app_entitlements][0], "WaitCam.entitlements"),
        (file_refs[widget_entitlements][0], "WaitCamWidgets.entitlements"),
        (storekit_fid, "WaitCam.storekit"),
    ])
    emit_group(products_group_id, "Products", [
        (app_product_id, "WaitCam.app"),
        (widget_product_id, "WaitCamWidgets.appex"),
        (test_product_id, "WaitCamTests.xctest"),
    ])
    w("/* End PBXGroup section */")
    w("")

    # PBXNativeTarget
    w("/* Begin PBXNativeTarget section */")
    w(f"\t\t{app_target_id} /* WaitCam */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {app_cfg_list};")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{app_sources_phase} /* Sources */,")
    w(f"\t\t\t\t{app_frameworks_phase} /* Frameworks */,")
    w(f"\t\t\t\t{app_resources_phase} /* Resources */,")
    w(f"\t\t\t\t{app_embed_phase} /* Embed Foundation Extensions */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = ();")
    w(f"\t\t\tdependencies = ({app_widget_dep_id} /* PBXTargetDependency */);")
    w("\t\t\tname = WaitCam;")
    w("\t\t\tproductName = WaitCam;")
    w(f"\t\t\tproductReference = {app_product_id} /* WaitCam.app */;")
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")

    w(f"\t\t{widget_target_id} /* WaitCamWidgets */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {widget_cfg_list};")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{widget_sources_phase} /* Sources */,")
    w(f"\t\t\t\t{widget_frameworks_phase} /* Frameworks */,")
    w(f"\t\t\t\t{widget_resources_phase} /* Resources */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = ();")
    w("\t\t\tdependencies = ();")
    w("\t\t\tname = WaitCamWidgets;")
    w("\t\t\tproductName = WaitCamWidgets;")
    w(f"\t\t\tproductReference = {widget_product_id} /* WaitCamWidgets.appex */;")
    w("\t\t\tproductType = \"com.apple.product-type.app-extension\";")
    w("\t\t};")

    w(f"\t\t{test_target_id} /* WaitCamTests */ = {{")
    w("\t\t\tisa = PBXNativeTarget;")
    w(f"\t\t\tbuildConfigurationList = {test_cfg_list};")
    w("\t\t\tbuildPhases = (")
    w(f"\t\t\t\t{test_sources_phase} /* Sources */,")
    w(f"\t\t\t\t{test_frameworks_phase} /* Frameworks */,")
    w(f"\t\t\t\t{test_resources_phase} /* Resources */,")
    w("\t\t\t);")
    w("\t\t\tbuildRules = ();")
    w(f"\t\t\tdependencies = ({test_dep_id} /* PBXTargetDependency */);")
    w("\t\t\tname = WaitCamTests;")
    w("\t\t\tproductName = WaitCamTests;")
    w(f"\t\t\tproductReference = {test_product_id} /* WaitCamTests.xctest */;")
    w("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    w("\t\t};")
    w("/* End PBXNativeTarget section */")
    w("")

    # PBXProject
    w("/* Begin PBXProject section */")
    w(f"\t\t{project_id} /* Project object */ = {{")
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastUpgradeCheck = 2720;")
    w("\t\t\t\tTargetAttributes = {")
    w(f"\t\t\t\t\t{app_target_id} = {{ CreatedOnToolsVersion = 27.2; }};")
    w(f"\t\t\t\t\t{widget_target_id} = {{ CreatedOnToolsVersion = 27.2; }};")
    w(f"\t\t\t\t\t{test_target_id} = {{ CreatedOnToolsVersion = 27.2; TestTargetID = {app_target_id}; }};")
    w("\t\t\t\t};")
    w("\t\t\t};")
    w(f"\t\t\tbuildConfigurationList = {proj_cfg_list};")
    w("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    w("\t\t\tdevelopmentRegion = \"zh-Hans\";")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (\"zh-Hans\", en, Base);")
    w(f"\t\t\tmainGroup = {root_group_id};")
    w(f"\t\t\tproductRefGroup = {products_group_id} /* Products */;")
    w("\t\t\tprojectDirPath = \"\";")
    w("\t\t\tprojectRoot = \"\";")
    w("\t\t\ttargets = (")
    w(f"\t\t\t\t{app_target_id} /* WaitCam */,")
    w(f"\t\t\t\t{widget_target_id} /* WaitCamWidgets */,")
    w(f"\t\t\t\t{test_target_id} /* WaitCamTests */,")
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")
    w("")

    # PBXResourcesBuildPhase
    w("/* Begin PBXResourcesBuildPhase section */")
    w(f"\t\t{app_resources_phase} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for k in ["app_res::Assets.xcassets", "app_res::PrivacyInfo.xcprivacy", "app_res::InfoPlist.strings"]:
        w(f"\t\t\t\t{build_files[k][0]} /* {k} */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")

    w(f"\t\t{widget_resources_phase} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w(f"\t\t\t\t{build_files['widget_res::PrivacyInfo.xcprivacy'][0]} /* widget_res::PrivacyInfo.xcprivacy */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")

    w(f"\t\t{test_resources_phase} /* Resources */ = {{")
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    w(f"\t\t\t\t{build_files['test_res::WaitCam.storekit'][0]} /* test_res::WaitCam.storekit */,")
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")
    w("")

    # PBXSourcesBuildPhase
    w("/* Begin PBXSourcesBuildPhase section */")
    for phase_id, prefix, items in [
        (app_sources_phase, "app_src", app_sources),
        (widget_sources_phase, "widget_src", widget_sources),
        (test_sources_phase, "test_src", test_sources),
    ]:
        w(f"\t\t{phase_id} /* Sources */ = {{")
        w("\t\t\tisa = PBXSourcesBuildPhase;")
        w("\t\t\tbuildActionMask = 2147483647;")
        w("\t\t\tfiles = (")
        for s in items:
            w(f"\t\t\t\t{build_files[f'{prefix}::{s}'][0]} /* {s} */,")
        w("\t\t\t);")
        w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")
    w("")

    # PBXTargetDependency
    w("/* Begin PBXTargetDependency section */")
    w(f"\t\t{app_widget_dep_id} /* PBXTargetDependency */ = {{")
    w("\t\t\tisa = PBXTargetDependency;")
    w(f"\t\t\ttarget = {widget_target_id} /* WaitCamWidgets */;")
    w(f"\t\t\ttargetProxy = {app_widget_proxy_id} /* PBXContainerItemProxy */;")
    w("\t\t};")
    w(f"\t\t{test_dep_id} /* PBXTargetDependency */ = {{")
    w("\t\t\tisa = PBXTargetDependency;")
    w(f"\t\t\ttarget = {app_target_id} /* WaitCam */;")
    w(f"\t\t\ttargetProxy = {test_proxy_id} /* PBXContainerItemProxy */;")
    w("\t\t};")
    w("/* End PBXTargetDependency section */")
    w("")

    # PBXVariantGroup
    w("/* Begin PBXVariantGroup section */")
    w(f"\t\t{strings_vg_id} /* InfoPlist.strings */ = {{")
    w("\t\t\tisa = PBXVariantGroup;")
    w("\t\t\tchildren = (")
    w(f"\t\t\t\t{zh_strings_fid} /* zh-Hans */,")
    w(f"\t\t\t\t{en_strings_fid} /* en */,")
    w("\t\t\t);")
    w("\t\t\tname = InfoPlist.strings;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w("/* End PBXVariantGroup section */")
    w("")

    # XCBuildConfiguration
    w("/* Begin XCBuildConfiguration section */")
    common_proj = [
        'ALWAYS_SEARCH_USER_PATHS = NO',
        'CLANG_ENABLE_MODULES = YES',
        'CLANG_ENABLE_OBJC_ARC = YES',
        'CODE_SIGN_STYLE = Automatic',
        'DEVELOPMENT_TEAM = KU364788TC',
        'ENABLE_STRICT_OBJC_MSGSEND = YES',
        'IPHONEOS_DEPLOYMENT_TARGET = 18.0',
        'MARKETING_VERSION = 1.0.0',
        'CURRENT_PROJECT_VERSION = 1',
        'SDKROOT = iphoneos',
        'SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"',
        'SWIFT_VERSION = 5.0',
        'TARGETED_DEVICE_FAMILY = "1,2"',
    ]

    def emit_cfg(cid: str, name: str, settings: list[str]) -> None:
        w(f"\t\t{cid} /* {name} */ = {{")
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        for line in settings:
            w(f"\t\t\t\t{line};")
        w("\t\t\t};")
        w(f"\t\t\tname = {name};")
        w("\t\t};")

    emit_cfg(proj_debug_cfg, "Debug", common_proj + [
        'DEBUG_INFORMATION_FORMAT = dwarf',
        'ENABLE_TESTABILITY = YES',
        'GCC_OPTIMIZATION_LEVEL = 0',
        'ONLY_ACTIVE_ARCH = YES',
        'SWIFT_OPTIMIZATION_LEVEL = "-Onone"',
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG"',
    ])
    emit_cfg(proj_release_cfg, "Release", common_proj + [
        'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"',
        'ENABLE_NS_ASSERTIONS = NO',
        'SWIFT_OPTIMIZATION_LEVEL = "-O"',
        'VALIDATE_PRODUCT = YES',
    ])

    app_common = [
        'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon',
        'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor',
        'CODE_SIGN_ENTITLEMENTS = "Config/WaitCam.entitlements"',
        'CODE_SIGN_IDENTITY = "Apple Development"',
        'GENERATE_INFOPLIST_FILE = NO',
        'INFOPLIST_FILE = "Config/Info.plist"',
        'LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks"',
        'PRODUCT_BUNDLE_IDENTIFIER = com.yanghe.waitcam',
        'PRODUCT_NAME = WaitCam',
        'SWIFT_EMIT_LOC_STRINGS = YES',
    ]
    emit_cfg(app_debug_cfg, "Debug", app_common)
    emit_cfg(app_release_cfg, "Release", app_common)

    widget_common = [
        'APPLICATION_EXTENSION_API_ONLY = YES',
        'CODE_SIGN_ENTITLEMENTS = "Config/WaitCamWidgets.entitlements"',
        'CODE_SIGN_IDENTITY = "Apple Development"',
        'GENERATE_INFOPLIST_FILE = NO',
        'INFOPLIST_FILE = "Config/Widget-Info.plist"',
        'LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks"',
        'PRODUCT_BUNDLE_IDENTIFIER = com.yanghe.waitcam.widgets',
        'PRODUCT_NAME = "$(TARGET_NAME)"',
        'SKIP_INSTALL = YES',
        'SWIFT_EMIT_LOC_STRINGS = YES',
    ]
    emit_cfg(widget_debug_cfg, "Debug", widget_common)
    emit_cfg(widget_release_cfg, "Release", widget_common)

    test_common = [
        'BUNDLE_LOADER = "$(TEST_HOST)"',
        'GENERATE_INFOPLIST_FILE = YES',
        'LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"',
        'PRODUCT_BUNDLE_IDENTIFIER = com.yanghe.waitcam.tests',
        'PRODUCT_NAME = "$(TARGET_NAME)"',
        'TEST_HOST = "$(BUILT_PRODUCTS_DIR)/WaitCam.app/WaitCam"',
    ]
    emit_cfg(test_debug_cfg, "Debug", test_common)
    emit_cfg(test_release_cfg, "Release", test_common)
    w("/* End XCBuildConfiguration section */")
    w("")

    # XCConfigurationList
    w("/* Begin XCConfigurationList section */")
    for list_id, label, d_id, r_id, def_name in [
        (proj_cfg_list, "PBXProject WaitCam", proj_debug_cfg, proj_release_cfg, "Release"),
        (app_cfg_list, "PBXNativeTarget WaitCam", app_debug_cfg, app_release_cfg, "Release"),
        (widget_cfg_list, "PBXNativeTarget WaitCamWidgets", widget_debug_cfg, widget_release_cfg, "Release"),
        (test_cfg_list, "PBXNativeTarget WaitCamTests", test_debug_cfg, test_release_cfg, "Release"),
    ]:
        w(f"\t\t{list_id} /* Build configuration list for {label} */ = {{")
        w("\t\t\tisa = XCConfigurationList;")
        w("\t\t\tbuildConfigurations = (")
        w(f"\t\t\t\t{d_id} /* Debug */,")
        w(f"\t\t\t\t{r_id} /* Release */,")
        w("\t\t\t);")
        w("\t\t\tdefaultConfigurationIsVisible = 0;")
        w(f"\t\t\tdefaultConfigurationName = {def_name};")
        w("\t\t};")
    w("/* End XCConfigurationList section */")
    w("\t};")
    w(f"\trootObject = {project_id} /* Project object */;")
    w("}")

    (PROJ_DIR / "project.pbxproj").write_text("\n".join(lines) + "\n", encoding="utf-8")

    schemes_dir = PROJ_DIR / "xcshareddata" / "xcschemes"
    schemes_dir.mkdir(parents=True, exist_ok=True)
    scheme_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2720"
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
               BlueprintIdentifier = "{app_target_id}"
               BuildableName = "WaitCam.app"
               BlueprintName = "WaitCam"
               ReferencedContainer = "container:WaitCam.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{widget_target_id}"
               BuildableName = "WaitCamWidgets.appex"
               BlueprintName = "WaitCamWidgets"
               ReferencedContainer = "container:WaitCam.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{test_target_id}"
               BuildableName = "WaitCamTests.xctest"
               BlueprintName = "WaitCamTests"
               ReferencedContainer = "container:WaitCam.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
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
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target_id}"
            BuildableName = "WaitCam.app"
            BlueprintName = "WaitCam"
            ReferencedContainer = "container:WaitCam.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <StoreKitConfigurationFileReference
         identifier = "../../Config/WaitCam.storekit">
      </StoreKitConfigurationFileReference>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_target_id}"
            BuildableName = "WaitCam.app"
            BlueprintName = "WaitCam"
            ReferencedContainer = "container:WaitCam.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
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
    (schemes_dir / "WaitCam.xcscheme").write_text(scheme_xml, encoding="utf-8")
    print(
        f"Generated {PROJ_DIR}: {len(app_sources)} app sources, "
        f"{len(widget_sources)} widget sources, {len(test_sources)} test sources."
    )


if __name__ == "__main__":
    main()
