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
}
