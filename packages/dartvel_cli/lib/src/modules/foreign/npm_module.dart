/// An npm package, as a module.
///
/// Two carriers. In a browser the package is served as one ES module among
/// the application's assets and loaded with a dynamic `import()` on the
/// first call, through `dart:js_interop` -- web standards, no framework. On
/// the backend it runs in Node, one process per call, with the arguments and
/// the answer as JSON. A device has no JavaScript engine, so there the
/// module declares what `--elsewhere` says: unavailable or noop.
///
/// A package that imports other packages is bundled with esbuild, pinned to
/// one version so the same source bundles to the same bytes; one that
/// imports nothing is served as it is.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;
import 'package:path/path.dart' as p;

import '../described_api.dart';
import 'dart_surface.dart';
import 'module_writer.dart';
import 'node_carrier.dart';
import 'npm_surface.dart';
import 'resolver.dart';

/// The esbuild a bundle is made with. Pinned: a bundler that floats makes a
/// wrapper whose hash changes with nothing else changing (DV-BIND-002).
const String dvEsbuildVersion = '0.24.2';

/// The two files a package is served as: one for a browser, one for Node.
class DVNpmBundles {
  const DVNpmBundles({required this.browser, required this.node});
  final String browser;
  final String node;
}

/// Makes the browser and Node bundles for [surface].
///
/// Served as it is when the entry is already an ES module that imports
/// nothing; bundled with esbuild otherwise.
Future<DVNpmBundles> dvBundleNpm(
  DVNpmSurface surface, {
  DVSourceFetcher fetcher = const DVSourceFetcher(),
}) async {
  final String entry = p.join(surface.directory, surface.entry);
  final String code = File(entry).readAsStringSync();
  final bool esm = entry.endsWith('.mjs') ||
      RegExp(r'^\s*export\s', multiLine: true).hasMatch(code);
  final bool imports =
      RegExp(r'''(?:^|\s)import\s[^;]*from\s+['"]|import\(|require\(''')
          .hasMatch(code);
  if (esm && !imports && !surface.hasDependencies) {
    return DVNpmBundles(browser: code, node: code);
  }
  Future<String> bundle(String platform) async {
    final Directory out = Directory.systemTemp.createTempSync('dv_esbuild_');
    try {
      final String file = p.join(out.path, 'bundle.mjs');
      await fetcher.run(
        'npx',
        <String>[
          '--yes',
          'esbuild@$dvEsbuildVersion',
          entry,
          '--bundle',
          '--format=esm',
          '--platform=$platform',
          '--log-level=error',
          '--outfile=$file',
        ],
        workingDirectory: surface.directory,
      );
      return File(file).readAsStringSync();
    } finally {
      out.deleteSync(recursive: true);
    }
  }

  return DVNpmBundles(
    browser: surface.web ? await bundle('browser') : '',
    node: surface.node ? await bundle('node') : '',
  );
}

/// The module spec for an npm package.
DVForeignModuleSpec dvNpmModuleSpec({
  required String id,
  required String source,
  required DVNpmSurface surface,
  required DVNpmBundles bundles,
  DVModuleOutcome elsewhere = DVModuleOutcome.unavailable,
}) {
  final String packageName = 'dv_${dvSnake(id)}_module';
  final String asset = 'assets/npm/${dvSnake(surface.name)}.mjs';
  final Map<DVModuleEnvironment, bool> runs = <DVModuleEnvironment, bool>{
    // A desktop runs it in the Node dartvel build bundles beside it.
    DVModuleEnvironment.native: surface.node,
    DVModuleEnvironment.web: surface.web,
    DVModuleEnvironment.backend: surface.node,
  };
  final String digest =
      sha256.convert(utf8.encode(bundles.node)).toString().substring(0, 16);

  return DVForeignModuleSpec(
    id: id,
    kind: 'npm',
    source: source,
    description: '${surface.name} ${surface.version}, as a Dartvel module.',
    operations: surface.operations,
    outcomes: <String, Map<DVModuleEnvironment, DVModuleOutcome>>{
      for (final DVModuleOperation op in surface.operations)
        op.name: <DVModuleEnvironment, DVModuleOutcome>{
          for (final DVModuleEnvironment env in dvModuleEnvironments)
            env: runs[env]! ? DVModuleOutcome.real : elsewhere,
        },
    },
    carriers: <DVModuleEnvironment, DVCarrierSource>{
      if (surface.web)
        DVModuleEnvironment.web: DVCarrierSource(
          imports: const <String>[
            "import 'dart:js_interop';",
            "import 'dart:js_interop_unsafe';",
          ],
          declarations: _webLoader(id, packageName, asset),
          body: (DVModuleOperation op) =>
              "_call('${op.name}', <Object?>[${_args(op)}])${_convert(op)}",
        ),
      if (surface.node)
        DVModuleEnvironment.backend: DVCarrierSource(
          imports: const <String>[
            "import 'dart:convert';",
            "import 'dart:io';",
          ],
          declarations: _nodeRunner(id, packageName, digest, bundles.node),
          body: (DVModuleOperation op) =>
              "_call('${op.name}', <Object?>[${_args(op)}])${_convert(op)}",
        ),
      if (surface.node)
        DVModuleEnvironment.native: DVCarrierSource(
          imports: const <String>[
            "import 'dart:convert';",
            "import 'dart:io';",
          ],
          declarations: _nodeRunner(id, packageName, digest, bundles.node),
          body: (DVModuleOperation op) =>
              "_call('${op.name}', <Object?>[${_args(op)}])${_convert(op)}",
        ),
    },
    targets: surface.node ? dvNodeTargets : const <String>[],
    skipped: surface.skipped,
    extraFiles: <String, String>{
      if (surface.web) asset: bundles.browser,
    },
    pubspecExtra: surface.web
        ? 'flutter:\n  assets:\n    - assets/npm/\n'
        : '',
  );
}

