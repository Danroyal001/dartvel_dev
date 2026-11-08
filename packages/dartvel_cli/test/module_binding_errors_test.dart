// A generated carrier converts whatever the foreign side throws into a
// DVBindingError naming the module, the operation and the binding kind it
// crossed, keeping the original error -- for a call that answers at once, a
// Future and a Stream. A module of Dart crosses no foreign boundary and its
// errors are its own, so its carrier wraps nothing.
//
// Checked by running a generated backend carrier on the VM against the real
// dartvel_core, with carrier bodies that fail the way a foreign library
// does.
import 'dart:io';

import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/dart_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'dart_package_module_test.dart' show install, scratch, vendor;

const List<DVModuleOperation> _operations = <DVModuleOperation>[
  DVModuleOperation(name: 'crc', returnType: 'int', params: <DVModuleParam>[
    DVModuleParam(name: 'text', type: 'String'),
  ]),
  DVModuleOperation(
      name: 'fetch', returnType: 'Future<String>', params: <DVModuleParam>[]),
  DVModuleOperation(
      name: 'ticks', returnType: 'Stream<int>', params: <DVModuleParam>[]),
];

DVForeignModuleSpec spec(String kind) => DVForeignModuleSpec(
      id: 'zlib',
      kind: kind,
      source: 'c:zlib',
      operations: _operations,
      outcomes: <String, Map<DVModuleEnvironment, DVModuleOutcome>>{
        for (final DVModuleOperation op in _operations)
          op.name: <DVModuleEnvironment, DVModuleOutcome>{
            DVModuleEnvironment.native: DVModuleOutcome.unavailable,
            DVModuleEnvironment.web: DVModuleOutcome.unavailable,
            DVModuleEnvironment.backend: DVModuleOutcome.real,
          },
      },
      carriers: <DVModuleEnvironment, DVCarrierSource>{
        DVModuleEnvironment.backend: DVCarrierSource(
          body: (DVModuleOperation op) => switch (op.name) {
            'crc' => "throw StateError('zlib: bad input \$text')",
            'fetch' => "Future<String>.error('zlib: inflate failed')",
            _ => "Stream<int>.fromIterable(<int>[1]).map((int v) => "
                "v == 1 ? throw StateError('zlib: stream ended') : v)",
          },
        ),
      },
    );

void main() {
  test('a foreign kind wraps each real call with its binding kind; Dart '
      'wraps nothing', () {
    final String ffi =
        dvWriteForeignModule(spec('ffi')).files['lib/src/carrier_backend.dart']!;
    expect(ffi, contains("dvBindingCall<int>('zlib', 'crc', 'DVFfiBinding'"));
    expect(ffi,
        contains("dvBindingFuture<String>('zlib', 'fetch', 'DVFfiBinding'"));
    expect(ffi,
        contains("dvBindingStream<int>('zlib', 'ticks', 'DVFfiBinding'"));
    expect(dvWriteForeignModule(spec('npm')).files['lib/src/carrier_backend.dart'],
        contains("'DVNodeJsBinding'"));

    final String dart = dvWriteForeignModule(spec('dartPackage'))
        .files['lib/src/carrier_backend.dart']!;
    expect(dart, isNot(contains('dvBinding')));
  });

  test('a foreign error reaches the caller as a DVBindingError naming where '
      'it crossed', () async {
    final Directory root = scratch();
    final DVGeneratedModule module = dvWriteForeignModule(spec('ffi'));
    final String config =
        install(root, module, vendor(root, 'zlib', '// nothing\n'));
    final File probe = File(p.join(root.path, 'probe.dart'))
      ..writeAsStringSync('''
import 'package:dartvel_core/dartvel.dart';
import 'package:dv_zlib_module/src/carrier_backend.dart' as backend;

Future<void> main() async {
  try {
    backend.crc('x');
  } on DVBindingError catch (e) {
    print('\${e.module} \${e.operation} \${e.binding} \${e.error}');
  }
  try {
    await backend.fetch();
  } on DVBindingError catch (e) {
    print('\${e.operation} \${e.error}');
  }
  try {
    await backend.ticks().toList();
  } on DVBindingError catch (e) {
    print('\${e.operation} \${e.error}');
  }
}
''');
    final ProcessResult run = await Process.run(Platform.resolvedExecutable,
        <String>['--packages=$config', probe.path],
        workingDirectory: root.path);
    expect(
        '${run.stdout}${run.stderr}',
        'zlib crc DVFfiBinding Bad state: zlib: bad input x\n'
        'fetch zlib: inflate failed\n'
        'ticks Bad state: zlib: stream ended\n');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
