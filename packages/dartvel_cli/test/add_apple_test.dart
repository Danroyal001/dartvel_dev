// `dartvel add swift:` and `pod:`: a Swift package beside the project, and
// a pod resolved from the CocoaPods CDN and fetched from its repository at
// the tag its podspec names.
import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:crypto/crypto.dart';
import 'package:dartvel_cli/src/commands/add_command.dart';
import 'package:dartvel_cli/src/module_trust/module_lock.dart';
import 'package:dartvel_cli/src/modules/foreign/resolver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

String project() {
  final Directory root = Directory.systemTemp.createTempSync('dv_add_apple_');
  addTearDown(() => root.deleteSync(recursive: true));
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync(
      'name: shop\nenvironment:\n  sdk: ^3.13.0\ndartvel:\n  app:\n    name: Shop\n');
  return root.path;
}

class _Cdn extends DVSourceFetcher {
  _Cdn(this.repo);
  final String repo;
  final List<String> asked = <String>[];

  @override
  Future<String> getText(Uri url) async {
    asked.add('$url');
    if ('$url'.contains('all_pods_versions_')) return 'Other/1.0\nCalcKit/1.0.0/1.1.0/2.0.0-beta\n';
    return jsonEncode(<String, Object?>{
      'name': 'CalcKit',
      'version': '1.1.0',
      'source': <String, Object?>{'git': repo, 'tag': '1.1.0'},
      'source_files': 'Classes/**/*.{h,m}',
    });
  }
}

Future<int> run(String root, List<String> args, DVSourceFetcher f) async {
  final CommandRunner<void> runner = CommandRunner<void>('dartvel', 'test')
    ..addCommand(AddCommand(root: root, fetcher: f));
  try {
    await runner.run(<String>['add', ...args]);
  } on DVAddRefused {
    return 1;
  }
  return 0;
}

void main() {
  test('a Swift package beside the project is wrapped with its shim', () async {
    final String root = project();
    final Directory pkg = Directory(p.join(root, 'vendor', 'TextKit'));
    File(p.join(pkg.path, 'Package.swift'))
      ..createSync(recursive: true)
      ..writeAsStringSync('let package = Package(name: "TextKit")\n');
    File(p.join(pkg.path, 'Sources', 'TextKit', 'T.swift'))
      ..createSync(recursive: true)
      ..writeAsStringSync('public func add(_ a: Int32, _ b: Int32) -> Int32 { a + b }\n');
    expect(await run(root, <String>['vendor/TextKit'], const DVSourceFetcher()), 0);
    final String module = p.join(root, 'modules', 'dv_text_kit_module');
    expect(File(p.join(module, 'native', 'swift', 'DartvelShim.swift')).existsSync(), isTrue);
    final YamlMap pubspec =
        loadYaml(File(p.join(module, 'pubspec.yaml')).readAsStringSync()) as YamlMap;
    expect(pubspec['dartvel']['module']['kind'], 'apple');
    expect(DVModuleLock.read(root).pins['dv_text_kit_module']!.source,
        'swift:vendor/TextKit');
  });

  test('pod: takes the newest release, clones its tag and exports its '
      'class methods', () async {
    final Directory repo = Directory.systemTemp.createTempSync('dv_pod_repo_');
    addTearDown(() => repo.deleteSync(recursive: true));
    File(p.join(repo.path, 'Classes', 'Calc.h'))
      ..createSync(recursive: true)
      ..writeAsStringSync('@interface Calc : NSObject\n+ (int)twice:(int)x;\n@end\n');
    File(p.join(repo.path, 'Classes', 'Calc.m')).writeAsStringSync(
        '#import "Calc.h"\n@implementation Calc\n+ (int)twice:(int)x { return x * 2; }\n@end\n');
    for (final List<String> git in <List<String>>[
      <String>['init', '-q'],
      <String>['-c', 'user.email=t@t', '-c', 'user.name=t', 'add', '.'],
      <String>['-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'x'],
      <String>['tag', '1.1.0'],
    ]) {
      expect(Process.runSync('git', git, workingDirectory: repo.path).exitCode, 0);
    }
    final String root = project();
    final _Cdn cdn = _Cdn(repo.path);
    expect(await run(root, <String>['pod:CalcKit@^1.0.0'], cdn), 0);
    final String hash = md5.convert(utf8.encode('CalcKit')).toString();
    expect(cdn.asked, contains(
        'https://cdn.cocoapods.org/Specs/${hash[0]}/${hash[1]}/${hash[2]}/CalcKit/1.1.0/CalcKit.podspec.json'));
    final String module = p.join(root, 'modules', 'dv_calc_kit_module');
    expect(File(p.join(module, 'native', 'objc', 'DartvelShim.m')).readAsStringSync(),
        contains('return [Calc twice:x];'));
    expect(DVModuleLock.read(root).pins['dv_calc_kit_module']!.source,
        'pod:CalcKit@1.1.0');
  });
}
