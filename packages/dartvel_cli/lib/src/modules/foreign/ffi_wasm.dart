/// C and Rust, compiled for the browser.
///
/// The placement matrix puts a C or Rust library on the web as WebAssembly:
/// the sources a device links through FFI, compiled for wasm32 when the
/// module is generated and carried in it, so nothing has to be served. The
/// browser instantiates the binary synchronously, which is what lets a
/// function that is synchronous on a device stay synchronous on the web.
///
/// Only functions whose values are numbers cross: a string needs a memory
/// layout and an allocator the two sides agree on, which a C library built
/// without a libc does not have. Those keep the outcome the module declares
/// elsewhere, and the README says why.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'dart_surface.dart';
import 'ffi_surface.dart';
import 'wasm_module.dart' show dvScanWasm, DVWasmSurface;

/// The library compiled to WebAssembly, or why it was not.
class DVFfiWasm {
  const DVFfiWasm(Uint8List this.bytes) : reason = null;
  const DVFfiWasm.none(String this.reason) : bytes = null;

  final Uint8List? bytes;

  /// Why there is no binary: the compiler that is missing, or what it said.
  final String? reason;
}

/// Compiles [surface]'s sources for wasm32.
Future<DVFfiWasm> dvCompileFfiToWasm(DVFfiSurface surface) async {
  final Directory work = Directory.systemTemp.createTempSync('dv_ffi_wasm_');
  try {
    return surface.language == 'c'
        ? await _compileC(surface, work)
        : await _compileRust(surface, work);
  } finally {
    work.deleteSync(recursive: true);
  }
}

Future<DVFfiWasm> _compileC(DVFfiSurface surface, Directory work) async {
  final String? linker = await _wasmLinker();
  if (linker == null) {
    return const DVFfiWasm.none('no WebAssembly linker: install lld (wasm-ld) '
        'or a Rust toolchain, which carries one');
  }
  final List<String> objects = <String>[];
  for (final String source in surface.sources) {
    final String object = p.join(work.path, '${objects.length}.o');
    final ProcessResult r = await _run('clang', <String>[
      '--target=wasm32', '-O2', '-nostdlib', '-ffreestanding',
      '-fvisibility=default', '-I', surface.directory,
      '-c', p.join(surface.directory, source), '-o', object,
    ]);
    if (r.exitCode != 0) {
      return DVFfiWasm.none('clang could not compile $source for wasm32: '
          '${_first(r)}');
    }
    objects.add(object);
  }
  final String out = p.join(work.path, 'out.wasm');
  final List<String> flavor =
      p.basename(linker).startsWith('rust-lld') ? <String>['-flavor', 'wasm'] : <String>[];
  final ProcessResult linked = await _run(linker, <String>[
    ...flavor, '--no-entry', '--strip-all',
    for (final DVFfiFunction f in surface.functions) '--export-if-defined=${f.name}',
    '-o', out, ...objects,
  ]);
  if (linked.exitCode != 0) {
    return DVFfiWasm.none('the wasm32 link failed, most often for a libc '
        'function a freestanding build has no copy of: ${_first(linked)}');
  }
  return DVFfiWasm(File(out).readAsBytesSync());
}

Future<DVFfiWasm> _compileRust(DVFfiSurface surface, Directory work) async {
  final ProcessResult targets =
      await _run(_rustup(), <String>['target', 'list', '--installed']);
  if (targets.exitCode != 0 ||
      !'${targets.stdout}'.contains('wasm32-unknown-unknown')) {
    return const DVFfiWasm.none('the wasm32-unknown-unknown target is not '
        'installed: rustup target add wasm32-unknown-unknown');
  }
  final ProcessResult built = await _run(_cargo(), <String>[
    'build', '--release', '--lib', '--target', 'wasm32-unknown-unknown',
    '--target-dir', work.path,
  ], workingDirectory: surface.directory);
  if (built.exitCode != 0) {
    return DVFfiWasm.none('cargo could not build for wasm32: ${_first(built)}');
  }
  final Directory release =
      Directory(p.join(work.path, 'wasm32-unknown-unknown', 'release'));
  final List<File> wasm = release
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.wasm'))
      .toList();
  if (wasm.isEmpty) {
    return const DVFfiWasm.none('the crate built no .wasm: its [lib] needs '
        'crate-type = ["cdylib"]');
  }
  return DVFfiWasm(wasm.first.readAsBytesSync());
}

