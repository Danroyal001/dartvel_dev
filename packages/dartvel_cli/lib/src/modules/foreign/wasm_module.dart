/// A WebAssembly binary, as a module.
///
/// The surface is read from the binary itself -- its type, function and
/// export sections -- so the Dart types come from what the module actually
/// takes and returns rather than from documentation. Only numbers cross a
/// WebAssembly boundary without an agreed memory layout: `i32` and `i64`
/// arrive as `int`, `f32` and `f64` as `double`. A function taking or
/// returning anything else, or more than one result, is left out with the
/// reason, and a binary that imports functions from its host is refused,
/// since nothing here could say what those functions should do.
///
/// Two carriers, both instantiating the same bytes, which the module carries
/// in its source: the browser's own `WebAssembly`, and Node's on the backend.
/// A device has no WebAssembly runtime in the application, so there the
/// module declares what `--elsewhere` says (DV-MODULE-013 when unavailable).
/// A 64-bit integer crosses as a BigInt, which is the one place a carrier
/// that passed a JavaScript Number would round without saying so.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;

import '../described_api.dart';
import 'dart_surface.dart';
import 'module_writer.dart';
import 'node_carrier.dart';

/// What a WebAssembly binary exports.
class DVWasmSurface {
  const DVWasmSurface({
    required this.name,
    required this.operations,
    required this.skipped,
    required this.types,
  });

  final String name;
  final List<DVModuleOperation> operations;
  final Map<String, String> skipped;

  /// Each operation's WebAssembly types: the parameters, `->`, the result.
  final Map<String, List<String>> types;
}

/// Reads the exports of the WebAssembly binary [bytes].
DVWasmSurface dvScanWasm(Uint8List bytes, {required String name}) {
  if (bytes.length < 8 ||
      bytes[0] != 0x00 ||
      bytes[1] != 0x61 ||
      bytes[2] != 0x73 ||
      bytes[3] != 0x6d) {
    throw const DVDartSurfaceRefused(
        'That file is not a WebAssembly binary: it does not start with '
        '\\0asm (DV-MODULE-009).');
  }
  final _Reader r = _Reader(bytes, 8);
  final List<(List<int>, List<int>)> types = <(List<int>, List<int>)>[];
  final List<int> functionTypes = <int>[];
  int importedFunctions = 0;
  final List<String> importedNames = <String>[];
  final List<(String, int)> exports = <(String, int)>[];
  while (r.offset < bytes.length) {
    final int id = r.byte();
    final int size = r.u32();
    final int end = r.offset + size;
    switch (id) {
      case 1:
        final int count = r.u32();
        for (int i = 0; i < count; i++) {
          r.byte(); // 0x60
          final List<int> params = <int>[
            for (int j = 0, n = r.u32(); j < n; j++) r.byte(),
          ];
          final List<int> results = <int>[
            for (int j = 0, n = r.u32(); j < n; j++) r.byte(),
          ];
          types.add((params, results));
        }
      case 2:
        final int count = r.u32();
        for (int i = 0; i < count; i++) {
          final String module = r.name();
          final String field = r.name();
          final int kind = r.byte();
          switch (kind) {
            case 0:
              r.u32();
              importedFunctions++;
              importedNames.add('$module.$field');
            case 1:
              r.byte();
              _limits(r);
            case 2:
              _limits(r);
            case 3:
              r.byte();
              r.byte();
          }
        }
      case 3:
        final int count = r.u32();
        for (int i = 0; i < count; i++) {
          functionTypes.add(r.u32());
        }
      case 7:
        final int count = r.u32();
        for (int i = 0; i < count; i++) {
          final String field = r.name();
          final int kind = r.byte();
          final int index = r.u32();
          if (kind == 0) exports.add((field, index));
        }
    }
    r.offset = end;
  }
  if (importedFunctions > 0) {
    throw DVDartSurfaceRefused('$name imports functions from its host '
        '(${importedNames.join(', ')}), and nothing here can say what they '
        'should do. A module needs a binary that imports no functions '
        '(DV-MODULE-017).');
  }

  final List<DVModuleOperation> operations = <DVModuleOperation>[];
  final Map<String, String> skipped = <String, String>{};
  final Map<String, List<String>> typeNames = <String, List<String>>{};
  for (final (String field, int index) in exports) {
    final int local = index - importedFunctions;
    if (local < 0 || local >= functionTypes.length) continue;
    final (List<int> params, List<int> results) = types[functionTypes[local]];
    final List<String?> paramNames = params.map(_valType).toList();
    if (paramNames.contains(null) || results.any((int t) => _valType(t) == null)) {
      skipped[field] = 'takes or returns a reference type; only numbers '
          'cross without an agreed memory layout';
      continue;
    }
    if (results.length > 1) {
      skipped[field] = 'returns ${results.length} values';
      continue;
    }
    final String? result = results.isEmpty ? null : _valType(results.single);
    final String op = dvCamel(field);
    typeNames[op] = <String>[...paramNames.cast<String>(), '->', result ?? 'void'];
    operations.add(DVModuleOperation(
      name: op,
      returnType: 'Future<${result == null ? 'void' : _dart(result)}>',
      params: <DVModuleParam>[
        for (int i = 0; i < params.length; i++)
          DVModuleParam(name: 'a$i', type: _dart(paramNames[i]!)),
      ],
      doc: 'The `$field` export.',
    ));
  }
  if (operations.isEmpty) {
    throw DVDartSurfaceRefused('$name exports no function a module can call '
        '(DV-MODULE-010).');
  }
  operations.sort(
      (DVModuleOperation a, DVModuleOperation b) => a.name.compareTo(b.name));
  return DVWasmSurface(
    name: name,
    operations: operations,
    skipped: skipped,
    types: typeNames,
  );
}

