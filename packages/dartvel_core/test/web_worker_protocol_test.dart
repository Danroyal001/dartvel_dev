// The web half of DV.Workers, minus the browser.
//
// A web worker is a separately loaded script: it cannot be handed a Dart
// function, only a message, so a task crosses by a registered name and its
// input by structured clone. Everything that decides what happens -- which
// name a task has, whether an input can be cloned at all, what the worker
// does with a request, and what the capability report says -- is plain Dart
// and is tested here on the VM. The Worker object itself is not; see
// workers_web.dart.
library;

import 'package:dartvel_core/src/observability/observability.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

int _sum(List<Object?> input, DVWorkerReporter reporter) {
  var total = 0;
  for (var i = 0; i < input.length; i++) {
    total += input[i]! as int;
    reporter.progress((i + 1) / input.length);
  }
  return total;
}

int _other(List<Object?> input, DVWorkerReporter reporter) => 0;

int _throws(Object? input, DVWorkerReporter reporter) =>
    throw const FormatException('row 3 has no amount');

Object _returnsAClass(Object? input, DVWorkerReporter reporter) =>
    const _Ledger();

class _Ledger {
  const _Ledger();
}

void main() {
  setUp(() {
    DVWorkerTasks.debugClear();
    DVObservability.resetLogging();
    DVWorkers.debugResetOnceDiagnostics();
  });

  group('tasks cross by name', () {
    test('a registered task is found by name and by the function itself', () {
      DVWorkerTasks.register('sum', _sum);
      expect(DVWorkerTasks.nameOf(_sum), 'sum');
      expect(DVWorkerTasks.nameOf(_other), isNull);
      expect(DVWorkerTasks.lookup('sum'), isNotNull);
      expect(DVWorkerTasks.lookup('missing'), isNull);
    });

    test('one name for two functions is refused; the same pair again is not',
        () {
      DVWorkerTasks.register('sum', _sum);
      DVWorkerTasks.register('sum', _sum);
      expect(() => DVWorkerTasks.register('sum', _other), throwsStateError);
      expect(() => DVWorkerTasks.register('', _other), throwsArgumentError);
    });
  });

  group('what a web worker can be handed', () {
    test('clonable values pass', () {
      expect(
        dvWorkerUnportable(<String, Object?>{
          'rows': <Object?>[1, 2.5, 'x', true, null],
          'bytes': Uint8List(4),
          'buffer': Uint8List(2).buffer,
          'nested': <String, Object?>{'n': <int>[1]},
        }),
        isNull,
      );
    });

    test('a class instance is named with where it sits', () {
      expect(
        dvWorkerUnportable(<String, Object?>{
          'rows': <Object?>[1, const _Ledger()],
        }),
        allOf(contains(r'$.rows[1]'), contains('_Ledger')),
      );
    });

    test('a function, and a map keyed by something other than a string', () {
      expect(dvWorkerUnportable(_sum), contains(r'$'));
      expect(dvWorkerUnportable(<int, int>{1: 2}), contains('key'));
    });
  });

  group('the worker side of a request', () {
    Future<List<Map<String, Object?>>> handle(Map<String, Object?> request) {
      final List<Map<String, Object?>> posted = <Map<String, Object?>>[];
      return dvWorkerHandle(request, posted.add).then((_) => posted);
    }

    test('progress then the value, each tagged with the request id', () async {
      DVWorkerTasks.register('sum', _sum);
      final List<Map<String, Object?>> posted = await handle(
          const DVWorkerRequest(id: 7, task: 'sum', input: <Object?>[2, 3])
              .toMessage());

      expect(posted.map((Map<String, Object?> m) => m['kind']),
          <String>['progress', 'progress', 'done']);
      expect(posted.every((Map<String, Object?> m) => m['id'] == 7), isTrue);
      expect(posted.last['value'], 5);
      expect(DVWorkerResponse.fromMessage(posted.first).fraction, 0.5);
    });

    test('a task the worker does not have fails by name', () async {
      final List<Map<String, Object?>> posted = await handle(
          const DVWorkerRequest(id: 1, task: 'ghost', input: null).toMessage());
      final DVWorkerResponse response =
          DVWorkerResponse.fromMessage(posted.single);
      expect(response.kind, DVWorkerResponseKind.failed);
      expect(response.failureKind, DVWorkerFailureKind.unsendableTask);
      expect(response.error, contains('ghost'));
    });

    test('a throw comes back as its type, message and stack', () async {
      DVWorkerTasks.register('throws', _throws);
      final DVWorkerResponse response = DVWorkerResponse.fromMessage((await handle(
              const DVWorkerRequest(id: 2, task: 'throws', input: null)
                  .toMessage()))
          .single);
      expect(response.failureKind, DVWorkerFailureKind.threw);
      expect(response.error, contains('FormatException'));
      expect(response.error, contains('row 3 has no amount'));
      expect(response.stack, contains('_throws'));
    });

    test('a result that cannot be cloned back fails by name, not by '
        'DataCloneError', () async {
      DVWorkerTasks.register('cls', _returnsAClass);
      final DVWorkerResponse response = DVWorkerResponse.fromMessage((await handle(
              const DVWorkerRequest(id: 3, task: 'cls', input: null)
                  .toMessage()))
          .single);
      expect(response.failureKind, DVWorkerFailureKind.unsendableResult);
      expect(response.error, contains('_Ledger'));
    });

    test('a malformed request is answered rather than dropped', () async {
      final List<Map<String, Object?>> posted =
          await handle(<String, Object?>{'id': 9});
      expect(DVWorkerResponse.fromMessage(posted.single).kind,
          DVWorkerResponseKind.failed);
    });
  });

  group('capability, reported rather than hidden', () {
    test('a browser with workers but no cross-origin isolation copies', () {
      final DVWorkerCapability c = dvWebWorkerCapability(
          hasWorker: true, crossOriginIsolated: false);
      expect(c.mechanism, DVWorkerMechanism.webWorker);
      expect(c.label, 'Supported with limitations');
      expect(c.sharedMemory, isFalse);
      expect(c.zeroCopyNative, isFalse);
      expect(c.note, contains('copied'));
    });

    test('cross-origin isolation is what makes memory shareable', () {
      expect(
          dvWebWorkerCapability(hasWorker: true, crossOriginIsolated: true)
              .sharedMemory,
          isTrue);
    });

    test('no Worker at all is inline', () {
      expect(
          dvWebWorkerCapability(hasWorker: false, crossOriginIsolated: true)
              .mechanism,
          DVWorkerMechanism.inline);
    });

    test('DV-WORKER-004 is reported once, and only when bytes were copied',
        () {
      final DVWorkerCapability copying = dvWebWorkerCapability(
          hasWorker: true, crossOriginIsolated: false);
      final DVWorkerCapability sharing = dvWebWorkerCapability(
          hasWorker: true, crossOriginIsolated: true);

      dvReportCopiedInput(sharing, Uint8List(8));
      dvReportCopiedInput(copying, <Object?>[1, 2]);
      expect(_logged('DV-WORKER-004'), isEmpty);

      dvReportCopiedInput(copying, <String, Object?>{'b': Uint8List(8)});
      dvReportCopiedInput(copying, Uint8List(8));
      final List<DVLogRecord> copied = _logged('DV-WORKER-004');
      expect(copied, hasLength(1));
      expect(copied.single.level, DVLogLevel.info);
    });
  });
}

List<DVLogRecord> _logged(String code) => DVObservability.recentLogs
    .where((DVLogRecord r) => r.code == code)
    .toList();
