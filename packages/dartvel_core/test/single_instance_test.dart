// The single-instance lock, which makes "second launch focuses the running
// app" true.
//
// The Multi-Window contract sets `singleInstance: true` as the desktop default
// and routes an external open request through the same idempotent open(), so a
// second launch focuses rather than forks. Nothing implemented the lock, so
// every launch forked and the deep-link path had nothing to hand a route to.
//
// The part that has to be right is release. A lock a crashed process keeps
// forever means the application can never start again, and the user's only fix
// is deleting a file they do not know about -- which is why this is built on an
// advisory file lock the kernel drops when the process dies, rather than on a
// pid file someone has to reap.
import 'dart:io';

import 'package:dartvel_core/src/windowing/single_instance.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  String path() => '${dir.path}/app.lock';

  setUp(() => dir = Directory.systemTemp.createTempSync('dv_lock_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the first acquirer gets the lock', () {
    final DVInstanceLock lock = DVSingleInstance.acquire(path());
    addTearDown(lock.release);
    expect(lock.isPrimary, isTrue);
  });

  test('a second acquirer does not get it', () {
    final DVInstanceLock first = DVSingleInstance.acquire(path());
    addTearDown(first.release);

    final DVInstanceLock second = DVSingleInstance.acquire(path());
    addTearDown(second.release);

    expect(second.isPrimary, isFalse);
  });

  test('releasing hands the lock on', () {
    DVSingleInstance.acquire(path()).release();
    final DVInstanceLock next = DVSingleInstance.acquire(path());
    addTearDown(next.release);
    expect(next.isPrimary, isTrue);
  });

  test('releasing twice is not an error', () {
    // Release runs from a shutdown path that may itself run twice.
    final DVInstanceLock lock = DVSingleInstance.acquire(path());
    lock.release();
    expect(lock.release, returnsNormally);
  });

  test('the lock file is created, with the directory if needed', () {
    final String nested = '${dir.path}/deep/nested/app.lock';
    final DVInstanceLock lock = DVSingleInstance.acquire(nested);
    addTearDown(lock.release);
    expect(File(nested).existsSync(), isTrue);
  });

  test('a secondary can hand the primary the route it wants opened', () {
    // The contract routes a second launch through the primary's open(), so
    // the request has to cross the process boundary.
    final DVInstanceLock primary = DVSingleInstance.acquire(path());
    addTearDown(primary.release);

    final DVInstanceLock secondary = DVSingleInstance.acquire(path());
    addTearDown(secondary.release);
    secondary.send('/orders/42');

    expect(primary.takePending(), <String>['/orders/42']);
  });

  test('taking pending requests clears them', () {
    // Or the primary reopens the same route on every poll.
    final DVInstanceLock primary = DVSingleInstance.acquire(path());
    addTearDown(primary.release);
    final DVInstanceLock secondary = DVSingleInstance.acquire(path());
    addTearDown(secondary.release);

    secondary.send('/a');
    expect(primary.takePending(), <String>['/a']);
    expect(primary.takePending(), isEmpty);
  });

  test('several requests arrive in order', () {
    final DVInstanceLock primary = DVSingleInstance.acquire(path());
    addTearDown(primary.release);
    final DVInstanceLock secondary = DVSingleInstance.acquire(path());
    addTearDown(secondary.release);

    secondary.send('/a');
    secondary.send('/b');
    expect(primary.takePending(), <String>['/a', '/b']);
  });

  test('a secondary never drains the queue', () {
    // Only the primary opens routes; a secondary that drained it would
    // swallow the route it just asked for.
    final DVInstanceLock primary = DVSingleInstance.acquire(path());
    addTearDown(primary.release);
    final DVInstanceLock secondary = DVSingleInstance.acquire(path());
    addTearDown(secondary.release);

    secondary.send('/a');
    expect(secondary.takePending(), isEmpty);
    expect(primary.takePending(), <String>['/a']);
  });

  test('an unreadable queue does not stop the application starting', () {
    // A corrupt or truncated file is recoverable; refusing to launch over it
    // is not.
    final DVInstanceLock primary = DVSingleInstance.acquire(path());
    addTearDown(primary.release);
    File('${path()}.requests').writeAsStringSync('  not json');

    expect(primary.takePending(), isEmpty);
  });

  test('a route is not sent twice by one secondary launch', () {
    // Idempotent by URL is the contract. Two identical pending requests would
    // make the primary open, then focus, the same window twice.
    final DVInstanceLock primary = DVSingleInstance.acquire(path());
    addTearDown(primary.release);
    final DVInstanceLock secondary = DVSingleInstance.acquire(path());
    addTearDown(secondary.release);

    secondary.send('/a');
    secondary.send('/a');
    expect(primary.takePending(), <String>['/a']);
  });
}
