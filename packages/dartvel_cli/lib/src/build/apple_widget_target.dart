/// The Xcode target that builds the widget extension.
///
/// Generating Swift, an Info.plist and an entitlements file is the half that
/// is easy to be sure of. None of it is built by anything until the Xcode
/// project has a target for it, and adding one means writing into
/// `project.pbxproj` -- a file Xcode wrote, which a build tool is normally
/// told to leave alone.
///
/// It is done here anyway, because the alternative is a page of instructions
/// telling a developer to add a target by hand, which is the part of a
/// framework's job that a framework is for. What that costs is care about
/// the failure modes, and they are all quiet:
///
///   - a pbxproj Xcode cannot parse will not open. That one is loud, and it
///     is the only loud one.
///   - a target that exists as an object but is not in the project's target
///     list is never built. Nothing errors; the app installs without it.
///   - an extension with no Copy Files phase into PlugIns is built into the
///     products directory and never enters the `.app`.
///   - no target dependency lets Xcode build the app first and embed an
///     `.appex` that is not there yet, which fails on some machines and
///     passes on others.
///   - a second build that appends rather than replaces gives Xcode two
///     targets with one name.
///
/// Every object this adds carries [dvAppleWidgetIdPrefix] in its id, and
/// every reference to one does too, so removing the whole target again is
/// removing everything with that prefix in it. That is what makes a rewrite
/// idempotent and a project with the widgets taken away byte-identical to
/// the one before they were added -- which matters, because the pbxproj is
/// checked in and a build that rewrote it differently every time would be a
/// diff on every branch.
library;

import 'apple_home_widget.dart';

/// The prefix every generated object id carries.
///
/// Not a hash of anything: there is exactly one widget extension per
/// project, so fixed ids are deterministic by construction and readable in a
/// diff. The prefix is long enough that Xcode's own 24-hex ids will not
/// collide with it.
const String dvAppleWidgetIdPrefix = 'DA97E1DA97E1';

String _id(String suffix) => '$dvAppleWidgetIdPrefix$suffix';

/// The extension's PBXNativeTarget.
final String dvAppleWidgetTargetId = _id('000000000001');
final String _productRefId = _id('000000000002');
final String _swiftRefId = _id('000000000003');
final String _plistRefId = _id('000000000004');
final String _entitlementsRefId = _id('000000000005');
final String _groupId = _id('000000000006');
final String _sourcesPhaseId = _id('000000000007');
final String _swiftBuildFileId = _id('000000000008');
final String _appexBuildFileId = _id('000000000009');
final String _embedPhaseId = _id('00000000000A');
final String _targetDepId = _id('00000000000B');
final String _proxyId = _id('00000000000C');
final String _configListId = _id('00000000000D');
final String _debugConfigId = _id('00000000000E');
final String _releaseConfigId = _id('00000000000F');
final String _profileConfigId = _id('000000000010');

const String _appex = '$dvAppleWidgetExtensionName.appex';
const String _swift = '$dvAppleWidgetExtensionName.swift';
const String _entitlements = '$dvAppleWidgetExtensionName.entitlements';

