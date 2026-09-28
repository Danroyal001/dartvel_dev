// Swift off Apple: the placement matrix runs a Swift package on Linux and
// Windows through the Swift toolchain, and on the backend, unless it needs
// an Apple framework -- and then the refusal names the import that blocks
// it, not just the platform.
import 'dart:io';

import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/apple_module.dart';
import 'package:dartvel_cli/src/modules/foreign/apple_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'apple_module_test.dart' show swiftPackage;

YamlMap declared(Directory root) => (loadYaml(dvWriteForeignModule(
        dvAppleModuleSpec(
            id: 'textKit',
            source: 'swift:TextKit',
            surface: dvScanSwiftPackage(root.path)))
    .files['pubspec.yaml']!) as YamlMap)['dartvel']['module'] as YamlMap;

void main() {
  Directory scratch() {
    final Directory dir = Directory.systemTemp.createTempSync('dv_swift_off_');
    addTearDown(() => dir.deleteSync(recursive: true));
    return dir;
  }

  test('a Swift package with no Apple framework runs on Linux, Windows and '
      'the backend', () {
    final YamlMap module = declared(swiftPackage(scratch()));
    expect(module['targets'], <String>['ios', 'macos', 'linux', 'windows']);
    expect(module['operations']['add']['backend'], 'real');
    expect(module['operations']['add']['native'], 'real');
  });

  test('one that imports UIKit stays on Apple, and says which import', () {
    final Directory pkg = swiftPackage(scratch());
    File(p.join(pkg.path, 'Sources', 'TextKit', 'Screen.swift'))
        .writeAsStringSync('import UIKit\n\npublic func scale() -> Double { 2 }\n');
    final DVGeneratedModule module = dvWriteForeignModule(dvAppleModuleSpec(
        id: 'textKit',
        source: 'swift:TextKit',
        surface: dvScanSwiftPackage(pkg.path)));
    final YamlMap m = (loadYaml(module.files['pubspec.yaml']!) as YamlMap)
        ['dartvel']['module'] as YamlMap;
    expect(m['targets'], <String>['ios', 'macos']);
    expect(m['operations']['add']['backend'], 'unavailable');
    expect(module.files['README.md'], contains('import UIKit'));
    expect(module.files['README.md'], contains('Screen.swift'));
  });

  test('the hook builds a Windows library too', () {
    final DVGeneratedModule module = dvWriteForeignModule(dvAppleModuleSpec(
        id: 'textKit',
        source: 'swift:TextKit',
        surface: dvScanSwiftPackage(swiftPackage(scratch()).path)));
    expect(module.files['hook/build.dart'], contains('case OS.windows:'));
  });
}
