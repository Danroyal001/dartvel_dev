// A second launch reaching the running application.
//
// The single-instance lock refuses the second process and queues the route it
// was launched with, and DV.Window.open presents routes. Nothing joined them,
// so the queue filled up and was never read: a deep link, a file association
// or a second launch reached a process that then exited, and the running
// application never heard about it. "Second launch focuses the running app"
// was true of the lock and false of the application.
//
// The contract routes an external request through the same idempotent open(),
// so a link to an order already on screen focuses that window rather than
// opening a second one.
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DVInstanceLock primary;
  late String lockPath;

  setUp(() {
    DVWindowManager.reset();
    lockPath = '${Directory.systemTemp.createTempSync('dv_ext_').path}/app.lock';
    primary = DVSingleInstance.acquire(lockPath);
  });

  tearDown(() {
    primary.release();
    DVWindowManager.reset();
  });

  /// A second launch asking for [route].
  void secondLaunch(String route) {
    final DVInstanceLock secondary = DVSingleInstance.acquire(lockPath);
    secondary.send(route);
    secondary.release();
  }

  group('draining what a second launch left', () {
    test('a queued route is opened', () async {
      secondLaunch('/orders/42');

      final int opened = await DV.Platform.Window.drainExternalOpens(primary);

      expect(opened, 1);
      expect(DV.Platform.Window.all.value.map((DVWindow w) => w.route.path),
          <String>['/orders/42']);
    });

    test('several queued routes are all opened, in order', () async {
      secondLaunch('/orders/1');
      secondLaunch('/orders/2');

      await DV.Platform.Window.drainExternalOpens(primary);

      expect(DV.Platform.Window.all.value.map((DVWindow w) => w.route.path),
          <String>['/orders/1', '/orders/2']);
    });

    test('an empty queue opens nothing and is not an error', () async {
      expect(await DV.Platform.Window.drainExternalOpens(primary), 0);
      expect(DV.Platform.Window.all.value, isEmpty);
    });

    test('draining twice does not reopen what it already opened', () async {
      // The queue is cleared on read. Without that the primary reopens the
      // same route on every poll, for ever.
      secondLaunch('/orders/42');

      await DV.Platform.Window.drainExternalOpens(primary);
      expect(await DV.Platform.Window.drainExternalOpens(primary), 0);
      expect(DV.Platform.Window.all.value, hasLength(1));
    });

    test('a route already on screen is focused, not duplicated', () async {
      // Idempotent by URL is the contract, and it is why an external request
      // goes through open() rather than through a second API.
      await DV.Platform.Window.open(const DVRouteTarget('/orders/42'));
      secondLaunch('/orders/42');

      await DV.Platform.Window.drainExternalOpens(primary);

      expect(DV.Platform.Window.all.value, hasLength(1),
          reason: 'the same URL is the same window');
    });

    test('a secondary draining gets nothing, so it cannot swallow its own ask',
        () async {
      final DVInstanceLock secondary = DVSingleInstance.acquire(lockPath);
      addTearDown(secondary.release);
      secondary.send('/orders/42');

      expect(await DV.Platform.Window.drainExternalOpens(secondary), 0);
      expect(await DV.Platform.Window.drainExternalOpens(primary), 1);
    });
  });

  group('what an external request is', () {
    test('the window records that it came from outside', () async {
      // A route the user asked for and a route the OS handed over are not the
      // same event, and a policy or an analytic that cannot tell them apart
      // reports every deep link as navigation.
      secondLaunch('/orders/42');
      await DV.Platform.Window.drainExternalOpens(primary);

      expect(DV.Platform.Window.all.value.single.external, isTrue);
    });

    test('an ordinary open is not external', () async {
      await DV.Platform.Window.open(const DVRouteTarget('/orders'));
      expect(DV.Platform.Window.all.value.single.external, isFalse);
    });

    test('DVWindowOptions.external is the documented way to say so', () {
      // The const value keeps the specification's name, which is the one that
      // gets typed; the instance field cannot share it, so it is isExternal.
      expect(DVWindowOptions.external.isExternal, isTrue);
      expect(const DVWindowOptions().isExternal, isFalse);
    });
  });

  group('routes it will not open', () {
    test('an empty or whitespace route is skipped', () async {
      secondLaunch('   ');
      expect(await DV.Platform.Window.drainExternalOpens(primary), 0);
      expect(DV.Platform.Window.all.value, isEmpty);
    });

    test('a route that is not a path is skipped rather than opened', () async {
      // The queue is written by another process. It is not trusted input, and
      // opening whatever it says would make a second launch able to name any
      // route at all.
      secondLaunch('orders/42');
      expect(await DV.Platform.Window.drainExternalOpens(primary), 0);
    });
  });
}