/// [pbxproj] with the widget extension target in it, or without it.
///
/// [platform] is `ios` or `macos`: an app extension lives in a different
/// folder in each, and copying one across produces a bundle that builds and
/// is refused at launch.
String dvApplePbxprojWithWidgets(
  String pbxproj, {
  required bool hasWidgets,
  required String bundleId,
  required String platform,
}) {
  final String stripped = _strip(pbxproj);
  if (!hasWidgets) return stripped;

  final bool ios = platform == 'ios';
  final String group = dvAppleAppGroup(bundleId);
  final String extensionBundleId = '$bundleId.$dvAppleWidgetExtensionName';

  String out = stripped;

  out = _beforeSectionEnd(out, 'PBXBuildFile', <String>[
    '\t\t$_swiftBuildFileId /* $_swift in Sources */ = {isa = PBXBuildFile; '
        'fileRef = $_swiftRefId /* $_swift */; };',
    '\t\t$_appexBuildFileId /* $_appex in Embed App Extensions */ = '
        '{isa = PBXBuildFile; fileRef = $_productRefId /* $_appex */; '
        'settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };',
  ]);

  out = _beforeSectionEnd(out, 'PBXContainerItemProxy', <String>[
    '\t\t$_proxyId /* PBXContainerItemProxy */ = {',
    '\t\t\tisa = PBXContainerItemProxy;',
    '\t\t\tcontainerPortal = ${_projectObjectId(stripped)} /* Project object */;',
    '\t\t\tproxyType = 1;',
    '\t\t\tremoteGlobalIDString = $dvAppleWidgetTargetId;',
    '\t\t\tremoteInfo = $dvAppleWidgetExtensionName;',
    '\t\t};',
  ]);

  // dstSubfolderSpec 13 is PlugIns. Without this phase the .appex is built
  // and left in the products directory: the build succeeds and the widget
  // is not on the device.
  out = _beforeSectionEnd(out, 'PBXCopyFilesBuildPhase', <String>[
    '\t\t$_embedPhaseId /* Embed App Extensions */ = {',
    '\t\t\tisa = PBXCopyFilesBuildPhase;',
    '\t\t\tbuildActionMask = 2147483647;',
    '\t\t\tdstPath = "";',
    '\t\t\tdstSubfolderSpec = 13;',
    '\t\t\tfiles = (',
    '\t\t\t\t$_appexBuildFileId /* $_appex in Embed App Extensions */,',
    '\t\t\t);',
    '\t\t\tname = "Embed App Extensions";',
    '\t\t\trunOnlyForDeploymentPostprocessing = 0;',
    '\t\t};',
  ]);

  out = _beforeSectionEnd(out, 'PBXFileReference', <String>[
    '\t\t$_productRefId /* $_appex */ = {isa = PBXFileReference; '
        'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; '
        'path = $_appex; sourceTree = BUILT_PRODUCTS_DIR; };',
    '\t\t$_swiftRefId /* $_swift */ = {isa = PBXFileReference; '
        'lastKnownFileType = sourcecode.swift; path = $_swift; '
        'sourceTree = "<group>"; };',
    '\t\t$_plistRefId /* Info.plist */ = {isa = PBXFileReference; '
        'lastKnownFileType = text.plist.xml; path = Info.plist; '
        'sourceTree = "<group>"; };',
    '\t\t$_entitlementsRefId /* $_entitlements */ = {isa = PBXFileReference; '
        'lastKnownFileType = text.plist.entitlements; path = $_entitlements; '
        'sourceTree = "<group>"; };',
  ]);

  out = _beforeSectionEnd(out, 'PBXGroup', <String>[
    '\t\t$_groupId /* $dvAppleWidgetExtensionName */ = {',
    '\t\t\tisa = PBXGroup;',
    '\t\t\tchildren = (',
    '\t\t\t\t$_swiftRefId /* $_swift */,',
    '\t\t\t\t$_plistRefId /* Info.plist */,',
    '\t\t\t\t$_entitlementsRefId /* $_entitlements */,',
    '\t\t\t);',
    '\t\t\tpath = $dvAppleWidgetExtensionName;',
    '\t\t\tsourceTree = "<group>";',
    '\t\t};',
  ]);

  // Visible in the navigator, and the product filed with the others. A
  // group nobody can see is a target nobody can inspect when it misbehaves.
  out = _intoChildren(out, _mainGroupId(stripped),
      '\t\t\t\t$_groupId /* $dvAppleWidgetExtensionName */,');
  out = _intoChildren(
      out, _productsGroupId(stripped), '\t\t\t\t$_productRefId /* $_appex */,');

  out = _beforeSectionEnd(out, 'PBXNativeTarget', <String>[
    '\t\t$dvAppleWidgetTargetId /* $dvAppleWidgetExtensionName */ = {',
    '\t\t\tisa = PBXNativeTarget;',
    '\t\t\tbuildConfigurationList = $_configListId /* Build configuration '
        'list for PBXNativeTarget "$dvAppleWidgetExtensionName" */;',
    '\t\t\tbuildPhases = (',
    '\t\t\t\t$_sourcesPhaseId /* Sources */,',
    '\t\t\t);',
    '\t\t\tbuildRules = (',
    '\t\t\t);',
    '\t\t\tdependencies = (',
    '\t\t\t);',
    '\t\t\tname = $dvAppleWidgetExtensionName;',
    '\t\t\tproductName = $dvAppleWidgetExtensionName;',
    '\t\t\tproductReference = $_productRefId /* $_appex */;',
    '\t\t\tproductType = "com.apple.product-type.app-extension";',
    '\t\t};',
  ]);

  // Onto the application: the embed phase last, which is where Xcode puts
  // its own, and the dependency so the app waits for the extension rather
  // than racing it.
  final String? application = _applicationTargetId(stripped);
  if (application != null) {
    out = _intoList(out, application, 'buildPhases',
        '\t\t\t\t$_embedPhaseId /* Embed App Extensions */,');
    out = _intoList(out, application, 'dependencies',
        '\t\t\t\t$_targetDepId /* PBXTargetDependency */,');
  }

  out = _afterLineContaining(out, '\t\t\ttargets = (',
      '\t\t\t\t$dvAppleWidgetTargetId /* $dvAppleWidgetExtensionName */,');
  // One line, so removing it again is removing a line. A multi-line entry
  // would leave its body behind when the id line went.
  out = _afterLineContaining(out, 'TargetAttributes = {',
      '\t\t\t\t\t$dvAppleWidgetTargetId = {CreatedOnToolsVersion = 15.0; };');

  out = _beforeSectionEnd(out, 'PBXSourcesBuildPhase', <String>[
    '\t\t$_sourcesPhaseId /* Sources */ = {',
    '\t\t\tisa = PBXSourcesBuildPhase;',
    '\t\t\tbuildActionMask = 2147483647;',
    '\t\t\tfiles = (',
    '\t\t\t\t$_swiftBuildFileId /* $_swift in Sources */,',
    '\t\t\t);',
    '\t\t\trunOnlyForDeploymentPostprocessing = 0;',
    '\t\t};',
  ]);

  out = _beforeSectionEnd(out, 'PBXTargetDependency', <String>[
    '\t\t$_targetDepId /* PBXTargetDependency */ = {',
    '\t\t\tisa = PBXTargetDependency;',
    '\t\t\ttarget = $dvAppleWidgetTargetId /* $dvAppleWidgetExtensionName */;',
    '\t\t\ttargetProxy = $_proxyId /* PBXContainerItemProxy */;',
    '\t\t};',
  ]);

  List<String> configuration(String id, String name) => <String>[
        '\t\t$id /* $name */ = {',
        '\t\t\tisa = XCBuildConfiguration;',
        '\t\t\tbuildSettings = {',
        '\t\t\t\tCODE_SIGN_ENTITLEMENTS = '
            '$dvAppleWidgetExtensionName/$_entitlements;',
        '\t\t\t\tCODE_SIGN_STYLE = Automatic;',
        '\t\t\t\tCURRENT_PROJECT_VERSION = 1;',
        // The App Group, as a build setting because the Info.plist reads it
        // back and the Swift reads the plist. It is per application and the
        // generated sources are not.
        '\t\t\t\t$dvAppleAppGroupSetting = $group;',
        '\t\t\t\tGENERATE_INFOPLIST_FILE = NO;',
        '\t\t\t\tINFOPLIST_FILE = $dvAppleWidgetExtensionName/Info.plist;',
        if (ios) '\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 14.0;',
        if (!ios) '\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 11.0;',
        '\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "\$(inherited) '
            '@executable_path/Frameworks @executable_path/../../Frameworks";',
        '\t\t\t\tMARKETING_VERSION = 1.0;',
        // Under the application's own, which is what Apple requires. An
        // extension whose identifier is not prefixed by the containing
        // app's is refused at submission, months after it built.
        '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = $extensionBundleId;',
        '\t\t\t\tPRODUCT_NAME = "\$(TARGET_NAME)";',
        '\t\t\t\tSDKROOT = ${ios ? 'iphoneos' : 'macosx'};',
        // Not installed on its own: it ships inside the application, and a
        // target that installs itself is a second copy in the archive.
        '\t\t\t\tSKIP_INSTALL = YES;',
        '\t\t\t\tSWIFT_VERSION = 5.0;',
        if (ios) '\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";',
        '\t\t\t};',
        '\t\t\tname = $name;',
        '\t\t};',
      ];

  out = _beforeSectionEnd(out, 'XCBuildConfiguration', <String>[
    ...configuration(_debugConfigId, 'Debug'),
    ...configuration(_releaseConfigId, 'Release'),
    // Flutter's own projects carry a Profile configuration, and a target
    // that does not have one is skipped by `flutter build --profile` with a
    // message about the scheme rather than about this.
    ...configuration(_profileConfigId, 'Profile'),
  ]);

  out = _beforeSectionEnd(out, 'XCConfigurationList', <String>[
    '\t\t$_configListId /* Build configuration list for PBXNativeTarget '
        '"$dvAppleWidgetExtensionName" */ = {',
    '\t\t\tisa = XCConfigurationList;',
    '\t\t\tbuildConfigurations = (',
    '\t\t\t\t$_debugConfigId /* Debug */,',
    '\t\t\t\t$_releaseConfigId /* Release */,',
    '\t\t\t\t$_profileConfigId /* Profile */,',
    '\t\t\t);',
    '\t\t\tdefaultConfigurationIsVisible = 0;',
    '\t\t\tdefaultConfigurationName = Release;',
    '\t\t};',
  ]);

  return out;
}