/// A wasm-ld: on PATH, or the rust-lld a Rust toolchain carries.
Future<String?> _wasmLinker() async {
  for (final String name in <String>['wasm-ld', 'wasm-ld-21', 'wasm-ld-20']) {
    final ProcessResult r = await _run('which', <String>[name]);
    if (r.exitCode == 0) return '${r.stdout}'.trim();
  }
  final ProcessResult sysroot = await _run(_rustc(), <String>['--print', 'sysroot']);
  if (sysroot.exitCode != 0) return null;
  final Directory rustlib =
      Directory(p.join('${sysroot.stdout}'.trim(), 'lib', 'rustlib'));
  if (!rustlib.existsSync()) return null;
  for (final FileSystemEntity e in rustlib.listSync(recursive: true)) {
    if (e is File && p.basename(e.path) == 'rust-lld') return e.path;
  }
  return null;
}

String _tool(String name) {
  final String home = Platform.environment['HOME'] ?? '';
  final File inCargo = File(p.join(home, '.cargo', 'bin', name));
  return inCargo.existsSync() ? inCargo.path : name;
}

String _rustc() => _tool('rustc');
String _cargo() => _tool('cargo');
String _rustup() => _tool('rustup');

Future<ProcessResult> _run(String exe, List<String> args,
    {String? workingDirectory}) async {
  try {
    return await Process.run(exe, args, workingDirectory: workingDirectory);
  } on ProcessException catch (e) {
    return ProcessResult(0, 127, '', e.message);
  }
}

String _first(ProcessResult r) {
  final String text = '${r.stderr}${r.stdout}'.trim();
  return text.split('\n').firstWhere((String l) => l.contains('error'),
      orElse: () => text.split('\n').first);
}

/// The functions of [surface] the browser can call through [bytes]: each
/// export's WebAssembly types, by the C name, for the functions whose values
/// are all numbers.
Map<String, List<String>> dvFfiWasmCallable(
    DVFfiSurface surface, Uint8List bytes) {
  final DVWasmSurface wasm;
  try {
    wasm = dvScanWasm(bytes, name: surface.name);
  } on Object {
    return const <String, List<String>>{};
  }
  final Map<String, List<String>> byExport = <String, List<String>>{
    for (final DVModuleOperation op in wasm.operations)
      op.doc.replaceFirst('The `', '').replaceFirst('` export.', ''):
          wasm.types[op.name]!,
  };
  const Set<String> numbers = <String>{'int', 'double'};
  return <String, List<String>>{
    for (final DVFfiFunction f in surface.functions)
      if (f.stringParams.isEmpty &&
          byExport.containsKey(f.name) &&
          f.operation.params.every((DVModuleParam p) => numbers.contains(p.type)) &&
          (f.operation.returnType == 'void' ||
              numbers.contains(f.operation.returnType)))
        f.name: byExport[f.name]!,
  };
}

/// The web carrier's declarations: the binary, instantiated synchronously
/// on first use.
String dvFfiWasmDeclarations(Uint8List bytes) => '''
/// The library compiled to WebAssembly, carried so nothing has to be served.
const String _wasm = '${base64Encode(bytes)}';

JSObject? _exports;

/// Instantiated synchronously, so a function that is synchronous on a
/// device is synchronous here too.
JSObject get _instance {
  final JSObject? loaded = _exports;
  if (loaded != null) return loaded;
  final JSObject wasm = globalContext['WebAssembly']! as JSObject;
  final JSObject module = (wasm['Module']! as JSFunction)
      .callAsConstructor<JSObject>(Uint8List.fromList(base64Decode(_wasm)).toJS);
  final JSObject instance =
      (wasm['Instance']! as JSFunction).callAsConstructor<JSObject>(module);
  return _exports = instance['exports']! as JSObject;
}''';

/// One call into the instance, as the web carrier writes it.
String dvFfiWasmCall(DVFfiFunction f, List<String> kinds) {
  final List<String> args = <String>[
    for (int i = 0; i < f.operation.params.length; i++)
      kinds[i] == 'i64'
          ? "globalContext.callMethod<JSAny>('BigInt'.toJS, '\${${f.operation.params[i].name}}'.toJS)"
          : '${f.operation.params[i].name}.toJS',
  ];
  final String call =
      "_instance.callMethodVarArgs<JSAny?>('${f.name}'.toJS, <JSAny?>[${args.join(', ')}])";
  final String result = kinds.last;
  return switch (f.operation.returnType) {
    'void' => call,
    'int' when result == 'i64' =>
      "int.parse(globalContext.callMethod<JSString>('String'.toJS, $call).toDart)",
    'int' => '($call! as JSNumber).toDartInt',
    _ => '($call! as JSNumber).toDartDouble',
  };
}