void _limits(_Reader r) {
  final int flag = r.byte();
  r.u32();
  if (flag & 1 == 1) r.u32();
}

String? _valType(int t) => switch (t) {
      0x7f => 'i32',
      0x7e => 'i64',
      0x7d => 'f32',
      0x7c => 'f64',
      _ => null,
    };

String _dart(String wasm) => wasm.startsWith('i') ? 'int' : 'double';

class _Reader {
  _Reader(this.bytes, this.offset);
  final Uint8List bytes;
  int offset;

  int byte() => bytes[offset++];

  int u32() {
    int result = 0;
    int shift = 0;
    while (true) {
      final int b = byte();
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
    }
  }

  String name() {
    final int length = u32();
    final String s = utf8.decode(bytes.sublist(offset, offset + length));
    offset += length;
    return s;
  }
}

/// The module spec for the binary [bytes].
DVForeignModuleSpec dvWasmModuleSpec({
  required String id,
  required String source,
  required Uint8List bytes,
  required DVWasmSurface surface,
  DVModuleOutcome elsewhere = DVModuleOutcome.unavailable,
}) {
  final String packageName = 'dv_${dvSnake(id)}_module';
  final String b64 = base64Encode(bytes);
  final String digest = sha256.convert(bytes).toString().substring(0, 16);
  final String types = jsonEncode(surface.types);
  String body(DVModuleOperation op) {
    final String t = RegExp(r'^Future<(.+)>$').firstMatch(op.returnType)!.group(1)!;
    final String args = op.params.map((DVModuleParam p) => p.name).join(', ');
    final String call = "_call('${_export(op)}', '${op.name}', <Object>[$args])";
    return switch (t) {
      'void' => '$call.then((Object? _) {})',
      'int' => '$call.then((Object? r) => int.parse(\'\$r\'))',
      _ => '$call.then((Object? r) => (r! as num).toDouble())',
    };
  }

  return DVForeignModuleSpec(
    id: id,
    kind: 'wasm',
    source: source,
    description: '${surface.name}, a WebAssembly module, as a Dartvel module.',
    operations: surface.operations,
    outcomes: <String, Map<DVModuleEnvironment, DVModuleOutcome>>{
      for (final DVModuleOperation op in surface.operations)
        op.name: <DVModuleEnvironment, DVModuleOutcome>{
          // A desktop runs it in the Node dartvel build bundles beside it.
          DVModuleEnvironment.native: DVModuleOutcome.real,
          DVModuleEnvironment.web: DVModuleOutcome.real,
          DVModuleEnvironment.backend: DVModuleOutcome.real,
        },
    },
    carriers: <DVModuleEnvironment, DVCarrierSource>{
      DVModuleEnvironment.web: DVCarrierSource(
        imports: const <String>[
          "import 'dart:convert';",
          "import 'dart:js_interop';",
          "import 'dart:js_interop_unsafe';",
          "import 'dart:typed_data';",
        ],
        declarations: _webInstance(b64, types),
        body: body,
      ),
      DVModuleEnvironment.native: DVCarrierSource(
        imports: const <String>[
          "import 'dart:convert';",
          "import 'dart:io';",
        ],
        declarations: _nodeInstance(id, packageName, digest, b64, types),
        body: body,
      ),
      DVModuleEnvironment.backend: DVCarrierSource(
        imports: const <String>[
          "import 'dart:convert';",
          "import 'dart:io';",
        ],
        declarations: _nodeInstance(id, packageName, digest, b64, types),
        body: body,
      ),
    },
    targets: dvNodeTargets,
    skipped: surface.skipped,
  );
}

