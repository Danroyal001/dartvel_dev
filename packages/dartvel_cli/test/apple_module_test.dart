// A Swift package becomes a module: a generated shim exports its public
// functions to the C ABI, and the module's hook compiles package and shim
// into one library for the target.
//
// Apple targets need Xcode, which this machine does not have. The shim and
// the hook are checked on Linux instead, with a Swift toolchain: the hook
// compiles the same sources with swiftc, and a probe binds the shim's
// symbols through the module's asset id and calls them, including the one
// returning a String, which the shim copies and the probe frees through the
// shim's own free function.
import 'dart:io';

import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/apple_module.dart';
import 'package:dartvel_cli/src/modules/foreign/apple_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/dart_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory swiftPackage(Directory root) {
  final Directory dir = Directory(p.join(root.path, 'TextKit'))..createSync();
  File(p.join(dir.path, 'Package.swift')).writeAsStringSync('''
// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "TextKit",
    products: [.library(name: "TextKit", targets: ["TextKit"])],
    targets: [.target(name: "TextKit")]
)
''');
  File(p.join(dir.path, 'Sources', 'TextKit', 'TextKit.swift'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
/// Adds two numbers.
public func add(_ a: Int32, _ b: Int32) -> Int32 { a + b }

public func greet(name: String) -> String { "Hello " + name }

public enum Units {
    public static func toCelsius(fahrenheit f: Double) -> Double { (f - 32) * 5 / 9 }
    public func instance() -> Int { 1 }
}

public func fetch() async -> Int { 1 }
public func parse(_ s: String) throws -> Int { 1 }
public func each(_ f: (Int) -> Void) {}
func hidden() -> Int { 0 }
''');
  return dir;
}

void main() {
  test('public functions and static functions are exported, the rest said', () {
    final Directory root = Directory.systemTemp.createTempSync('dv_swift_');
    addTearDown(() => root.deleteSync(recursive: true));
    final DVAppleSurface surface = dvScanSwiftPackage(swiftPackage(root).path);
    final Map<String, DVAppleFunction> f = <String, DVAppleFunction>{
      for (final DVAppleFunction x in surface.functions) x.operation.name: x,
    };
    expect(f.keys, unorderedEquals(<String>['add', 'greet', 'unitsToCelsius']));
    expect(f['greet']!.operation.returnType, 'String');
    expect(f['unitsToCelsius']!.owner, 'Units');
    expect(surface.skipped['fetch'], contains('async'));
    expect(surface.skipped['parse'], contains('throws'));
    expect(surface.skipped['each'], contains('does not cross'));
    final String shim = dvSwiftShim(surface, dvAppleSymbolPrefix(surface));
    expect(shim, contains('@_cdecl("dv_textkit_add")'));
    expect(shim, contains('return Units.toCelsius(fahrenheit: f)'));
    expect(shim, contains('return strdup(greet(name: String(cString: name)))!'));
  });

  test('an Objective-C library exports its class methods through a C shim', () {
    final Directory root = Directory.systemTemp.createTempSync('dv_objc_');
    addTearDown(() => root.deleteSync(recursive: true));
    File(p.join(root.path, 'Classes', 'Calc.h'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
#import <Foundation/Foundation.h>
@interface Calc : NSObject
+ (int)add:(int)a to:(int)b;
+ (NSString *)greet:(NSString *)name;
+ (void)reset;
- (int)count;
+ (NSArray *)all;
@end
''');
    File(p.join(root.path, 'Classes', 'Calc.m')).writeAsStringSync(
        '#import "Calc.h"\n@implementation Calc\n@end\n');
    final DVAppleSurface surface = dvScanObjcHeaders(root.path, 'Calc');
    final Map<String, DVAppleFunction> f = <String, DVAppleFunction>{
      for (final DVAppleFunction x in surface.functions) x.operation.name: x,
    };
    expect(f.keys, unorderedEquals(<String>['calcAdd', 'calcGreet', 'calcReset']));
    expect(f['calcAdd']!.operation.parameterList, 'int a, int b');
    expect(f['calcGreet']!.operation.returnType, 'String');
    expect(surface.skipped['Calc.count'], contains('instance method'));
    expect(surface.skipped['Calc.all'], contains('NSArray'));
    final String shim = dvObjcShim(surface, dvAppleSymbolPrefix(surface));
    expect(shim, contains('int32_t dv_calc_calc_add(int32_t a, int32_t b) {'));
    expect(shim, contains('return [Calc add:a to:b];'));
    expect(shim, contains('return strdup([[Calc greet:[NSString stringWithUTF8String:name]] UTF8String]);'));
    final DVGeneratedModule module = dvWriteForeignModule(dvAppleModuleSpec(
      id: 'calc', source: 'pod:Calc@1.0.0', surface: surface));
    final String hook = module.files['hook/build.dart']!;
    expect(hook, contains('Language.objectiveC'));
    expect(hook, contains("'native/objc/Classes/Calc.m',"));
    expect(hook, contains("'native/objc/DartvelShim.m',"));
    expect(module.files['lib/src/carrier_native.dart'], contains('_free(r)'));
  });

  test('a package with dependencies is refused rather than half-built', () {
    final Directory root = Directory.systemTemp.createTempSync('dv_swift_');
    addTearDown(() => root.deleteSync(recursive: true));
    final Directory dir = swiftPackage(root);
    File(p.join(dir.path, 'Package.swift')).writeAsStringSync(
        'let package = Package(name: "TextKit", dependencies: [.package(url: "x", from: "1.0.0")])');
    expect(() => dvScanSwiftPackage(dir.path),
        throwsA(isA<DVDartSurfaceRefused>().having(
            (DVDartSurfaceRefused e) => e.message, 'message', contains('DV-MODULE-017'))));
  });

  test('the hook compiles package and shim, and the symbols answer', () async {
    final String swift = <String>[
      '${Platform.environment['HOME']}/.dartvel/toolchains/swift-6.1.2-RELEASE-ubuntu24.04/usr/bin',
    ].firstWhere((String d) => File('$d/swiftc').existsSync(), orElse: () => '');
    if (swift.isEmpty) {
      markTestSkipped('no Swift toolchain');
      return;
    }
    final Directory root = Directory.systemTemp.createTempSync('dv_swift_');
    addTearDown(() => root.deleteSync(recursive: true));
    final DVGeneratedModule module = dvWriteForeignModule(dvAppleModuleSpec(
      id: 'textKit',
      source: 'swift:TextKit',
      surface: dvScanSwiftPackage(swiftPackage(root).path),
    ));
    expect(module.files['pubspec.yaml'], contains('targets: [ios, macos]'));
    final Directory into = Directory(p.join(root.path, module.packageName));
    for (final MapEntry<String, String> e in module.files.entries) {
      File(p.join(into.path, e.key))
        ..createSync(recursive: true)
        ..writeAsStringSync(e.value);
    }
    final Directory stub = Directory(p.join(root.path, 'dartvel_core'));
    File(p.join(stub.path, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: dartvel_core\nversion: 9.9.9\nenvironment:\n  sdk: ">=3.13.0 <4.0.0"\n');
    File(p.join(stub.path, 'lib', 'dartvel.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('enum DVModuleEnvironment { native, web, backend }\n'
          'class DVModuleUnavailable implements Exception {\n'
          '  const DVModuleUnavailable(this.m, this.o, this.e);\n'
          '  final String m; final String o; final DVModuleEnvironment e;\n}\n');
    final Directory app = Directory(p.join(root.path, 'app'));
    File(p.join(app.path, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: probe_app
environment:
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  ffi: ^2.1.0
  ${module.packageName}:
    path: ../${module.packageName}
dependency_overrides:
  dartvel_core:
    path: ../dartvel_core
''');
    const String asset = "assetId: 'package:dv_text_kit_module/native'";
    File(p.join(app.path, 'bin', 'probe.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
import 'dart:ffi';
import 'package:ffi/ffi.dart';

@Native<Int32 Function(Int32, Int32)>(symbol: 'dv_textkit_add', $asset)
external int add(int a, int b);
@Native<Pointer<Utf8> Function(Pointer<Utf8>)>(symbol: 'dv_textkit_greet', $asset)
external Pointer<Utf8> greet(Pointer<Utf8> name);
@Native<Void Function(Pointer<Utf8>)>(symbol: 'dv_textkit_free', $asset)
external void free(Pointer<Utf8> p);
@Native<Double Function(Double)>(symbol: 'dv_textkit_units_to_celsius', $asset)
external double celsius(double f);

void main() {
  print(add(40, 2));
  final Pointer<Utf8> g = using((Arena a) => greet('Swift'.toNativeUtf8(allocator: a)));
  print(g.toDartString());
  free(g);
  print(celsius(212));
}
''');
    final Map<String, String> env = <String, String>{
      'PATH': '$swift:${Platform.environment['PATH']}',
    };
    final ProcessResult got = await Process.run(
        Platform.resolvedExecutable, <String>['pub', 'get'],
        workingDirectory: app.path, environment: env);
    expect(got.exitCode, 0, reason: '${got.stdout}${got.stderr}');
    final ProcessResult run = await Process.run(
        Platform.resolvedExecutable, <String>['run', 'bin/probe.dart'],
        workingDirectory: app.path, environment: env);
    expect('${run.stdout}', contains('42\nHello Swift\n100.0'),
        reason: '${run.stdout}${run.stderr}');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
