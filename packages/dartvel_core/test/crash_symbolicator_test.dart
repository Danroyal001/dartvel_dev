// Reading a crash with the symbols of the release it came from.
//
// The ways this goes wrong are all quiet: a stack read with another
// release's mapping (a wrong method name on a believable line), a group id
// computed from obfuscated names (so one bug splits into a group per
// release), a decoder that throws and takes the report down with it, and a
// Dart stack decoded with a file for another architecture.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

import 'fixtures/r8_mapping.dart';

DVCrashReport jvmReport({
  String release = '1.4.0',
  String errorType = 'a.b',
  List<DVCrashFrame>? frames,
}) {
  final List<DVCrashFrame> stack = frames ??
      const <DVCrashFrame>[
        DVCrashFrame(function: 'onCreate', uri: 'jvm:a.a.a', line: 2),
        DVCrashFrame(function: 'onCreate', uri: 'jvm:a.a.a', line: 4),
        DVCrashFrame(function: 'performCreate', uri: 'jvm:android.app.Activity', line: 8000),
      ];
  return DVCrashReport(
    id: 'r1',
    kind: DVCrashKind.fatal,
    errorType: errorType,
    message: 'gateway down',
    frames: stack,
    fingerprint: DVCrashFingerprint.of(errorType: errorType, frames: stack),
    context: DVCrashContext(release: release, installId: 'i1', platform: 'android'),
    occurredAt: DateTime.utc(2026, 10, 11),
  );
}

DVSymbolsManifest manifest(String release, List<DVSymbolFile> files) =>
    DVSymbolsManifest(
        release: release, createdAt: DateTime.utc(2026, 10, 11), files: files);

Future<DVMemorySymbolRepository> repoWithMapping(String release) async {
  final DVMemorySymbolRepository repo = DVMemorySymbolRepository();
  await repo.putFile(release, 'mapping.txt', utf8.encode(r8Mapping));
  await repo.putManifest(manifest(release, <DVSymbolFile>[
    DVSymbolFile(
      name: 'mapping.txt',
      kind: DVSymbolKind.r8Mapping,
      sha256: dvSymbolSha256(utf8.encode(r8Mapping)),
      bytes: utf8.encode(r8Mapping).length,
    ),
  ]));
  return repo;
}

// A Dart stack as `--obfuscate --split-debug-info` builds print it.
const String nativeStack = '''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 4242, tid: 4300, name 1.ui
os: android arch: arm64 comp: no sim: no
build_id: 'c0ffee00c0ffee00c0ffee00c0ffee00'
isolate_dso_base: 7a1c000000, vm_dso_base: 7a1c000000
isolate_instructions: 7a1c0a1000, vm_instructions: 7a1c0a0000
    #00 abs 0000007a1c1b2345 virt 00000000001b2345 _kDartIsolateSnapshotInstructions+0x11234
    #01 abs 0000007a1c1b3456 virt 00000000001b3456 _kDartIsolateSnapshotInstructions+0x12345''';

DVCrashReport dartReport({String release = '1.4.0'}) {
  final List<DVCrashFrame> frames = DVCrashFrame.parse(nativeStack);
  return DVCrashReport(
    id: 'd1',
    kind: DVCrashKind.fatal,
    errorType: 'StateError',
    message: 'bad',
    frames: frames,
    fingerprint: DVCrashFingerprint.of(errorType: 'StateError', frames: frames),
    context: DVCrashContext(release: release, installId: 'i1', platform: 'android'),
    occurredAt: DateTime.utc(2026, 10, 11),
  );
}

class _FakeDecoder implements DVDartStackDecoder {
  _FakeDecoder({this.answer, this.fails = false});
  final String? answer;
  final bool fails;
  String? sawStack;
  int sawFiles = -1;

  @override
  Future<String?> decode(String stack, {required List<List<int>> symbolFiles}) async {
    sawStack = stack;
    sawFiles = symbolFiles.length;
    if (fails) throw StateError('corrupt symbols');
    return answer;
  }
}

