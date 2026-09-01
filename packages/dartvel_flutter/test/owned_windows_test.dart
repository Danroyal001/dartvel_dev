// Owned windows, and modality that does not lie.
//
// A dialog, popup, tooltip or satellite belongs to another window. It cannot
// outlive its owner, and a request naming an owner that has already closed
// must fail rather than quietly adopt main -- a dialog reparented to the wrong
// window blocks input on a window the user was not working in.
//
// Neither rule existed. DVWindowOptions had no owner and no modality at all,
// so DV-WINDOW-007 and DV-WINDOW-008 were reserved codes with nothing able to
// emit them.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DVWindowManager.reset();
    DV.Test.fakeWindowing(DVWindowingCapability.desktop());
    DVNativeBridge.register('window.open', (Object? _) => 'native');
    DVNativeBridge.register('window.close', (Object? _) => true);
  });

  tearDown(() {
    DVNativeBridge.unregister('window.open');
    DVNativeBridge.unregister('window.close');
    DVWindowManager.reset();
  });

  Future<DVWindow> open(String path, {DVWindowOptions? options}) =>
      DV.Platform.Window.open(DVRouteTarget(path),
          options: options ?? const DVWindowOptions());

  group('ownership', () {
    test('an owned window records its owner', () async {
      final DVWindow owner = await open('/a');
      final DVWindow dialog = await open('/confirm',
          options: DVWindowOptions(
              kind: DVWindowKind.dialog, owner: owner, duplicate: true));

      expect(dialog.owner, same(owner));
    });

    test('closing the owner closes what it owns', () async {
      final DVWindow owner = await open('/a');
      final DVWindow dialog = await open('/confirm',
          options: DVWindowOptions(
              kind: DVWindowKind.dialog, owner: owner, duplicate: true));

      await owner.close();

      expect(DV.Platform.Window.all.value, isEmpty);
      expect(dialog.lifecycle.value, DVWindowLifecycle.closed);
    });

    test('owned windows close in reverse open order', () async {
      // Last opened is closest to the user, so it goes first. A palette
      // disappearing before the dialog on top of it flashes the wrong thing.
      final List<String> closed = <String>[];
      final DVWindow owner = await open('/a');
      for (final String path in <String>['/first', '/second', '/third']) {
        final DVWindow child = await open(path,
            options: DVWindowOptions(
                kind: DVWindowKind.satellite, owner: owner, duplicate: true));
        child.lifecycle.addListener(() {
          if (child.lifecycle.value == DVWindowLifecycle.closed) {
            closed.add(path);
          }
        });
      }

      await owner.close();

      expect(closed, <String>['/third', '/second', '/first']);
    });

    test('a closed owner is refused, not swapped for main', () async {
      // Adopting main would put a dialog on a window the user was not working
      // in, and block input there.
      final DVWindow owner = await open('/a');
      await open('/b');
      await owner.close();

      final DVWindow dialog = await open('/confirm',
          options: DVWindowOptions(
              kind: DVWindowKind.dialog, owner: owner, duplicate: true));

      expect(dialog.degradation, DVWindowDegradation.ownerClosed);
      expect(dialog.owner, isNull);
      expect(dialog.presentation, isNot(DVWindowPresentation.window));
    });

    test('DV-WINDOW-007 is what that reports', () {
      expect(DVWindowDegradation.ownerClosed.code, 'DV-WINDOW-007');
      expect(DVWindowDegradation.ownerClosed.level, 'warning');
    });

    test('a regular window takes no owner', () async {
      final DVWindow owner = await open('/a');
      final DVWindow other = await open('/b',
          options: DVWindowOptions(owner: owner, duplicate: true));

      expect(other.owner, isNull,
          reason: 'regular windows are peers; ownership would make close '
              'cascade through unrelated windows');
    });
  });

  group('modality', () {
    test('a dialog is window-modal by default', () async {
      final DVWindow owner = await open('/a');
      final DVWindow dialog = await open('/confirm',
          options: DVWindowOptions(
              kind: DVWindowKind.dialog, owner: owner, duplicate: true));

      expect(dialog.modality, DVWindowModality.window);
    });

    test('a satellite is not modal', () async {
      final DVWindow owner = await open('/a');
      final DVWindow palette = await open('/palette',
          options: DVWindowOptions(
              kind: DVWindowKind.satellite, owner: owner, duplicate: true));

      expect(palette.modality, DVWindowModality.none);
    });

    test('application modality is honoured where the OS supports it',
        () async {
      DV.Test.fakeWindowing(const DVWindowingCapability(
        multiWindow: true,
        sameEngine: true,
        applicationModal: true,
      ));
      final DVWindow owner = await open('/a');
      final DVWindow dialog = await open('/confirm',
          options: DVWindowOptions(
              kind: DVWindowKind.dialog,
              owner: owner,
              modality: DVWindowModality.application,
              duplicate: true));

      expect(dialog.modality, DVWindowModality.application);
      expect(dialog.degradation, DVWindowDegradation.none);
    });

    test('and degrades to window modality where it is not', () async {
      // A fake application-modal that leaks input is worse than an honest
      // window-modal: the user finds the gap, and the thing that was meant to
      // be blocked happens anyway.
      final DVWindow owner = await open('/a');
      final DVWindow dialog = await open('/confirm',
          options: DVWindowOptions(
              kind: DVWindowKind.dialog,
              owner: owner,
              modality: DVWindowModality.application,
              duplicate: true));

      expect(dialog.modality, DVWindowModality.window);
      expect(dialog.degradation, DVWindowDegradation.modalityReduced);
    });

    test('DV-WINDOW-008 is debug, because nothing was blocked that could be',
        () {
      expect(DVWindowDegradation.modalityReduced.code, 'DV-WINDOW-008');
      expect(DVWindowDegradation.modalityReduced.level, 'debug');
    });
  });
}
