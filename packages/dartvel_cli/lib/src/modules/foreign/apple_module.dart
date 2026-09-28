/// A Swift package, as a module: exported to the C ABI by a generated shim
/// and compiled by the module's build hook.
///
/// The hook compiles the package's sources and the shim into one library
/// for the target being built -- `xcrun swiftc` with the iOS or macOS SDK
/// the build asks for -- and the carrier binds the shim's symbols with
/// `@Native`, as for C. No platform channel, no Objective-C runtime lookup.
///
/// The module declares `targets: [ios, macos]`: that is where a Swift
/// package's frameworks are. The hook also builds on Linux when a Swift
/// toolchain is on the PATH, which is how the shim is checked on a machine
/// without Xcode; the Linux build is a check, not a target the module claims.
library;

import 'dart:io';

import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;
import 'package:path/path.dart' as p;

import '../described_api.dart';
import 'apple_surface.dart';
import 'dart_surface.dart';
import 'module_writer.dart';

/// The symbol prefix the shim exports under for module [id].
String dvAppleSymbolPrefix(DVAppleSurface surface) =>
    'dv_${surface.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_';

DVForeignModuleSpec dvAppleModuleSpec({
  required String id,
  required String source,
  required DVAppleSurface surface,
  DVModuleOutcome elsewhere = DVModuleOutcome.unavailable,
}) {
  final String packageName = 'dv_${dvSnake(id)}_module';
  final String assetId = 'package:$packageName/native';
  final String prefix = dvAppleSymbolPrefix(surface);
  final bool swift = surface.language == 'swift';
  String ffi(String t) => swift ? dvSwiftFfi(t) : dvObjcFfi(t);
  bool text(String t) => t == 'String' || t == 'NSString*';
  final StringBuffer externs = StringBuffer()
    ..writeln("@Native<Void Function(Pointer<Utf8>)>(symbol: '${prefix}free', "
        "assetId: '$assetId')")
    ..writeln('external void _free(Pointer<Utf8> pointer);')
    ..writeln();
  for (final DVAppleFunction f in surface.functions) {
    final String ret = text(f.returns) ? 'Pointer<Utf8>' : ffi(f.returns);
    final String dartRet = text(f.returns)
        ? 'Pointer<Utf8>'
        : f.operation.returnType;
    externs
      ..writeln('@Native<$ret Function(${f.params.map(((String?, String, String) x) => ffi(x.$3)).join(', ')})>('
          "symbol: '${f.symbol}', assetId: '$assetId')")
      ..writeln('external $dartRet _${f.symbol}(${f.params.map(((String?, String, String) x) => '${text(x.$3) ? 'Pointer<Utf8>' : f.operation.params.firstWhere((DVModuleParam q) => q.name == x.$2).type} ${x.$2}').join(', ')});')
      ..writeln();
  }
  final DVCarrierSource native = DVCarrierSource(
    imports: const <String>["import 'dart:ffi';", "import 'package:ffi/ffi.dart';"],
    declarations: externs.toString(),
    body: (DVModuleOperation op) {
      final DVAppleFunction f = surface.functions
          .firstWhere((DVAppleFunction f) => f.operation.name == op.name);
      final String args = f.params
          .map(((String?, String, String) x) => text(x.$3)
              ? '${x.$2}.toNativeUtf8(allocator: arena)'
              : x.$2)
          .join(', ');
      final bool strings = f.params.any(((String?, String, String) x) => text(x.$3));
      final String call = '_${f.symbol}($args)';
      if (text(f.returns)) {
        // The shim's copy, read and handed back to the shim to free.
        return 'using((Arena arena) { final Pointer<Utf8> r = $call; '
            'try { return r.toDartString(); } finally { _free(r); } })';
      }
      return strings ? 'using((Arena arena) => $call)' : call;
    },
  );

  final String dir = swift ? 'native/swift' : 'native/objc';
  final Map<String, String> files = <String, String>{
    for (final String s in surface.sources)
      '$dir/$s': File(p.join(surface.directory, s)).readAsStringSync(),
    if (swift)
      '$dir/DartvelShim.swift': dvSwiftShim(surface, prefix)
    else
      '$dir/DartvelShim.m': dvObjcShim(surface, prefix),
  };

  return DVForeignModuleSpec(
    id: id,
    kind: 'apple',
    source: source,
    description: '${surface.name}, ${swift ? 'a Swift package' : 'an Objective-C library'}, as a Dartvel module.',
    operations: <DVModuleOperation>[
      for (final DVAppleFunction f in surface.functions) f.operation,
    ],
    outcomes: <String, Map<DVModuleEnvironment, DVModuleOutcome>>{
      for (final DVAppleFunction f in surface.functions)
        f.operation.name: <DVModuleEnvironment, DVModuleOutcome>{
          DVModuleEnvironment.native: DVModuleOutcome.real,
          DVModuleEnvironment.web: elsewhere,
          DVModuleEnvironment.backend: elsewhere,
        },
    },
    carriers: <DVModuleEnvironment, DVCarrierSource>{
      DVModuleEnvironment.native: native,
    },
    dependencies: <String, String>{
      'ffi': '^2.1.0',
      'hooks': '^0.20.1',
      'code_assets': '^0.19.7',
      if (!swift) 'native_toolchain_c': '^0.17.2',
    },
    targets: const <String>['ios', 'macos'],
    skipped: surface.skipped,
    extraFiles: <String, String>{
      ...files,
      'hook/build.dart': swift
          ? _swiftHook(packageName, surface.name, files.keys.toList())
          : _objcHook(files.keys.where((String k) => k.endsWith('.m')).toList(), dir),
    },
  );
}

