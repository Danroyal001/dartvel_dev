// Decoding a real obfuscated Dart stack with a real symbols file.
//
// The fixture is not recorded text: the test compiles a program with the
// flags Flutter's `--obfuscate --split-debug-info` uses for the AOT snapshot
// (`--obfuscate`, `--save-debugging-info`, DWARF stack traces), runs it, and
// captures the stack it prints. A hand-written header and offsets would pass
// a decoder that only recognises the hand-writer's idea of the format.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' hide Platform;
import 'package:dartvel_shelf/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const String _program = '''
class Checkout {
  void pay(int amount) {
    if (amount > 0) throw StateError('declined');
  }
}

void runCheckout() => Checkout().pay(5);

void main() {
  try {
    runCheckout();
  } catch (error, stack) {
    print(stack);
  }
}
''';

void main() {
  late Directory work;
  late String stack;
  late List<int> symbols;

  setUpAll(() {
    work = Directory.systemTemp.createTempSync('dv_native_stack_');
    final File source = File(p.join(work.path, 'crash.dart'))
      ..writeAsStringSync(_program);
    final String dart = Platform.resolvedExecutable;
    final String snapshot = p.join(work.path, 'app.aot');
    final String symbolsPath = p.join(work.path, 'app.symbols');
    final ProcessResult compiled = Process.runSync(dart, <String>[
      'compile',
      'aot-snapshot',
      '--extra-gen-snapshot-options=--dwarf-stack-traces-mode,--save-debugging-info=$symbolsPath,--obfuscate',
      '-o',
      snapshot,
      source.path,
    ]);
    if (compiled.exitCode != 0) {
      fail('could not compile the fixture program:\n${compiled.stderr}');
    }
    final String runtime = p.join(p.dirname(dart), 'dartaotruntime');
    final ProcessResult ran = Process.runSync(runtime, <String>[snapshot]);
    stack = '${ran.stdout}';
    symbols = File(symbolsPath).readAsBytesSync();
  });

  tearDownAll(() => work.deleteSync(recursive: true));

  test('the fixture really is an obfuscated native stack', () {
    expect(stack, contains('build_id:'));
    expect(stack, contains('isolate_dso_base'));
    expect(stack, isNot(contains('Checkout')));
    expect(stack, isNot(contains('crash.dart')));
  });

  test('the build id of the symbols file is the one the stack names', () {
    final String? fromFile = DVNativeStackSymbolizer.buildIdOf(symbols);
    final String? fromStack =
        RegExp(r"build_id: '([0-9a-f]+)'").firstMatch(stack)?.group(1);
    expect(fromFile, isNotNull);
    expect(fromFile, fromStack);
  });

  test('decodes the frames to the names and lines in the source', () async {
    final String? decoded = await const DVNativeStackSymbolizer()
        .decode(stack, symbolFiles: <List<int>>[symbols]);
    expect(decoded, isNotNull);
    expect(decoded, contains('Checkout.pay'));
    expect(decoded, contains('crash.dart:3'));
    expect(decoded, contains('runCheckout'));
    expect(decoded, contains('main'));
  });

  test('a file that is not symbols decodes nothing rather than guessing',
      () async {
    expect(
      await const DVNativeStackSymbolizer()
          .decode(stack, symbolFiles: <List<int>>[utf8.encode('not an ELF')]),
      isNull,
    );
    expect(DVNativeStackSymbolizer.buildIdOf(utf8.encode('not an ELF')), isNull);
  });

  test('finds the right file among several', () async {
    final String? decoded = await const DVNativeStackSymbolizer().decode(
      stack,
      symbolFiles: <List<int>>[utf8.encode('junk'), symbols],
    );
    expect(decoded, contains('Checkout.pay'));
  });

  test('end to end: the symbolicator turns a crash report back into source '
      'frames and groups it by them', () async {
    final DVMemorySymbolRepository repo = DVMemorySymbolRepository();
    await repo.putFile('1.0.0', 'app.symbols', symbols);
    await repo.putManifest(DVSymbolsManifest(
      release: '1.0.0',
      createdAt: DateTime.utc(2026, 10, 11),
      files: <DVSymbolFile>[
        DVSymbolFile(
          name: 'app.symbols',
          kind: DVSymbolKind.dartSymbols,
          sha256: dvSymbolSha256(symbols),
          bytes: symbols.length,
          buildId: DVNativeStackSymbolizer.buildIdOf(symbols),
        ),
      ],
    ));
    final List<DVCrashFrame> frames = DVCrashFrame.parse(stack);
    final DVCrashReport report = DVCrashReport(
      id: 'r1',
      kind: DVCrashKind.fatal,
      errorType: 'StateError',
      message: 'declined',
      frames: frames,
      fingerprint: DVCrashFingerprint.of(errorType: 'StateError', frames: frames),
      context: const DVCrashContext(release: '1.0.0', installId: 'i'),
      occurredAt: DateTime.utc(2026, 10, 11),
    );

    final DVCrashReport out = await DVRepositoryCrashSymbolicator(
      repository: repo,
      dartDecoder: const DVNativeStackSymbolizer(),
    ).symbolicate(report);

    expect(out.symbolicated, isTrue);
    expect(out.frames.map((DVCrashFrame f) => f.function),
        contains('Checkout.pay'));
    expect(out.frames.any((DVCrashFrame f) => (f.uri ?? '').endsWith('crash.dart')),
        isTrue);
    expect(out.fingerprint, isNot(report.fingerprint));
  });
}
