/// The one place a foreign source becomes a module package.
///
/// Every kind of source -- a Dart package, an npm package, a C or Rust
/// library, a WASM binary, a JVM artifact, an Apple framework -- ends as the
/// same shape: a pubspec that declares the module and its outcome per
/// operation and environment, a surface class the parent reaches as
/// `DV.Modules.<id>`, one carrier library per environment chosen by a
/// conditional import at compile time, a generated test and a README. What
/// differs between kinds is only how a `real` operation is carried, which
/// each kind supplies as a [DVCarrierSource]. Keeping the rest here is what
/// keeps six generators from becoming six slightly different module shapes.
///
/// The environment is chosen at compile time, never at run time: the web
/// build imports the web carrier and nothing else, so a package that needs
/// `dart:io` never reaches the browser bundle, and a module nothing calls on
/// a platform costs that platform nothing.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;

import '../described_api.dart';
import 'dart_surface.dart';
import 'rpc_codec.dart';

/// Thrown when a module cannot be generated as declared.
class DVModuleGenerationRefused implements Exception {
  const DVModuleGenerationRefused(this.code, this.message);

  /// The diagnostic: `DV-MODULE-010`, `DV-MODULE-014`, `DV-MODULE-017`.
  final String code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// How one kind carries its `real` operations into one environment.
class DVCarrierSource {
  const DVCarrierSource({
    this.imports = const <String>[],
    required this.body,
    this.declarations = '',
  });

  /// Directives the carrier library needs, written as they appear.
  final List<String> imports;

  /// The body of a real operation: an expression, after `=>`.
  final String Function(DVModuleOperation operation) body;

  /// Top-level declarations the carrier needs besides the operations: a
  /// loader, a binding table.
  final String declarations;
}

/// Everything a module package is generated from.
class DVForeignModuleSpec {
  DVForeignModuleSpec({
    required this.id,
    required this.kind,
    required this.source,
    required this.operations,
    required this.outcomes,
    required this.carriers,
    this.dependencies = const <String, String>{},
    this.skipped = const <String, String>{},
    this.description = '',
    this.exports = const <String>[],
    this.extraFiles = const <String, String>{},
    this.noopValues = const <String, String>{},
    this.pubspecExtra = '',
    this.targets = const <String>[],
    this.notes = const <String>[],
  });

  /// What the README says besides the table: why an environment has no
  /// carrier it could have had.
  final List<String> notes;

  /// The targets a native carrier reaches, when it reaches only some: a JVM
  /// library is `android` alone. Empty for every target.
  final List<String> targets;

  /// Top-level pubspec sections a kind needs besides the module block: the
  /// assets an npm module serves to the browser.
  final String pubspecExtra;

  /// What the parent calls it: `DV.Modules.<id>`.
  final String id;

  /// The kind the pubspec records: `dartPackage`, `npm`, `ffi`, `wasm`,
  /// `jvm`, `apple`.
  final String kind;

  /// The source descriptor it was resolved from, as `dartvel add` was given
  /// it: `pub:textkit@1.2.3`.
  final String source;

  final List<DVModuleOperation> operations;

  /// The declared outcome of each operation in each environment. Every
  /// operation has one for every environment: there is no default.
  final Map<String, Map<DVModuleEnvironment, DVModuleOutcome>> outcomes;

  /// How `real` operations are carried, per environment. An environment in
  /// which some operation is real must have one.
  final Map<DVModuleEnvironment, DVCarrierSource> carriers;

  /// Extra pubspec dependencies, name to the YAML value written after it.
  final Map<String, String> dependencies;

  /// Public operations of the source that the module does not expose, with
  /// the reason, for the README.
  final Map<String, String> skipped;

  final String description;

  /// Libraries the module's own library re-exports, so a caller can name
  /// the source's types. Only ever a library every environment can import.
  final List<String> exports;

  /// Kind-specific files: a header for ffigen, a JS shim, a build hook.
  final Map<String, String> extraFiles;