/// The export an operation calls: its name as the binary spells it.
String _export(DVModuleOperation op) =>
    op.doc.replaceFirst('The `', '').replaceFirst('` export.', '');

String _webInstance(String b64, String types) => '''
/// The binary, carried in the module so nothing has to be served.
const String _wasm = '$b64';

/// Each export's WebAssembly types, so a 64-bit integer goes as a BigInt.
const String _types = r\'\'\'$types\'\'\';

JSObject? _exports;

Future<JSObject> _load() async {
  final JSObject? loaded = _exports;
  if (loaded != null) return loaded;
  final JSObject wasm = globalContext['WebAssembly']! as JSObject;
  final JSObject result = await wasm
      .callMethod<JSPromise<JSObject>>('instantiate'.toJS,
          Uint8List.fromList(base64Decode(_wasm)).toJS)
      .toDart;
  return _exports = (result['instance']! as JSObject)['exports']! as JSObject;
}

Future<Object?> _call(String name, String op, List<Object> args) async {
  final List<Object?> kinds =
      (jsonDecode(_types) as Map<String, Object?>)[op]! as List<Object?>;
  final JSObject exports = await _load();
  final JSAny? result = exports.callMethodVarArgs<JSAny?>(name.toJS, <JSAny?>[
    for (int i = 0; i < args.length; i++)
      kinds[i] == 'i64'
          ? globalContext.callMethod<JSAny>('BigInt'.toJS, '\${args[i]}'.toJS)
          : (args[i] as num).toJS,
  ]);
  if (result == null) return null;
  if (kinds.last == 'i64') {
    return (globalContext.callMethod<JSString>('String'.toJS, result)).toDart;
  }
  return kinds.last == 'i32'
      ? (result as JSNumber).toDartInt
      : (result as JSNumber).toDartDouble;
}''';

String _nodeInstance(
        String id, String packageName, String digest, String b64, String types) =>
    '''
const String _wasm = '$b64';

const String _types = r\'\'\'$types\'\'\';

/// What Node runs: instantiate the binary and call one export, a 64-bit
/// integer in and out as a BigInt.
const String _runner = r"""
import { readFileSync } from 'node:fs';
const [file, name, op, args, types] = process.argv.slice(1);
const kinds = JSON.parse(types)[op];
const { instance } = await WebAssembly.instantiate(readFileSync(file));
const values = JSON.parse(args).map((a, i) => kinds[i] === 'i64' ? BigInt(a) : a);
const r = instance.exports[name](...values);
process.stdout.write(JSON.stringify(typeof r === 'bigint' ? r.toString() : (r ?? null)));
""";

String? _path;

$dvNodeLocator

Future<Object?> _call(String name, String op, List<Object> args) async {
  final String path = _path ??= () {
    final File file = File('\${Directory.systemTemp.path}/${packageName}_$digest.wasm');
    if (!file.existsSync()) file.writeAsBytesSync(base64Decode(_wasm));
    return file.path;
  }();
  final ProcessResult result;
  try {
    result = await Process.run(_node, <String>[
      '--input-type=module', '-e', _runner, path, name, op,
      jsonEncode(<String>[for (final Object a in args) '\$a']), _types,
    ]);
  } on ProcessException {
    throw StateError('DV-MODULE-020: $id.\$op runs in Node, and there is '
        'none bundled beside the application, named by DARTVEL_NODE or on PATH.');
  }
  if (result.exitCode != 0) {
    throw StateError('$id.\$op failed: \${result.stderr}');
  }
  return jsonDecode(result.stdout as String);
}''';