void main() {
  group('JVM frames', () {
    test('are retraced with the mapping of the release that crashed', () async {
      final DVCrashSymbolicator symbolicator =
          DVRepositoryCrashSymbolicator(repository: await repoWithMapping('1.4.0'));
      final DVCrashReport out = await symbolicator.symbolicate(jvmReport());

      expect(out.symbolicated, isTrue);
      expect(out.errorType, 'com.example.shop.PaymentGateway');
      // Line 2 -> onCreate:13; line 4 is an inlined chain of two frames.
      expect(out.frames.map((DVCrashFrame f) => f.function), <String>[
        'onCreate', 'validate', 'onCreate', 'performCreate',
      ]);
      expect(out.frames.map((DVCrashFrame f) => f.line), <int?>[13, 30, 15, 8000]);
      expect(out.frames.first.uri, 'jvm:com.example.shop.CheckoutActivity');
      // A framework frame passes through untouched.
      expect(out.frames.last.uri, 'jvm:android.app.Activity');
    });

    test('are not read with another release\'s mapping', () async {
      final DVCrashSymbolicator symbolicator =
          DVRepositoryCrashSymbolicator(repository: await repoWithMapping('1.3.0'));
      final DVCrashReport report = jvmReport(release: '1.4.0');
      final DVCrashReport out = await symbolicator.symbolicate(report);
      expect(out.symbolicated, isFalse);
      expect(out.frames.map((DVCrashFrame f) => f.function),
          report.frames.map((DVCrashFrame f) => f.function));
      expect(out.errorType, 'a.b');
    });

    test('with no symbols at all the report says so and is otherwise untouched',
        () async {
      final DVCrashReport report = jvmReport();
      final DVCrashReport out =
          await DVRepositoryCrashSymbolicator(repository: DVMemorySymbolRepository())
              .symbolicate(report);
      expect(out.symbolicated, isFalse);
      expect(out.fingerprint, report.fingerprint);
    });

    test('the group id comes from the original names, so a bug keeps its group '
        'across releases', () async {
      final DVCrashReport out = await DVRepositoryCrashSymbolicator(
              repository: await repoWithMapping('1.4.0'))
          .symbolicate(jvmReport());
      expect(
        out.fingerprint,
        DVCrashFingerprint.of(errorType: out.errorType, frames: out.frames),
      );
      expect(out.fingerprint, isNot(jvmReport().fingerprint));
    });

    test('a mapping that cannot be read leaves the report as it was', () async {
      final DVMemorySymbolRepository repo = DVMemorySymbolRepository();
      await repo.putFile('1.4.0', 'mapping.txt', <int>[0xff, 0xfe, 0xfd]);
      await repo.putManifest(manifest('1.4.0', <DVSymbolFile>[
        const DVSymbolFile(
            name: 'mapping.txt', kind: DVSymbolKind.r8Mapping, sha256: 'x', bytes: 3),
      ]));
      final DVCrashReport report = jvmReport();
      final DVCrashReport out =
          await DVRepositoryCrashSymbolicator(repository: repo).symbolicate(report);
      expect(out.frames.length, report.frames.length);
    });
  });

  group('Dart frames', () {
    Future<DVMemorySymbolRepository> repoWithDart({String? buildId}) async {
      final DVMemorySymbolRepository repo = DVMemorySymbolRepository();
      await repo.putFile('1.4.0', 'app.android-arm64.symbols', <int>[1, 2, 3]);
      await repo.putFile('1.4.0', 'app.android-arm.symbols', <int>[4, 5, 6]);
      await repo.putManifest(manifest('1.4.0', <DVSymbolFile>[
        DVSymbolFile(
          name: 'app.android-arm64.symbols',
          kind: DVSymbolKind.dartSymbols,
          sha256: 'a',
          bytes: 3,
          arch: 'arm64',
          buildId: buildId ?? 'c0ffee00c0ffee00c0ffee00c0ffee00',
        ),
        const DVSymbolFile(
          name: 'app.android-arm.symbols',
          kind: DVSymbolKind.dartSymbols,
          sha256: 'b',
          bytes: 3,
          arch: 'arm',
          buildId: '11111111111111111111111111111111',
        ),
      ]));
      return repo;
    }

    test('an obfuscated native stack is decoded with the file of its build id',
        () async {
      final _FakeDecoder decoder = _FakeDecoder(answer: '''
#0      Checkout.pay (package:shop/checkout.dart:88:7)
#1      main (package:shop/main.dart:12:3)''');
      final DVCrashReport out = await DVRepositoryCrashSymbolicator(
        repository: await repoWithDart(),
        dartDecoder: decoder,
      ).symbolicate(dartReport());

      expect(decoder.sawStack, contains("build_id: 'c0ffee00c0ffee00c0ffee00c0ffee00'"));
      expect(decoder.sawStack, contains('_kDartIsolateSnapshotInstructions+0x11234'));
      // Only the file for this build, never the other architecture's.
      expect(decoder.sawFiles, 1);
      expect(out.symbolicated, isTrue);
      expect(out.frames.first.function, 'Checkout.pay');
      expect(out.frames.first.uri, 'package:shop/checkout.dart');
      expect(out.frames.first.line, 88);
      expect(out.fingerprint,
          DVCrashFingerprint.of(errorType: 'StateError', frames: out.frames));
    });

    test('a stack of another build is not decoded with this one\'s files',
        () async {
      final _FakeDecoder decoder = _FakeDecoder(answer: '#0 x (package:a/a.dart:1:1)');
      final DVCrashReport out = await DVRepositoryCrashSymbolicator(
        repository: await repoWithDart(buildId: 'deadbeefdeadbeefdeadbeefdeadbeef'),
        dartDecoder: decoder,
      ).symbolicate(dartReport());
      expect(decoder.sawStack, isNull);
      expect(out.symbolicated, isFalse);
    });

    test('a decoder that throws costs the report its symbols, not its life',
        () async {
      final DVCrashReport report = dartReport();
      final DVCrashReport out = await DVRepositoryCrashSymbolicator(
        repository: await repoWithDart(),
        dartDecoder: _FakeDecoder(fails: true),
      ).symbolicate(report);
      expect(out.symbolicated, isFalse);
      expect(out.frames.length, report.frames.length);
      expect(out.fingerprint, report.fingerprint);
    });

    test('a stack that is already readable is left alone', () async {
      final DVCrashReport readable = DVCrashReport(
        id: 'p1',
        kind: DVCrashKind.fatal,
        errorType: 'StateError',
        message: 'm',
        frames: DVCrashFrame.parse('#0      Checkout.pay (package:shop/checkout.dart:88:7)'),
        fingerprint: 'f',
        context: const DVCrashContext(release: '1.4.0', installId: 'i'),
        occurredAt: DateTime.utc(2026),
      );
      final _FakeDecoder decoder = _FakeDecoder(answer: 'x');
      final DVCrashReport out = await DVRepositoryCrashSymbolicator(
        repository: await repoWithDart(),
        dartDecoder: decoder,
      ).symbolicate(readable);
      expect(decoder.sawStack, isNull);
      expect(out.symbolicated, isNull);
      expect(out.fingerprint, 'f');
    });

    test('with no decoder an obfuscated stack is reported as unsymbolicated',
        () async {
      final DVCrashReport out =
          await DVRepositoryCrashSymbolicator(repository: await repoWithDart())
              .symbolicate(dartReport());
      expect(out.symbolicated, isFalse);
    });
  });

  group('in the ingest', () {
    test('a report arrives symbolicated and is stored that way', () async {
      final DVMemoryCrashReportRepository reports = DVMemoryCrashReportRepository();
      final DVCrashIngest ingest = DVCrashIngest(
        repository: reports,
        symbolicator:
            DVRepositoryCrashSymbolicator(repository: await repoWithMapping('1.4.0')),
        log: (String _) {},
      );
      final DVCrashIngestResult result =
          await ingest.accept(utf8.encode(jsonEncode(jvmReport().toJson())));
      expect(result.outcome, DVCrashIngestOutcome.stored);
      expect(reports.stored.single.symbolicated, isTrue);
      expect(reports.stored.single.errorType, 'com.example.shop.PaymentGateway');
    });

    test('a symbolicator that throws does not lose the report', () async {
      final DVMemoryCrashReportRepository reports = DVMemoryCrashReportRepository();
      final DVCrashIngest ingest = DVCrashIngest(
        repository: reports,
        symbolicator: _ThrowingSymbolicator(),
        log: (String _) {},
      );
      final DVCrashIngestResult result =
          await ingest.accept(utf8.encode(jsonEncode(jvmReport().toJson())));
      expect(result.outcome, DVCrashIngestOutcome.stored);
      expect(reports.stored.single.errorType, 'a.b');
    });
  });
}

class _ThrowingSymbolicator implements DVCrashSymbolicator {
  @override
  Future<DVCrashReport> symbolicate(DVCrashReport report) =>
      throw StateError('boom');
}
