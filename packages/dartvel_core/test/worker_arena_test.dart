// A Platform Memory arena lent to a worker: the join the specification says
// the three sections were missing. The arena is where the data sits, and a
// worker is where it is processed without the UI waiting.
//
// What is guarded is what an address alone does not protect. An arena's
// segments are freed by a finalizer once the last Dart view is collected, and
// a worker holding an address holds no view -- so an arena disposed while a
// worker writes is freed under it. And reset() hands the same bytes out again
// while the worker is still writing them. While lent, neither is allowed.
@TestOn('vm')
@Timeout(Duration(seconds: 30))
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// Writes each index into the bytes at [input]'s address.
int _fill(List<int> input, DVWorkerReporter reporter) {
  final Uint8List bytes =
      Pointer<Uint8>.fromAddress(input[0]).asTypedList(input[1]);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = i;
  }
  return bytes.length;
}

int _scribble(List<int> input, DVWorkerReporter reporter) {
  final Uint8List bytes =
      Pointer<Uint8>.fromAddress(input[0]).asTypedList(input[1]);
  var i = 0;
  while (true) {
    bytes[i++ % bytes.length] = 7;
  }
}

DVPlatformMemory _arena() => DVPlatformMemory(
      megabytes: 1,
      segment: const DVSize.kb(64),
      target: DVMemoryTarget.linux,
    );

void main() {
  late DVWorkers workers;
  setUp(() => workers = DVWorkers(profile: const DVWorkerProfile(cores: 4)));
  tearDown(() => workers.close());

  test('a worker writes into an arena slice and the caller reads it in place',
      () async {
    final DVPlatformMemory arena = _arena();
    addTearDown(arena.dispose);
    final MemorySlice<int> slice = arena.uint8(200);

    final DVWorkerResult<int> result = await workers.run(
      _fill,
      input: <int>[slice.addresses.single, slice.length],
      lend: <DVWorkerLendable>[arena],
    );

    expect(result.value, 200);
    expect(slice[0], 0);
    expect(slice[199], 199);
    expect(arena.isLent, isFalse);
  });

  test('a lent arena cannot be reset, disposed or lent again', () async {
    final DVPlatformMemory arena = _arena();
    addTearDown(arena.dispose);
    final MemorySlice<int> slice = arena.uint8(16);

    final Future<DVWorkerResult<int>> pending = workers.run(
      _fill,
      input: <int>[slice.addresses.single, slice.length],
      lend: <DVWorkerLendable>[arena],
    );
    expect(arena.isLent, isTrue);
    expect(arena.reset, throwsStateError);
    expect(arena.dispose, throwsStateError);
    expect(arena.isDisposed, isFalse);
    expect(
      () => workers.run(_fill,
          input: <int>[slice.addresses.single, slice.length],
          lend: <DVWorkerLendable>[arena]),
      throwsStateError,
    );

    expect((await pending).outcome, DVWorkerOutcome.completed);
    arena.reset();
    expect(slice.isValid, isFalse);
  });

  test('a cancelled writer keeps the arena until its isolate has ended',
      () async {
    final DVPlatformMemory arena = _arena();
    addTearDown(() {
      if (!arena.isLent) arena.dispose();
    });
    final MemorySlice<int> slice = arena.uint8(64);
    final DVCancellation cancel = DVCancellation();

    final Future<DVWorkerResult<int>> pending = workers.run(
      _scribble,
      input: <int>[slice.addresses.single, slice.length],
      lend: <DVWorkerLendable>[arena],
      cancellation: cancel,
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    cancel.cancel();

    expect((await pending).outcome, DVWorkerOutcome.cancelled);
    expect(arena.isLent, isTrue);
    expect(arena.dispose, throwsStateError);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(arena.isLent, isFalse);
  });

  test('a disposed arena cannot be lent', () {
    final DVPlatformMemory arena = _arena()..dispose();
    expect(arena.lend, throwsStateError);
  });
}
