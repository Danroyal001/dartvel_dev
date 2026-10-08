/// `dartvel.scene3d.enabled`, written into each platform's own files at build
/// time: Flutter GPU, which Flutter Scene renders through, is off by default
/// on every native platform and switched on per platform file.
///
/// Nothing here asks a developer to edit `android/`, `ios/`, `macos/`,
/// `linux/` or `windows/`. What goes in is a marked block a later build
/// replaces, and turning `scene3d` off takes it back out. A declaration the
/// developer wrote themselves is theirs: the build leaves it alone and writes
/// no second copy. The web needs nothing: Flutter Scene's WebGL2 backend runs
/// without a flag.
library dartvel_cli.build.scene3d_native;

import 'package:yaml/yaml.dart';

/// Whether the `dartvel:` section turns 3D scenes on.
bool dvScene3dEnabled(Map<dynamic, dynamic> dartvel) {
  final Object? scene3d = dartvel['scene3d'];
  return scene3d is Map && scene3d['enabled'] == true;
}

/// Same, reading the YAML a pubspec gives.
bool dvScene3dEnabledIn(YamlMap? dartvel) => dartvel != null && dvScene3dEnabled(dartvel);

/// Why [pubspec] cannot build with `scene3d` on, or null when it can: the
/// generated runtime installs the renderer from `dartvel_scene`, so a project
/// that turns 3D on depends on it.
String? dvScene3dDependencyProblem(Object? pubspec) {
  if (pubspec is! Map) return null;
  final Object? dartvel = pubspec['dartvel'];
  if (dartvel is! Map || !dvScene3dEnabled(dartvel)) return null;
  final Object? dependencies = pubspec['dependencies'];
  if (dependencies is Map && dependencies.containsKey('dartvel_scene')) return null;
  return 'dartvel.scene3d.enabled is true, but dartvel_scene is not a dependency, '
      'so nothing can draw a DVBox.scene. Add it: dart pub add dartvel_scene';
}

const String _androidKey = 'io.flutter.embedding.android.EnableFlutterGPU';
const String _xmlStart = '<!-- dartvel.scene3d: begin -->';
const String _xmlEnd = '<!-- dartvel.scene3d: end -->';
const String _codeStart = '// dartvel.scene3d: begin';
const String _codeEnd = '// dartvel.scene3d: end';

/// Removes a marked block, with the line break before it and the indentation
/// it was written with.
String _strip(String source, String start, String end) =>
    source.replaceAll(RegExp('\n[ \t]*${RegExp.escape(start)}.*?${RegExp.escape(end)}', dotAll: true), '');

/// [manifest] with Flutter GPU declared inside `<application>` when [enabled].
String dvAndroidFlutterGpu(String manifest, {required bool enabled}) {
  final String stripped = _strip(manifest, _xmlStart, _xmlEnd);
  if (!enabled || stripped.contains(_androidKey)) return stripped;
  final RegExpMatch? application = RegExp(r'<application\b[^>]*>').firstMatch(stripped);
  if (application == null) return stripped;
  const String indent = '        ';
  final String block = '\n$indent$_xmlStart\n'
      '$indent<meta-data android:name="$_androidKey" android:value="true" />\n'
      '$indent$_xmlEnd';
  return stripped.replaceRange(application.end, application.end, block);
}

/// [plist] (an iOS or macOS Info.plist) with `FLTEnableFlutterGPU` set when
/// [enabled].
String dvAppleFlutterGpu(String plist, {required bool enabled}) {
  final String stripped = _strip(plist, _xmlStart, _xmlEnd);
  if (!enabled || stripped.contains('<key>FLTEnableFlutterGPU</key>')) return stripped;
  final int close = stripped.lastIndexOf('</dict>');
  if (close < 0) return stripped;
  // Inserted after the line before </dict>, so the block sits on lines of its
  // own and removing it restores the file byte for byte.
  final int lineEnd = stripped.lastIndexOf('\n', close);
  if (lineEnd < 0) return stripped;
  const String block = '\n\t$_xmlStart\n\t<key>FLTEnableFlutterGPU</key>\n\t<true/>\n\t$_xmlEnd';
  return stripped.replaceRange(lineEnd, lineEnd, block);
}

/// [runner] (`linux/runner/my_application.cc`) with Flutter GPU enabled on
/// the Dart project when [enabled]. Needs Flutter 3.47.1.
String dvLinuxFlutterGpu(String runner, {required bool enabled}) => _afterLine(
      runner,
      enabled: enabled,
      anchor: RegExp(r'^([ \t]*)g_autoptr\(FlDartProject\)\s*(\w+)\s*=\s*fl_dart_project_new\(\);[^\n]*$', multiLine: true),
      already: 'fl_dart_project_set_enable_flutter_gpu',
      line: (String project) => 'fl_dart_project_set_enable_flutter_gpu($project, TRUE);',
    );

/// [runner] (`windows/runner/main.cpp`) with Flutter GPU enabled on the
/// DartProject when [enabled]. Needs Flutter 3.47.1.
String dvWindowsFlutterGpu(String runner, {required bool enabled}) => _afterLine(
      runner,
      enabled: enabled,
      anchor: RegExp(r'^([ \t]*)flutter::DartProject\s+(\w+)\([^)]*\);[^\n]*$', multiLine: true),
      already: 'set_enable_flutter_gpu',
      line: (String project) => '$project.set_enable_flutter_gpu(true);',
    );

String _afterLine(
  String source, {
  required bool enabled,
  required RegExp anchor,
  required String already,
  required String Function(String project) line,
}) {
  final String stripped = _strip(source, _codeStart, _codeEnd);
  if (!enabled || stripped.contains(already)) return stripped;
  final RegExpMatch? match = anchor.firstMatch(stripped);
  if (match == null) return stripped;
  final String indent = match.group(1)!;
  final String block = '\n$indent$_codeStart\n$indent${line(match.group(2)!)}\n$indent$_codeEnd';
  return stripped.replaceRange(match.end, match.end, block);
}