String _swiftHook(String packageName, String module, List<String> sources) => '''
// GENERATED by dartvel add. Compiles the Swift package and its C-ABI shim
// into one library for the target the application is built for.
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

const List<String> _sources = <String>[
${sources.map((String s) => "  '$s',").join('\n')}
];

Future<void> main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    if (!input.config.buildAssetTypes.contains('code_assets/code')) return;
    final OS os = input.config.code.targetOS;
    final Architecture arch = input.config.code.targetArchitecture;
    final String arch0 = arch == Architecture.arm64 ? 'arm64' : 'x86_64';
    final List<String> files = <String>[
      for (final String s in _sources) input.packageRoot.resolve(s).toFilePath(),
    ];
    final String name = os == OS.linux ? 'lib$packageName.so' : 'lib$packageName.dylib';
    final String out = input.outputDirectory.resolve(name).toFilePath();
    final List<String> common = <String>[
      '-emit-library', '-O', '-module-name', '${module.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_')}',
      '-o', out, ...files,
    ];
    final ProcessResult built;
    switch (os) {
      case OS.linux:
        built = await Process.run('swiftc', common);
      case OS.macOS:
        built = await Process.run('xcrun', <String>[
          '--sdk', 'macosx', 'swiftc', '-target', '\$arch0-apple-macos11.0',
          '-Xlinker', '-install_name', '-Xlinker', '@rpath/\$name', ...common,
        ]);
      case OS.iOS:
        final bool simulator =
            input.config.code.iOS.targetSdk == IOSSdk.iPhoneSimulator;
        built = await Process.run('xcrun', <String>[
          '--sdk', simulator ? 'iphonesimulator' : 'iphoneos', 'swiftc',
          '-target', '\$arch0-apple-ios13.0\${simulator ? '-simulator' : ''}',
          '-Xlinker', '-install_name', '-Xlinker', '@rpath/\$name', ...common,
        ]);
      default:
        return; // Not an Apple target: the module is not for it.
    }
    if (built.exitCode != 0) {
      throw StateError('swiftc failed for \$os/\$arch:\\n\${built.stderr}');
    }
    output.assets.code.add(CodeAsset(
      package: input.packageName,
      name: 'native',
      linkMode: DynamicLoadingBundled(),
      file: Uri.file(out),
    ));
    for (final String f in files) {
      output.dependencies.add(Uri.file(f));
    }
  });
}
''';

String _objcHook(List<String> sources, String dir) => '''
// GENERATED by dartvel add. Compiles the Objective-C sources and the C-ABI
// shim for the Apple target the application is built for.
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) async {
  await build(args, (BuildInput input, BuildOutputBuilder output) async {
    if (!input.config.buildAssetTypes.contains('code_assets/code')) return;
    final OS os = input.config.code.targetOS;
    // Objective-C and Foundation are Apple's: another target is not one the
    // module is for.
    if (os != OS.iOS && os != OS.macOS) return;
    await CBuilder.library(
      name: 'native',
      assetName: 'native',
      language: Language.objectiveC,
      sources: <String>[
${sources.map((String s) => "        '$s',").join('\n')}
      ],
      includes: <String>['$dir'],
      frameworks: <String>['Foundation'],
      flags: <String>['-fobjc-arc'],
    ).run(input: input, output: output);
  });
}
''';
