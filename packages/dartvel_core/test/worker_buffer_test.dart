// The native offload seam: memory outside the Dart heap lent to a worker by
// address, and native calls that block made where they cannot stall the
// caller.
//
// What is guarded is the unsafe half. A lent buffer is passed, not shared: the
// caller cannot touch it or lend it again while a worker holds it, and it is
// not handed back until the worker's thread has actually ended -- a cancelled
// run whose isolate is still writing must not have its memory freed under it.
@TestOn('vm')
@Timeout(Duration(seconds: 30))
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

int _fillWithIndex(DVWorkerLease lease, DVWorkerReporter reporter) {
  final Uint8List bytes = lease.bytes;
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = i & 0xff;
  }
  return lease.address;
}

int _scribbleForever(DVWorkerLease lease, DVWorkerReporter reporter) {
  final Uint8List bytes = lease.bytes;
  var i = 0;
  while (true) {
    bytes[i++ % bytes.length] = 7;
  }
}

/// A native call that holds its thread: libc's usleep, or Win32's Sleep.
int _sleepNatively(int milliseconds, DVWorkerReporter reporter) {
  if (io.Platform.isWindows) {
    DynamicLibrary.open('kernel32.dll')
        .lookupFunction<Void Function(Uint32), void Function(int)>('Sleep')(
            milliseconds);
  } else {
    DynamicLibrary.process()
        .lookupFunction<Int32 Function(Uint32), int Function(int)>('usleep')(
            milliseconds * 1000);
  }
  return milliseconds;
}

void main() {
  late DVWorkers workers;
  setUp(() => workers = DVWorkers(profile: const DVWorkerProfile(cores: 4)));
  tearDown(() => workers.close());

  test('a worker writes into lent memory and the caller reads it in place',
      () async {
    final DVWorkerBuffer buffer = DVWorkerBuffer.allocate(4096);
    addTearDown(buffer.free);

    final DVWorkerResult<int> result = await workers.run(
      _fillWithIndex,
      input: buffer.lease,
      lend: <DVWorkerBuffer>[buffer],
    );

    expect(result.outcome, DVWorkerOutcome.completed);
    // The worker wrote at the caller's address: nothing was copied either way.
    expect(result.value, buffer.lease.address);
    expect(buffer.bytes[0], 0);
    expect(buffer.bytes[255], 255);
    expect(buffer.bytes[4095], 4095 & 0xff);
    expect(workers.capability.zeroCopyNative, isTrue);
  });

  test('a lent buffer cannot be read, freed or lent again until it is back',
      () async {
    final DVWorkerBuffer buffer = DVWorkerBuffer.allocate(64);
    addTearDown(buffer.free);

    final Future<DVWorkerResult<int>> pending = workers.run(
      _fillWithIndex,
      input: buffer.lease,
      lend: <DVWorkerBuffer>[buffer],
    );
    expect(buffer.isLent, isTrue);
    expect(() => buffer.bytes, throwsStateError);
    expect(buffer.free, throwsStateError);
    expect(
      () => workers.run(_fillWithIndex,
          input: buffer.lease, lend: <DVWorkerBuffer>[buffer]),
      throwsStateError,
    );

    expect((await pending).outcome, DVWorkerOutcome.completed);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(buffer.isLent, isFalse);
    expect(buffer.bytes, hasLength(64));
  });

  test('cancelling a writer keeps the buffer lent until its thread has ended',
      () async {
    final DVWorkerBuffer buffer = DVWorkerBuffer.allocate(64);
    addTearDown(buffer.free);
    final DVCancellation cancel = DVCancellation();

    final Future<DVWorkerResult<int>> pending = workers.run(
      _scribbleForever,
      input: buffer.lease,
      lend: <DVWorkerBuffer>[buffer],
      cancellation: cancel,
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    cancel.cancel();

    expect((await pending).outcome, DVWorkerOutcome.cancelled);
    // Answered, but the isolate has not reported its exit yet: the memory it
    // may still be writing is not the caller's.
    expect(buffer.isLent, isTrue);
    expect(buffer.free, throwsStateError);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(buffer.isLent, isFalse);
  });

  test('a buffer lent to a run that could not start is handed straight back',
      () async {
    final DVWorkerBuffer buffer = DVWorkerBuffer.allocate(8);
    addTearDown(buffer.free);
    final DVWorkerResult<int> result = await workers.run(
      _fillWithIndex,
      input: buffer.lease,
      lend: <DVWorkerBuffer>[buffer],
      cancellation: DVCancellation()..cancel(),
    );
    expect(result.outcome, DVWorkerOutcome.cancelled);
    expect(buffer.isLent, isFalse);
  });

  test('a freed buffer refuses everything', () {
    final DVWorkerBuffer buffer = DVWorkerBuffer.allocate(8)..free();
    expect(() => buffer.bytes, throwsStateError);
    expect(() => buffer.lease, throwsStateError);
    expect(() => DVWorkerBuffer.allocate(0), throwsArgumentError);
  });

  test('a blocking native call on a worker leaves the caller its event loop',
      () async {
    var ticks = 0;
    final Timer ticker =
        Timer.periodic(const Duration(milliseconds: 20), (_) => ticks++);
    final DVWorkerResult<int> result =
        await workers.run(_sleepNatively, input: 600);
    ticker.cancel();

    expect(result.outcome, DVWorkerOutcome.completed);
    // Made on the calling isolate, the same call yields zero ticks: a native
    // call is not preempted and returns to no event loop until it is done.
    expect(ticks, greaterThan(10));
  });
}