  /// What a `noop` operation returns, by operation, when it returns a value.
  final Map<String, String> noopValues;

  String get packageName => 'dv_${dvSnake(id)}_module';

  String get surfaceClass => '${dvClassName(id)}Module';
}

/// The environments in the order a pubspec lists them.
const List<DVModuleEnvironment> dvModuleEnvironments = <DVModuleEnvironment>[
  DVModuleEnvironment.native,
  DVModuleEnvironment.web,
  DVModuleEnvironment.backend,
];

/// Generates the package for [spec].
DVGeneratedModule dvWriteForeignModule(DVForeignModuleSpec spec) {
  if (spec.operations.isEmpty) {
    throw DVModuleGenerationRefused(
      'DV-MODULE-010',
      '${spec.source} resolved but exposes no operation every environment '
          'can call${spec.skipped.isEmpty ? '' : ': ${spec.skipped.entries.map((MapEntry<String, String> e) => '${e.key} ${e.value}').join('; ')}'}.',
    );
  }
  for (final DVModuleOperation op in spec.operations) {
    final Map<DVModuleEnvironment, DVModuleOutcome>? declared =
        spec.outcomes[op.name];
    for (final DVModuleEnvironment env in dvModuleEnvironments) {
      final DVModuleOutcome? outcome = declared?[env];
      if (outcome == null) {
        throw DVModuleGenerationRefused(
          'DV-MODULE-014',
          '${spec.id}.${op.name} declares nothing for ${env.name}. Every '
              'operation declares real, compat, noop or unavailable for '
              'native, web and backend; there is no default.',
        );
      }
      if (outcome == DVModuleOutcome.real && spec.carriers[env] == null) {
        throw DVModuleGenerationRefused(
          'DV-MODULE-017',
          '${spec.id}.${op.name} is declared real on ${env.name}, and '
              '${spec.kind} has no carrier there.',
        );
      }
      if (outcome == DVModuleOutcome.compat) {
        final String? why = dvBackendRpcRefusal(op, spec, env);
        if (why != null) {
          throw DVModuleGenerationRefused(
            'DV-MODULE-017',
            '${spec.id}.${op.name} is declared compat on ${env.name}, and '
                'it cannot be carried to the backend: $why. Declare '
                'unavailable or noop instead.',
          );
        }
      }
      if (outcome == DVModuleOutcome.noop && !_canNoop(op, spec)) {
        throw DVModuleGenerationRefused(
          'DV-MODULE-017',
          '${spec.id}.${op.name} is declared noop on ${env.name} and returns '
              '${op.returnType}, which has no value that means nothing '
              'happened. Declare unavailable, or name the value it returns.',
        );
      }
    }
  }

  final String lib = dvSnake(spec.packageName);
  final Map<String, String> files = <String, String>{
    'pubspec.yaml': _pubspec(spec),
    'README.md': _readme(spec),
    'lib/$lib.dart': _surface(spec, lib),
    for (final DVModuleEnvironment env in dvModuleEnvironments)
      'lib/src/carrier_${env.name}.dart': _carrier(spec, env),
    'test/${lib}_test.dart': _test(spec, lib),
    ...spec.extraFiles,
  };
  final Map<String, String> ordered = Map<String, String>.fromEntries(
      files.entries.toList()
        ..sort((MapEntry<String, String> a, MapEntry<String, String> b) =>
            a.key.compareTo(b.key)));
  return DVGeneratedModule(
    id: spec.id,
    packageName: spec.packageName,
    host: '',
    files: ordered,
  );
}

/// The hash a lock entry pins: every generated file, in order, with its path.
///
/// Stable for the same files on any machine, so a regeneration that changes
/// a single byte of a wrapper is seen as a different wrapper.
String dvWrapperHash(Map<String, String> files) {
  final List<int> bytes = <int>[];
  for (final String path in files.keys.toList()..sort()) {
    bytes
      ..addAll(utf8.encode(path))
      ..add(0)
      ..addAll(utf8.encode(files[path]!))
      ..add(0);
  }
  return sha256.convert(bytes).toString();
}

bool _canNoop(DVModuleOperation op, DVForeignModuleSpec spec) {
  if (spec.noopValues.containsKey(op.name)) return true;
  final String t = op.returnType;
  return t == 'void' ||
      t == 'Future<void>' ||
      t.endsWith('?') ||
      t == 'dynamic' ||
      RegExp(r'^Future<.*\?>$').hasMatch(t) ||
      t.startsWith('Stream<');
}

String _pubspec(DVForeignModuleSpec spec) {
  final StringBuffer out = StringBuffer()
    ..writeln('# GENERATED by dartvel add from ${spec.source}.')
    ..writeln('#')
    ..writeln('# Regenerate with dartvel add --refresh ${spec.id}. A hand edit')
    ..writeln('# changes the wrapper hash the lock pins (DV-MODULE-016).')
    ..writeln('name: ${spec.packageName}')
    ..writeln('description: ${dvYamlScalar(spec.description.isEmpty ? '${spec.source}, as a Dartvel module.' : spec.description)}')
    ..writeln('publish_to: none')
    ..writeln('version: 0.0.1')
    ..writeln()
    ..writeln('environment:')
    ..writeln('  sdk: ">=3.13.0 <4.0.0"')
    ..writeln()
    ..writeln('dependencies:')
    // The first release with DVModuleRpc, which a call carried to the
    // backend needs.
    ..writeln('  dartvel_core: ^0.9.0');
  for (final MapEntry<String, String> dep in spec.dependencies.entries) {
    out.writeln('  ${dep.key}: ${dep.value}');
  }
  if (spec.pubspecExtra.isNotEmpty) {
    out
      ..writeln()
      ..write(spec.pubspecExtra);
  }
  out
    ..writeln()
    ..writeln('dartvel:')
    ..writeln('  module:')
    ..writeln('    id: ${spec.id}')
    ..writeln('    kind: ${spec.kind}')
    ..writeln('    source: ${dvYamlScalar(spec.source)}')
    ..writeln('    surface: ${spec.surfaceClass}')
    ..write(spec.targets.isEmpty ? '' : '    targets: [${spec.targets.join(', ')}]\n')
    ..writeln('    operations:');
  for (final DVModuleOperation op in spec.operations) {
    out.writeln('      ${op.name}:');
    for (final DVModuleEnvironment env in dvModuleEnvironments) {
      out.writeln('        ${env.name}: ${_outcomeYaml(spec.outcomes[op.name]![env]!)}');
    }
  }
  return out.toString();
}

String _surface(DVForeignModuleSpec spec, String lib) {
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED by dartvel add from ${spec.source}. Do not edit.')
    ..writeln('//')
    ..writeln('// The environment is chosen when the application is compiled:')
    ..writeln('// a browser build imports the web carrier, a device build the')
    ..writeln('// native one, the backend the backend one. Nothing a carrier')
    ..writeln("// does not need reaches that environment's build.")
    ..writeln('library;')
    ..writeln()
    ..write(_typedData(spec))
    ..writeln("import 'src/carrier_backend.dart'")
    ..writeln("    if (dart.library.js_interop) 'src/carrier_web.dart'")
    ..writeln("    if (dart.library.ui) 'src/carrier_native.dart' as carrier;");
  for (final String library in spec.exports) {
    out.writeln("export '$library';");
  }
  out
    ..writeln()
    ..writeln('/// ${spec.source}, as the `${spec.id}` module.')
    ..writeln('///')
    ..writeln('/// Reached as `DV.Modules.${dvCamel(spec.id)}`. What each operation')
    ..writeln('/// does in each environment is declared in this package\'s')
    ..writeln('/// pubspec and listed in its README.')
    ..writeln('class ${spec.surfaceClass} {')
    ..writeln('  const ${spec.surfaceClass}();');
  for (final DVModuleOperation op in spec.operations) {
    out.writeln();
    if (op.doc.isNotEmpty) out.writeln('  /// ${op.doc}');
    out.writeln('  ${op.returnType} ${op.name}(${op.parameterList}) =>');
    out.writeln('      carrier.${op.name}(${op.argumentList});');
  }
  out.writeln('}');
  return out.toString();
}

String _carrier(DVForeignModuleSpec spec, DVModuleEnvironment env) {
  final List<DVModuleOperation> real = <DVModuleOperation>[
    for (final DVModuleOperation op in spec.operations)
      if (spec.outcomes[op.name]![env] == DVModuleOutcome.real) op,
  ];
  final bool throws = spec.operations.any((DVModuleOperation op) =>
      spec.outcomes[op.name]![env] == DVModuleOutcome.unavailable);
  final DVCarrierSource? carrier = real.isEmpty ? null : spec.carriers[env];
  final bool sends = spec.operations.any((DVModuleOperation op) =>
      spec.outcomes[op.name]![env] == DVModuleOutcome.compat);
  // The backend answers the calls other environments send it.
  final List<DVModuleOperation> answers = env == DVModuleEnvironment.backend
      ? <DVModuleOperation>[
          for (final DVModuleOperation op in spec.operations)
            if (spec.outcomes[op.name]!.values.contains(DVModuleOutcome.compat))
              op,
        ]
      : const <DVModuleOperation>[];
  final List<String> core = <String>[
    if (throws) ...<String>['DVModuleEnvironment', 'DVModuleUnavailable'],
    if (sends || answers.isNotEmpty) 'DVModuleRpc',
    if (answers.isNotEmpty) 'DVModuleRpcRefused',
  ]..sort();
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED by dartvel add from ${spec.source}. Do not edit.')
    ..writeln('//')
    ..writeln('// The ${env.name} carrier: what each operation does when the')
    ..writeln('// application runs ${_where(env)}.')
    ..writeln('library;')
    ..writeln();
  final List<String> imports = <String>[
    if (_usesTypedData(spec)) "import 'dart:typed_data';",
    if (core.isNotEmpty)
      "import 'package:dartvel_core/dartvel.dart'\n"
          '    show ${core.join(', ')};',
    ...?carrier?.imports,
  ];
  for (final String line in imports) {
    out.writeln(line);
  }
  if (imports.isNotEmpty) out.writeln();
  if (carrier != null && carrier.declarations.isNotEmpty) {
    out
      ..writeln(carrier.declarations.trimRight())
      ..writeln();
  }
  for (final DVModuleOperation op in spec.operations) {
    final DVModuleOutcome outcome = spec.outcomes[op.name]![env]!;
    final String head = '${op.returnType} ${op.name}(${op.parameterList})';
    switch (outcome) {
      case DVModuleOutcome.real:
        out.writeln('$head =>\n    ${carrier!.body(op)};');
      case DVModuleOutcome.unavailable:
        out.writeln('$head =>\n    throw const DVModuleUnavailable('
            "'${spec.id}', '${op.name}', DVModuleEnvironment.${env.name});");
      case DVModuleOutcome.noop:
        out.writeln(_noop(op, head, spec.noopValues[op.name]));
      case DVModuleOutcome.compat:
        out.writeln(_backendCall(spec, op, head));
    }
    out.writeln();
  }
  if (answers.isNotEmpty) out.write(_dispatcher(spec, answers));
  return '${out.toString().trimRight()}\n';
}

String _noop(DVModuleOperation op, String head, String? value) {
  final String t = op.returnType;
  if (value != null) {
    return t.startsWith('Future<') ? '$head async => $value;' : '$head => $value;';
  }
  if (t == 'void') return '$head {}';
  if (t.startsWith('Future<')) return '$head async ${t == 'Future<void>' ? '{}' : '=> null;'}';
  if (t.startsWith('Stream<')) return '$head => const Stream.empty();';
  return '$head => null;';
}

String _where(DVModuleEnvironment env) => switch (env) {
      DVModuleEnvironment.native => 'on a device',
      DVModuleEnvironment.web => 'in a browser',
      DVModuleEnvironment.backend => 'on the backend',
    };

String _readme(DVForeignModuleSpec spec) {
  final StringBuffer out = StringBuffer()
    ..writeln('# ${spec.id}')
    ..writeln()
    ..writeln('Generated by `dartvel add ${spec.source}`. Reached as '
        '`DV.Modules.${dvCamel(spec.id)}`.')
    ..writeln()
    ..writeln('Do not edit this package: regenerate it with '
        '`dartvel add --refresh ${spec.id}`. A hand edit is lost and changes '
        'the wrapper hash `dartvel.module.lock` pins (DV-MODULE-016).')
    ..writeln()
    ..writeln('## Operations')
    ..writeln()
    ..writeln('| Operation | native | web | backend |')
    ..writeln('|---|---|---|---|');
  for (final DVModuleOperation op in spec.operations) {
    out.writeln('| `${op.returnType} ${op.name}(${op.parameterList})` | '
        '${dvModuleEnvironments.map((DVModuleEnvironment e) => spec.outcomes[op.name]![e]!.name).join(' | ')} |');
  }
  out
    ..writeln()
    ..writeln('`real` runs the implementation. `noop` does nothing and returns '
        'nothing. `unavailable` throws `DVModuleUnavailable` naming the '
        'module, the operation and the environment, and the build refuses a '
        'call it can see reaching one (DV-MODULE-013).');
  if (spec.notes.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Notes')
      ..writeln();
    for (final String note in spec.notes) {
      out.writeln('- $note');
    }
  }
  if (spec.skipped.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Not exposed')
      ..writeln()
      ..writeln('The source has these, and the module does not carry them:')
      ..writeln();
    for (final MapEntry<String, String> e in spec.skipped.entries) {
      out.writeln('- `${e.key}` ${e.value}.');
    }
  }
  return out.toString();
}

String _test(DVForeignModuleSpec spec, String lib) {
  final List<DVModuleOperation> unavailable = <DVModuleOperation>[
    for (final DVModuleOperation op in spec.operations)
      if (spec.outcomes[op.name]![DVModuleEnvironment.backend] ==
              DVModuleOutcome.unavailable &&
          op.params.every((DVModuleParam p) => !p.required))
        op,
  ];
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED by dartvel add from ${spec.source}.')
    ..writeln('//')
    ..writeln('// Runs on the Dart VM, which is the backend environment.')
    ..writeln("import 'package:${spec.packageName}/$lib.dart';")
    ..writeln("import 'package:dartvel_core/dartvel.dart';")
    ..writeln("import 'package:test/test.dart';")
    ..writeln()
    ..writeln('void main() {')
    ..writeln("  test('the module is its declared surface', () {")
    ..writeln('    expect(const ${spec.surfaceClass}(), isNotNull);')
    ..writeln('  });');
  for (final DVModuleOperation op in unavailable) {
    out
      ..writeln()
      ..writeln("  test('${op.name} is unavailable on the backend', () {")
      ..writeln('    expect(() => const ${spec.surfaceClass}().${op.name}(),')
      ..writeln('        throwsA(isA<DVModuleUnavailable>()));')
      ..writeln('  });');
  }
  out.writeln('}');
  return out.toString();
}

bool _usesTypedData(DVForeignModuleSpec spec) => spec.operations.any(
    (DVModuleOperation op) =>
        op.returnType.contains('Uint8List') ||
        op.params.any((DVModuleParam p) => p.type.contains('Uint8List')));

String _typedData(DVForeignModuleSpec spec) =>
    _usesTypedData(spec) ? "import 'dart:typed_data';\n\n" : '';

/// Why [op] cannot be carried from [env] to the backend, or null when it
/// can: the backend must run it, the answer must come later, and every value
/// must be one JSON carries.
String? dvBackendRpcRefusal(
    DVModuleOperation op, DVForeignModuleSpec spec, DVModuleEnvironment env) {
  if (env == DVModuleEnvironment.backend) {
    return 'the backend is where the call would go';
  }
  if (spec.outcomes[op.name]?[DVModuleEnvironment.backend] !=
      DVModuleOutcome.real) {
    return 'it is not real on the backend';
  }
  return dvRpcTypeRefusal(op);
}

/// Why [op]'s values cannot cross to the backend, or null when they can.
String? dvRpcTypeRefusal(DVModuleOperation op) {
  final String? answer = dvRpcAnswerType(op.returnType);
  if (answer == null) {
    return 'it returns ${op.returnType}, and a call to the backend can only '
        'answer later, as a Future';
  }
  if (answer != 'void' && dvRpcDecode(answer, 'r') == null) {
    return 'it returns $answer, which JSON does not carry';
  }
  for (final DVModuleParam param in op.params) {
    if (dvRpcDecode(param.type, 'a') == null) {
      return 'its parameter ${param.name} is ${param.type}, which JSON does '
          'not carry';
    }
  }
  return null;
}

String _outcomeYaml(DVModuleOutcome outcome) =>
    outcome == DVModuleOutcome.compat ? '{compat: backend}' : outcome.name;

/// A client operation that sends the call to the backend.
String _backendCall(
    DVForeignModuleSpec spec, DVModuleOperation op, String head) {
  final String answer = dvRpcAnswerType(op.returnType)!;
  final String args = op.params
      .map((DVModuleParam p) => "'${p.name}': ${p.name}")
      .join(', ');
  final String send = "DVModuleRpc.call('${spec.id}', '${op.name}', "
      '<String, Object?>{$args})';
  return answer == 'void'
      ? '$head =>\n    $send.then((Object? _) {});'
      : '$head =>\n    $send\n        .then((Object? r) => ${dvRpcDecode(answer, 'r')});';
}

/// The backend's half: runs a call another environment sent, by name.
///
/// Only operations some environment carries here are answered; anything
/// else is refused rather than run, so the route cannot reach an operation
/// the module never offered to the network.
String _dispatcher(
    DVForeignModuleSpec spec, List<DVModuleOperation> answers) {
  final StringBuffer out = StringBuffer()
    ..writeln()
    ..writeln(r'/// Runs the operation named [dv$operation] with the JSON')
    ..writeln(r'/// [dv$arguments] another environment sent, answering with JSON.')
    ..writeln('Future<Object?> dvModuleDispatch(')
    ..writeln(r'    String dv$operation, Map<String, Object?> dv$arguments) async {')
    ..writeln(r'  switch (dv$operation) {');
  for (final DVModuleOperation op in answers) {
    final List<String> positional = <String>[];
    final List<String> named = <String>[];
    for (final DVModuleParam p in op.params) {
      final String read = dvRpcDecode(p.type, "dv\$arguments['${p.name}']")!;
      if (p.named) {
        named.add('${p.name}: $read');
      } else {
        positional.add(read);
      }
    }
    final String call = '${op.name}(${<String>[...positional, ...named].join(', ')})';
    final bool isVoid = dvRpcAnswerType(op.returnType) == 'void';
    out
      ..writeln("    case '${op.name}':")
      ..writeln(isVoid
          ? '      await $call;\n      return null;'
          : '      return DVModuleRpc.encode(await $call);');
  }
  out
    ..writeln('  }')
    ..writeln("  throw DVModuleRpcRefused('${spec.id}', dv\$operation,")
    ..writeln("      'the module does not carry it to the backend');")
    ..writeln('}');
  return out.toString();
}
