@TestOn('linux')
library;

// Holding a kiosk on an embedded Linux device.
//
// The desktop implementation grabs keys through X11. An eLinux kiosk has no
// X11 and no window manager: it draws on DRM/KMS and it already owns the
// display, so the question is not which application is on top. It is whether
// somebody can get off it, and there are two ways they can.
//
// A virtual terminal switch. Ctrl+Alt+F2 leaves the application running and
// puts a login prompt in front of it, on a unit in a lobby, and the
// application never knows. The kernel offers VT_LOCKSWITCH for exactly this
// and it is one ioctl.
//
// And the console itself, which is still in text mode underneath: kernel
// messages paint over the framebuffer while the application is drawing on it.
// KD_GRAPHICS says the console is not to draw.
//
// Both need CAP_SYS_TTY_CONFIG, which a kiosk unit has and a CI runner does
// not -- so the case this suite can actually exercise is the refusal, and the
// refusal is the part that matters. The specification's rule is that a kiosk
// which cannot hold says so: DV-KIOSK-007 with the part that was not held
// named, rather than a success that leaves somebody believing the unit is
// locked.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/src/platform/linux/elinux_kiosk_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the ioctls it uses', () {
    test('VT_LOCKSWITCH and VT_UNLOCKSWITCH are the kernel numbers', () {
      // Written out rather than computed. These carry no struct and no size,
      // so there is no encoder to check them against -- only the header.
      expect(dvVtLockSwitch, 0x560B);
      expect(dvVtUnlockSwitch, 0x560C);
    });

    test('KDSETMODE and its two modes are the kernel numbers', () {
      expect(dvKdSetMode, 0x4B3A);
      expect(dvKdText, 0);
      expect(dvKdGraphics, 1);
    });
  });

  group('what a refusal says', () {
    test('no permission names the capability, not the call', () {
      // EPERM here is one thing: the process does not have
      // CAP_SYS_TTY_CONFIG. Told "errno 1", somebody goes looking at the
      // ioctl number.
      final String message = dvElinuxKioskFailure(1, 'lock the console');

      expect(message, contains('CAP_SYS_TTY_CONFIG'));
      expect(message, contains('lock the console'));
    });

    test('no console says there is no console', () {
      // A container, or a device booted without a virtual terminal at all.
      // That is not a permissions problem and sending somebody to fix
      // permissions wastes their afternoon.
      expect(dvElinuxKioskFailure(19, 'lock the console').toLowerCase(),
          contains('no virtual terminal'));
      expect(dvElinuxKioskFailure(2, 'lock the console').toLowerCase(),
          contains('no virtual terminal'));
    });

    test('anything else still names the operation and the number', () {
      final String message = dvElinuxKioskFailure(4242, 'blank the console');

      expect(message, contains('blank the console'));
      expect(message, contains('4242'));
    });
  });

  group('holding it here, where it cannot be held', () {
    test('it does not throw, on a machine that will not let it', () async {
      // A kiosk application calls this at startup. Whatever the answer, it
      // has to be an answer.
      final DVElinuxKioskResult result = await DVElinuxKiosk.enforce();

      expect(result, isNotNull);
    });

    test('a part it could not hold is named, not swallowed', () async {
      // The whole point. A runner has no CAP_SYS_TTY_CONFIG, so at least one
      // of the two will refuse -- and the result has to carry which, or an
      // operator reads "kiosk enforced" for a unit somebody can Ctrl+Alt+F2
      // out of.
      final DVElinuxKioskResult result = await DVElinuxKiosk.enforce();

      if (result.held) {
        // The runner turned out to have the capability. Then both parts must
        // be held rather than one, or the report disagrees with itself.
        expect(result.unheld, isEmpty);
        return;
      }
      expect(result.unheld, isNotEmpty);
      for (final String reason in result.unheld.values) {
        expect(reason, isNotEmpty);
      }
    });

    test('not holding it is DV-KIOSK-007, which is the code for this', () async {
      // The specification gives a missing binding its own diagnostic. A
      // kiosk that cannot hold and reports no code is indistinguishable from
      // one that held.
      final DVElinuxKioskResult result = await DVElinuxKiosk.enforce();

      if (result.held) return;
      expect(result.degradation, DVKioskDegradation.bindingMissing);
      expect(result.degradation.code, 'DV-KIOSK-007');
    });

    test('releasing after a refusal is not itself a failure', () async {
      // Nothing was taken, so nothing has to be given back -- and an
      // application that always releases on shutdown must not crash on the
      // path where the hold never happened.
      await DVElinuxKiosk.enforce();

      await expectLater(DVElinuxKiosk.release(), completes);
    });
  });
}
