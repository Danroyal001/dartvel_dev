// The install prompt, which a PWA cannot offer without.
//
// The spec lists install prompts under PWA and "web capabilities where
// supported, exposed through DV.Platform". Nothing exposed one, so a Dartvel
// PWA could be installable and had no way to say so -- the browser's own
// affordance is buried in a menu most people never open.
//
// The rules here are the ones that make an install button either work or
// mislead. A browser fires beforeinstallprompt once, only when the app is
// installable and not already installed, and refuses prompt() outside a user
// gesture. A button shown when none of that holds is a button that does
// nothing when tapped.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DVInstallPrompt.resetForTest);

  test('nothing is available before the browser offers one', () {
    // The default has to be false. A button rendered on the assumption that
    // an install is possible is one that does nothing when tapped.
    expect(const DVInstall().canPrompt, isFalse);
  });

  test('it becomes available when the browser offers one', () {
    DVInstallPrompt.captureForTest();
    expect(const DVInstall().canPrompt, isTrue);
  });

  test('prompting without an offer fails rather than pretending', () async {
    // Returning "dismissed" would be a lie: nothing was shown. The caller
    // needs to know it asked for something impossible.
    await expectLater(const DVInstall().prompt(), throwsStateError);
  });

  test('the offer is consumed, because a browser fires it once', () async {
    // The deferred event cannot be reused. Keeping canPrompt true after a
    // prompt leaves a button that silently stops working.
    DVInstallPrompt.captureForTest();
    expect(const DVInstall().canPrompt, isTrue);

    await const DVInstall().prompt();
    expect(const DVInstall().canPrompt, isFalse);
  });

  test('a dismissed prompt is reported, not swallowed', () async {
    DVInstallPrompt.captureForTest(outcome: DVInstallOutcome.dismissed);
    expect(await const DVInstall().prompt(), DVInstallOutcome.dismissed);
  });

  test('an accepted prompt is reported', () async {
    DVInstallPrompt.captureForTest(outcome: DVInstallOutcome.accepted);
    expect(await const DVInstall().prompt(), DVInstallOutcome.accepted);
  });

  test('an already-installed app never offers to install', () {
    // display-mode: standalone means it is already installed. Offering again
    // is the clearest possible sign the button is decorative.
    DVInstallPrompt.captureForTest();
    DVInstallPrompt.markInstalledForTest();
    expect(const DVInstall().canPrompt, isFalse);
  });

  test('installing clears the offer', () async {
    DVInstallPrompt.captureForTest(outcome: DVInstallOutcome.accepted);
    await const DVInstall().prompt();
    expect(const DVInstall().isInstalled, isTrue);
  });

  test('a signal reports availability, so UI can appear when it does', () {
    // The affordance has to show up when the browser decides the app is
    // installable, which is not at first frame. Polling for it in a build
    // method is the alternative, and it is worse.
    final List<bool> seen = <bool>[];
    final void Function() stop =
        DVInstallPrompt.listen((bool available) => seen.add(available));
    addTearDown(stop);

    DVInstallPrompt.captureForTest();
    expect(seen, <bool>[true]);
  });

  test('a listener stops when it is cancelled', () {
    final List<bool> seen = <bool>[];
    DVInstallPrompt.listen(seen.add)();
    DVInstallPrompt.captureForTest();
    expect(seen, isEmpty);
  });

  group('the browser is the one that answers', () {
    // The outcome tests above set _outcome themselves and then assert it
    // comes back, which proves the seam and not the path: in a browser
    // nothing ever set it, so show() reported accepted whatever the person
    // at the screen chose, and marked the application installed.
    //
    // Worse, the binding that calls the browser's own prompt() was written
    // and called by nothing, so tapping Install never opened the browser's
    // dialog at all.
    tearDown(() => DVNativeBridge.unregister('install.prompt'));

    test('the prompt is actually asked for', () async {
      int asked = 0;
      DVNativeBridge.register('install.prompt', (Object? _) async {
        asked++;
        return 'accepted';
      });
      DVInstallPrompt.captureForTest();

      await DVInstallPrompt.show();

      expect(asked, 1, reason: 'the browser was never asked');
    });

    test('a dismissal comes back as a dismissal', () async {
      DVNativeBridge.register('install.prompt', (Object? _) async => 'dismissed');
      DVInstallPrompt.captureForTest();

      expect(await DVInstallPrompt.show(), DVInstallOutcome.dismissed);
    });

    test('a dismissed app is not an installed app', () async {
      // The half that is visible to somebody: marking it installed hides the
      // affordance, so an application the user declined to install can never
      // be installed again from inside it.
      DVNativeBridge.register('install.prompt', (Object? _) async => 'dismissed');
      DVInstallPrompt.captureForTest();

      await DVInstallPrompt.show();

      expect(DVInstallPrompt.installed, isFalse);
    });

    test('an acceptance installs it', () async {
      DVNativeBridge.register('install.prompt', (Object? _) async => 'accepted');
      DVInstallPrompt.captureForTest();

      expect(await DVInstallPrompt.show(), DVInstallOutcome.accepted);
      expect(DVInstallPrompt.installed, isTrue);
    });

    test('anything the browser does not recognise is a dismissal', () async {
      // The browser answers accepted or dismissed. Treating an unknown third
      // answer as acceptance would install nothing and say it had.
      DVNativeBridge.register('install.prompt', (Object? _) async => 'maybe');
      DVInstallPrompt.captureForTest();

      expect(await DVInstallPrompt.show(), DVInstallOutcome.dismissed);
      expect(DVInstallPrompt.installed, isFalse);
    });

    test('with no binding at all the seam still decides', () async {
      // Every non-web target has no install prompt binding, and the tests
      // above this group depend on the seam continuing to work.
      DVInstallPrompt.captureForTest(outcome: DVInstallOutcome.dismissed);

      expect(await DVInstallPrompt.show(), DVInstallOutcome.dismissed);
    });
  });
}