/// [pbxproj] with everything this ever wrote taken back out.
///
/// Walked line by line rather than matched as a pattern, because the two
/// shapes an object comes in are not one pattern: a build file or a file
/// reference is written on one line, and everything else is a block whose
/// inner lines do not carry the prefix at all. A regular expression that
/// reached from the first of those to the next closing brace would take
/// every unrelated object between them with it.
String _strip(String pbxproj) {
  final List<String> kept = <String>[];
  bool inObject = false;
  for (final String line in pbxproj.split('\n')) {
    if (inObject) {
      // An object ends at the only closing brace written at its own depth.
      // Everything nested inside it is indented deeper than this.
      if (line == '\t\t};') inObject = false;
      continue;
    }
    if (!line.contains(dvAppleWidgetIdPrefix)) {
      kept.add(line);
      continue;
    }
    // A generated object opens at two tabs. A reference to one is nested
    // deeper, and a single-line object closes on the line it opened on --
    // so only the first of those starts a block to skip.
    final bool opens = line.startsWith('\t\t') &&
        !line.startsWith('\t\t\t') &&
        !line.endsWith('};');
    if (opens) inObject = true;
  }
  return kept.join('\n');
}

/// [lines] inserted just before `/* End [section] section */`.
String _beforeSectionEnd(String pbxproj, String section, List<String> lines) {
  final String end = '/* End $section section */';
  final int at = pbxproj.indexOf(end);
  if (at < 0) return pbxproj;
  return '${pbxproj.substring(0, at)}${lines.join('\n')}\n'
      '${pbxproj.substring(at)}';
}

