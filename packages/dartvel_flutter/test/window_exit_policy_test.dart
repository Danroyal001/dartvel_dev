// The main window, its promotion, and when closing a window ends the process.
//
// The first window opened is `main`, and it is a peer for everything except
// two jobs: it anchors restore and deep links with no target, and it decides
// process exit under `exit: mainWindow`. None of that existed -- there was no
// main, no promotion when it closed, and no exit policy -- so `exit` was a
// configuration key the runtime read and then ignored, which is worse than an
// unimplemented one because `dartvel inspect windows` reports it as in effect.
//
// The rule that needs the most care is promotion. If main closes under
// `exit: lastWindow` while other regular windows remain, the oldest remaining
// regular window becomes main. Getting that wrong strands an application with
// no main: restore lands nowhere and tray code following the signal sees null.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DVWindowManager.reset();
    // Real windows, so kind and ordering are what decides rather than the
    // capability falling back to a page.
    DV.Test.fakeWindowing(DVWindowingCapability.desktop());
    DVNativeBridge.register('window.open', (Object? _) => 'native');
    DVNativeBridge.register('window.close', (Object? _) => true);
  });

  tearDown(() {
    DVNativeBridge.unregister('window.open');
    DVNativeBridge.unregister('window.close');
    DVWindowManager.reset();
  });

  Future<DVWindow> open(String path,
          {DVWindowKind kind = DVWindowKind.regular}) =>
      DV.Platform.Window.open(DVRouteTarget(path),
          options: DVWindowOptions(kind: kind));

  group('which window is main', () {
    test('there is no main window before one is opened', () {
      expect(DV.Platform.Window.main.value, isNull);
    });

    test('the first window opened is main', () async {
      final DVWindow first = await open('/a');
      expect(DV.Platform.Window.main.value, same(first));
    });

    test('a later window is not', () async {
      final DVWindow first = await open('/a');
      await open('/b');
      expect(DV.Platform.Window.main.value, same(first));
    });

    test('an owned window is never main, even if opened first', () async {
      // Owned windows are dialogs and popups. One of them anchoring restore
      // would put a restored workspace inside a dialog.
      await open('/dialog', kind: DVWindowKind.dialog);
      expect(DV.Platform.Window.main.value, isNull);

      final DVWindow regular = await open('/a');
      expect(DV.Platform.Window.main.value, same(regular));
    });
  });

  group('promotion when main closes', () {
    test('the oldest remaining regular window becomes main', () async {
      final DVWindow first = await open('/a');
      final DVWindow second = await open('/b');
      await open('/c');

      await first.close();

      expect(DV.Platform.Window.main.value, same(second),
          reason: 'oldest remaining, not newest');
    });

    test('an owned window is skipped for promotion', () async {
      final DVWindow first = await open('/a');
      await open('/dialog', kind: DVWindowKind.popup);
      final DVWindow regular = await open('/b');

      await first.close();

      expect(DV.Platform.Window.main.value, same(regular));
    });

    test('with nothing left to promote, main goes null', () async {
      final DVWindow only = await open('/a');
      await only.close();
      expect(DV.Platform.Window.main.value, isNull);
    });

    test('closing a window that is not main leaves main alone', () async {
      final DVWindow first = await open('/a');
      final DVWindow second = await open('/b');

      await second.close();

      expect(DV.Platform.Window.main.value, same(first));
    });

    test('main is a signal, so tray code follows the promotion', () async {
      // The specification calls it signal-backed for this reason: code that
      // read it once would keep a handle to a closed window.
      final List<String?> seen = <String?>[];
      void listener() =>
          seen.add(DV.Platform.Window.main.value?.route.path);
      DV.Platform.Window.main.addListener(listener);
      addTearDown(() => DV.Platform.Window.main.removeListener(listener));

      final DVWindow first = await open('/a');
      await open('/b');
      await first.close();

      expect(seen, <String?>['/a', '/b']);
    });
  });

  group('exit policy', () {
    test('lastWindow ends the process when the last regular window closes',
        () async {
      DVWindowManager.exitPolicy = DVWindowExitPolicy.lastWindow;
      final DVWindow a = await open('/a');
      final DVWindow b = await open('/b');

      await a.close();
      expect(DV.Platform.Window.shouldExit.value, isFalse);

      await b.close();
      expect(DV.Platform.Window.shouldExit.value, isTrue);
    });

    test('an owned window left open does not keep the process alive',
        () async {
      // "the last regular or kiosk window; owned windows do not count". A
      // lingering tooltip would otherwise hold an application open with
      // nothing on screen.
      DVWindowManager.exitPolicy = DVWindowExitPolicy.lastWindow;
      final DVWindow a = await open('/a');
      await open('/tip', kind: DVWindowKind.tooltip);

      await a.close();

      expect(DV.Platform.Window.shouldExit.value, isTrue);
    });

    test('mainWindow ends the process when main closes, others or not',
        () async {
      DVWindowManager.exitPolicy = DVWindowExitPolicy.mainWindow;
      final DVWindow a = await open('/a');
      await open('/b');

      await a.close();

      expect(DV.Platform.Window.shouldExit.value, isTrue);
    });

    test('mainWindow ignores a non-main window closing', () async {
      DVWindowManager.exitPolicy = DVWindowExitPolicy.mainWindow;
      await open('/a');
      final DVWindow b = await open('/b');

      await b.close();

      expect(DV.Platform.Window.shouldExit.value, isFalse);
    });

    test('explicit never exits on a window close', () async {
      // Tray-resident applications: closing the window hides it, and the
      // process stays for the tray icon.
      DVWindowManager.exitPolicy = DVWindowExitPolicy.explicit;
      final DVWindow a = await open('/a');

      await a.close();

      expect(DV.Platform.Window.shouldExit.value, isFalse);
      expect(DV.Platform.Window.all.value, isEmpty);
    });

    test('a later close does not cancel an exit already decided', () async {
      // shouldExit is a latch, not a running commentary. Under mainWindow,
      // closing main decides the process should end; a stray window closing
      // afterwards recomputing it as false would cancel an exit the embedder
      // had not got round to acting on yet, and nothing would ever exit.
      // Three windows, because closing main promotes the next one -- so with
      // only two, the second close is also a main close and the latch is
      // never tested. It takes a third, non-main window to close afterwards.
      DVWindowManager.exitPolicy = DVWindowExitPolicy.mainWindow;
      final DVWindow a = await open('/a');
      await open('/b');
      final DVWindow c = await open('/c');

      await a.close();
      expect(DV.Platform.Window.shouldExit.value, isTrue);

      await c.close();
      expect(DV.Platform.Window.shouldExit.value, isTrue,
          reason: 'still exiting; c was not main');
    });

    test('opening a window clears it, because there is something on screen',
        () async {
      // The one thing that should undo it: a deep link arriving between the
      // last window closing and the embedder acting.
      DVWindowManager.exitPolicy = DVWindowExitPolicy.lastWindow;
      final DVWindow a = await open('/a');
      await a.close();
      expect(DV.Platform.Window.shouldExit.value, isTrue);

      await open('/b');
      expect(DV.Platform.Window.shouldExit.value, isFalse);
    });

    test('the default is lastWindow', () {
      expect(DVWindowManager.exitPolicy, DVWindowExitPolicy.lastWindow);
    });

    test('reset puts the policy back, so one test cannot set another\'s',
        () async {
      DVWindowManager.exitPolicy = DVWindowExitPolicy.explicit;
      DVWindowManager.reset();
      expect(DVWindowManager.exitPolicy, DVWindowExitPolicy.lastWindow);
      expect(DV.Platform.Window.shouldExit.value, isFalse);
    });
  });
}
