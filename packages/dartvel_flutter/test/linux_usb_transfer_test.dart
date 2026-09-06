@TestOn('linux')
library;

// Talking to a USB device, not just listing one.
//
// Reading the bus was built and opening a device was named a different job
// and left. It is the half a kiosk needs to do anything with the hardware it
// found: a scanner that reports a mode, a payment terminal that answers a
// status request, a printer that takes a page.
//
// Linux answers this through usbfs -- ioctls on /dev/bus/usb/BBB/DDD -- and
// what makes it worth its own suite is that the request numbers are computed
// rather than named. An ioctl number encodes a direction, a struct size, a
// type letter and an index, and getting any of them wrong produces a number
// that is still a valid ioctl: the kernel runs a different one, or returns
// ENOTTY, and neither says which of the four fields was wrong. They are
// checked here against the values the kernel headers actually define.
//
// The rest is what the errors mean. EACCES on a device node is not a bug in
// the caller's code, it is a udev rule nobody has written, and EBUSY almost
// always means a kernel driver already holds the interface -- which needs
// detaching, not retrying. A caller handed "errno 13" learns neither.
import 'package:dartvel_flutter/src/platform/linux/linux_usb_transfer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the ioctl numbers', () {
    // From <linux/usbdevice_fs.h> on a 64-bit kernel. Written out rather
    // than recomputed, or the test would only prove the encoder agrees with
    // itself.
    test('CLAIMINTERFACE is the number the kernel defines', () {
      expect(dvUsbClaimInterface, 0x8004550F);
    });

    test('RELEASEINTERFACE is the number the kernel defines', () {
      expect(dvUsbReleaseInterface, 0x80045510);
    });

    test('CONTROL carries the size of the struct it is given', () {
      // The size is part of the number. A struct laid out wrongly -- a
      // pointer where the kernel padded, say -- produces a different ioctl
      // that the kernel does not recognise, and the failure names nothing.
      expect(dvUsbControl, 0xC0185500);
    });

    test('BULK carries its own size, which happens to match', () {
      expect(dvUsbBulk, 0xC0185502);
    });

    test('RESET has no argument, so it carries no size', () {
      expect(dvUsbReset, 0x00005514);
    });

    test('the encoder is what produced them, not a table of literals', () {
      // If the constants above were hand-written the tests would prove
      // nothing about the next one somebody adds. This is the rule they all
      // come from.
      expect(dvUsbIoctlNumber(direction: 2, size: 4, index: 15),
          dvUsbClaimInterface);
      expect(dvUsbIoctlNumber(direction: 3, size: 24, index: 0), dvUsbControl);
      expect(dvUsbIoctlNumber(direction: 0, size: 0, index: 20), dvUsbReset);
    });

    test('the direction bits are the two the kernel uses, in its order', () {
      // Read is 2 and write is 1 -- which is the opposite of the order they
      // are usually said in, and a swap produces a number that is a valid
      // ioctl for something else entirely.
      expect(dvUsbIoctlNumber(direction: 2, size: 0, index: 0), 0x80005500);
      expect(dvUsbIoctlNumber(direction: 1, size: 0, index: 0), 0x40005500);
    });
  });

  group('the device node for a device', () {
    test('is the bus and address, padded the way the kernel writes them', () {
      // /dev/bus/usb/001/004, not /dev/bus/usb/1/4. A path built without
      // padding does not exist, and the error is a missing file rather than
      // anything about USB.
      expect(dvUsbDeviceNode(bus: 1, address: 4), '/dev/bus/usb/001/004');
      expect(dvUsbDeviceNode(bus: 12, address: 130), '/dev/bus/usb/012/130');
    });
  });

  group('what an error means', () {
    test('permission denied names the rule nobody wrote', () {
      // The most common failure by a distance, and it is not a bug in the
      // caller's code: the device node belongs to root and the application
      // is not root. Told "errno 13", somebody goes looking at their own
      // transfer code.
      final String message = dvUsbFailure(13, '/dev/bus/usb/001/004');

      expect(message, contains('/dev/bus/usb/001/004'));
      expect(message.toLowerCase(), contains('udev'));
    });

    test('busy names the kernel driver, because that is what it is', () {
      // EBUSY on a claim means a kernel driver already has the interface --
      // usbhid on a scanner, usb-storage on a reader. It needs detaching,
      // and retrying never works.
      final String message = dvUsbFailure(16, '/dev/bus/usb/001/004');

      expect(message.toLowerCase(), contains('driver'));
    });

    test('no such device is being unplugged, not a bad address', () {
      final String message = dvUsbFailure(19, '/dev/bus/usb/001/004');

      expect(message.toLowerCase(), contains('unplug'));
    });

    test('a timeout says so rather than looking like a failure', () {
      // A device that did not answer in time is a device that may answer
      // next time. Reported as a hard failure, a kiosk stops asking.
      expect(dvUsbFailure(110, '/dev/bus/usb/001/004').toLowerCase(),
          contains('did not answer'));
    });

    test('a code it does not know still names the path and the number', () {
      final String message = dvUsbFailure(4242, '/dev/bus/usb/001/004');

      expect(message, contains('/dev/bus/usb/001/004'));
      expect(message, contains('4242'));
    });
  });

  group('opening a device that is not there', () {
    test('fails by name rather than throwing something from dart:ffi', () async {
      // A runner has no USB devices, which is the case worth checking: the
      // path does not exist and the answer has to be about the device
      // rather than about a null pointer.
      expect(
        () => DVLinuxUsbTransfer.open(bus: 199, address: 199),
        throwsA(predicate((Object? e) =>
            '$e'.contains('/dev/bus/usb/199/199'), 'names the device node')),
      );
    });
  });
}