/// [line] inserted after the first line containing [needle].
String _afterLineContaining(String pbxproj, String needle, String line) {
  final int at = pbxproj.indexOf(needle);
  if (at < 0) return pbxproj;
  final int eol = pbxproj.indexOf('\n', at);
  if (eol < 0) return pbxproj;
  return '${pbxproj.substring(0, eol + 1)}$line\n${pbxproj.substring(eol + 1)}';
}

/// [entry] added to the `children = (` of the object with [objectId].
String _intoChildren(String pbxproj, String? objectId, String entry) =>
    objectId == null ? pbxproj : _intoList(pbxproj, objectId, 'children', entry);

/// [entry] added to the end of `[key] = (` inside the object with [objectId].
///
/// At the end rather than the start: an embed phase belongs after the phases
/// that produce what it embeds, which is also where Xcode puts its own.
String _intoList(String pbxproj, String objectId, String key, String entry) {
  final int object = pbxproj.indexOf('\t\t$objectId ');
  if (object < 0) return pbxproj;
  final int list = pbxproj.indexOf('$key = (', object);
  if (list < 0) return pbxproj;
  final int close = pbxproj.indexOf('\t\t\t);', list);
  if (close < 0) return pbxproj;
  return '${pbxproj.substring(0, close)}$entry\n${pbxproj.substring(close)}';
}

/// The `PBXProject` object's own id.
String _projectObjectId(String pbxproj) =>
    RegExp(r'rootObject = ([0-9A-F]{24})').firstMatch(pbxproj)?.group(1) ?? '';

String? _mainGroupId(String pbxproj) =>
    RegExp(r'mainGroup = ([0-9A-F]{24})').firstMatch(pbxproj)?.group(1);

String? _productsGroupId(String pbxproj) =>
    RegExp(r'productRefGroup = ([0-9A-F]{24})').firstMatch(pbxproj)?.group(1);

/// The id of the target that builds the `.app`.
///
/// Found by its product type rather than by its name, because the target is
/// called Runner in a Flutter project and a renamed one is still the
/// application the extension has to be embedded in.
String? _applicationTargetId(String pbxproj) {
  final RegExp target = RegExp(
      r'\t\t([0-9A-F]{24}) /\*.*?\*/ = \{\n\t\t\tisa = PBXNativeTarget;'
      r'.*?\n\t\t\};',
      dotAll: true);
  for (final RegExpMatch match in target.allMatches(pbxproj)) {
    if (match.group(0)!.contains('com.apple.product-type.application')) {
      return match.group(1);
    }
  }
  return null;
}