String _args(DVModuleOperation op) =>
    op.params.map((DVModuleParam p) => p.name).join(', ');

/// Turns the decoded answer into the declared type.
String _convert(DVModuleOperation op) {
  final String t = RegExp(r'^Future<(.+)>$').firstMatch(op.returnType)!.group(1)!;
  if (t == 'void') return '.then((Object? _) {})';
  if (t == 'Object?' || t == 'Null') return '';
  if (t.startsWith('List<')) {
    return '.then((Object? r) => (r! as List<Object?>).cast<${t.substring(5, t.length - 1)}>())';
  }
  if (t.startsWith('Map<')) {
    return '.then((Object? r) => (r! as Map<Object?, Object?>).cast<${t.substring(4, t.length - 1)}>())';
  }
  return '.then((Object? r) => r! as $t)';
}

String _webLoader(String id, String packageName, String asset) => '''
/// The package, once the first call has loaded it.
JSObject? _module;

/// Loads the package from the application's assets, resolved against the
/// page's base URI so a deep route still finds it.
Future<JSObject> _load() async {
  final JSObject? loaded = _module;
  if (loaded != null) return loaded;
  final String base =
      ((globalContext['document']! as JSObject)['baseURI']! as JSString).toDart;
  final String url =
      Uri.parse(base).resolve('assets/packages/$packageName/$asset').toString();
  return _module = await importModule(url.toJS).toDart;
}

/// Calls [name] with [args], awaiting a promise when one comes back.
///
/// Trailing absent arguments are dropped rather than passed as null, so a
/// JavaScript default applies as it would to a caller who left it out.
Future<Object?> _call(String name, List<Object?> args) async {
  while (args.isNotEmpty && args.last == null) {
    args.removeLast();
  }
  final JSObject module = await _load();
  JSAny? result = module.callMethodVarArgs<JSAny?>(
      name.toJS, <JSAny?>[for (final Object? a in args) a.jsify()]);
  if (result != null && result.isA<JSPromise<JSAny?>>()) {
    result = await (result as JSPromise<JSAny?>).toDart;
  }
  return result.dartify();
}''';

String _nodeRunner(
        String id, String packageName, String digest, String bundle) =>
    '''
/// The package, bundled for Node, as base64 so no character in it can end
/// the string it is written in.
const String _bundle =
    '${base64Encode(utf8.encode(bundle))}';

/// Where the bundle is written for Node to import, once per process.
String? _path;

$dvNodeLocator

/// What Node runs: import the bundle, call one function, print the answer.
const String _runner = r"""
import { pathToFileURL } from 'node:url';
const [file, name, args] = process.argv.slice(1);
const m = await import(pathToFileURL(file).href);
const r = await m[name](...JSON.parse(args));
process.stdout.write(JSON.stringify(r === undefined ? null : r));
""";

Future<Object?> _call(String name, List<Object?> args) async {
  while (args.isNotEmpty && args.last == null) {
    args.removeLast();
  }
  final String path = _path ??= () {
    final File file = File('\${Directory.systemTemp.path}/${packageName}_$digest.mjs');
    if (!file.existsSync()) file.writeAsBytesSync(base64Decode(_bundle));
    return file.path;
  }();
  final ProcessResult result;
  try {
    result = await Process.run(_node, <String>[
      '--input-type=module', '-e', _runner, path, name, jsonEncode(args),
    ]);
  } on ProcessException {
    throw StateError('DV-MODULE-020: $id.\$name runs in Node, and there is '
        'none bundled beside the application, named by DARTVEL_NODE or on PATH.');
  }
  if (result.exitCode != 0) {
    throw StateError('$id.\$name failed in Node: \${result.stderr}');
  }
  return jsonDecode(result.stdout as String);
}''';
