/// Talking to a USB device, through usbfs.
///
/// Listing the bus is a reader and this is not: it opens `/dev/bus/usb/BBB/DDD`
/// and drives the device with ioctls. That is a different job with a different
/// threat model, which is why it was left out of the reader -- an application
/// that only wants to know whether the scanner is plugged in should not have
/// to arrange write access to it.
///
/// usbfs rather than libusb, for the reason the rest of this directory reaches
/// for the kernel first: libusb is a dependency to ship, a licence to carry
/// and a shared object to find on a device that may be read-only, and the
/// interface underneath it is four ioctls.
///
/// The part worth being careful about is that those ioctls are *computed*. An
/// ioctl number packs a direction, the size of the struct it takes, a type
/// letter and an index into thirty-two bits, and getting any one of them
/// wrong still produces a valid number -- the kernel runs a different call or
/// answers ENOTTY, and neither says which of the four was wrong. So the
/// numbers are derived from one rule and checked against what the kernel
/// headers define.
library dartvel_flutter.platform.linux.usb_transfer;

import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// `_IOC(dir, type, nr, size)` for usbfs, whose type letter is always `U`.
///
/// [direction] is the kernel's, not the one the names suggest: read is 2 and
/// write is 1. They are the wrong way round from how anybody says them, and
/// swapping them produces a number that is a perfectly good ioctl for
/// something else.
int dvUsbIoctlNumber({
  required int direction,
  required int size,
  required int index,
}) =>
    (direction << 30) | (size << 16) | (0x55 << 8) | index;

/// `USBDEVFS_CONTROL`, taking a `usbdevfs_ctrltransfer` of 24 bytes on a
/// 64-bit kernel: five short fields, a `__u32` timeout, and a pointer the
/// compiler aligns to eight.
final int dvUsbControl = dvUsbIoctlNumber(direction: 3, size: 24, index: 0);

/// `USBDEVFS_BULK`, taking a `usbdevfs_bulktransfer`: three `unsigned int`
/// and a pointer, which comes to the same 24 bytes by a different route.
final int dvUsbBulk = dvUsbIoctlNumber(direction: 3, size: 24, index: 2);

/// `USBDEVFS_CLAIMINTERFACE`, taking the interface number.
final int dvUsbClaimInterface =
    dvUsbIoctlNumber(direction: 2, size: 4, index: 15);

/// `USBDEVFS_RELEASEINTERFACE`.
final int dvUsbReleaseInterface =
    dvUsbIoctlNumber(direction: 2, size: 4, index: 16);

/// `USBDEVFS_RESET`, which takes nothing and so carries no size.
final int dvUsbReset = dvUsbIoctlNumber(direction: 0, size: 0, index: 20);

/// The node the kernel exposes a device at.
///
/// Three digits each, zero-padded, because that is how the kernel writes
/// them. A path built without the padding does not exist, and the failure is
/// a missing file rather than anything that mentions USB.
String dvUsbDeviceNode({required int bus, required int address}) =>
    '/dev/bus/usb/${bus.toString().padLeft(3, '0')}/'
    '${address.toString().padLeft(3, '0')}';

/// What an errno from usbfs means, in words somebody can act on.
///
/// These are not general errno descriptions. On a USB device node each of
/// them has one overwhelmingly likely cause, and naming it is the difference
/// between somebody writing a udev rule and somebody rereading their own
/// transfer code.
String dvUsbFailure(int errno, String node) {
  switch (errno) {
    case 13: // EACCES
      return 'No permission to open $node. The device node belongs to root, '
          'and this is a udev rule nobody has written yet rather than a '
          'fault in the application: give the device to a group the '
          'application is in.';
    case 16: // EBUSY
      return 'A kernel driver already holds that interface on $node -- usbhid '
          'for anything that looks like a keyboard, usb-storage for anything '
          'that looks like a disk. It has to be detached; retrying will not '
          'take it.';
    case 19: // ENODEV
    case 2: // ENOENT
      return 'There is no device at $node any more. It has been unplugged, or '
          'it re-enumerated and is at a different address now.';
    case 32: // EPIPE
      return 'The device stalled the endpoint on $node. That is the device '
          'refusing the request rather than the transfer failing: the request '
          'itself is one it does not support.';
    case 110: // ETIMEDOUT
      return 'The device at $node did not answer in time. It may answer the '
          'next request; this is not a device that has gone.';
    default:
      return 'The transfer on $node failed (errno $errno).';
  }
}

typedef _OpenNative = Int32 Function(Pointer<Utf8> path, Int32 flags);
typedef _OpenDart = int Function(Pointer<Utf8> path, int flags);
typedef _CloseNative = Int32 Function(Int32 fd);
typedef _CloseDart = int Function(int fd);
typedef _IoctlNative = Int32 Function(Int32 fd, Uint64 request, Pointer<Void> argument);
typedef _IoctlDart = int Function(int fd, int request, Pointer<Void> argument);

/// `struct usbdevfs_bulktransfer`.
final class _BulkTransfer extends Struct {
  @Uint32()
  external int endpoint;
  @Uint32()
  external int length;
  @Uint32()
  external int timeout;
  // The compiler pads to eight before the pointer, and the ioctl number
  // above carries the padded size. Declared so the layout is the kernel's
  // rather than whatever Dart would otherwise choose.
  @Uint32()
  external int padding;
  external Pointer<Uint8> data;
}

/// An open USB device.
class DVLinuxUsbTransfer {
  DVLinuxUsbTransfer._(this._fd, this.node);

  final int _fd;

  /// The node it was opened at, so a failure can name it.
  final String node;

  final Set<int> _claimed = <int>{};

  static DynamicLibrary? _libc;
  static DynamicLibrary get _c => _libc ??= DynamicLibrary.open('libc.so.6');

  /// Opens the device at [bus] and [address].
  ///
  /// Throws with the node in the message. A caller handed a null pointer or
  /// an errno learns nothing about which device would not open.
  static DVLinuxUsbTransfer open({required int bus, required int address}) {
    final String node = dvUsbDeviceNode(bus: bus, address: address);
    final Pointer<Utf8> path = node.toNativeUtf8();
    try {
      // O_RDWR. A device that is only read from still needs it: a control
      // transfer is a write followed by a read on the same descriptor.
      final int fd =
          _c.lookupFunction<_OpenNative, _OpenDart>('open')(path, 2);
      if (fd < 0) throw StateError(dvUsbFailure(_errno(), node));
      return DVLinuxUsbTransfer._(fd, node);
    } finally {
      calloc.free(path);
    }
  }

  /// Claims [interface] so transfers on it are this process's.
  ///
  /// The kernel will not let two things drive one interface, which is the
  /// point: a scanner that usbhid is already reading would otherwise deliver
  /// half its bytes here and half to the input layer.
  void claim(int interface) {
    final Pointer<Uint32> value = calloc<Uint32>()..value = interface;
    try {
      if (_ioctl(dvUsbClaimInterface, value.cast()) < 0) {
        throw StateError(dvUsbFailure(_errno(), node));
      }
      _claimed.add(interface);
    } finally {
      calloc.free(value);
    }
  }

  void release(int interface) {
    final Pointer<Uint32> value = calloc<Uint32>()..value = interface;
    try {
      _ioctl(dvUsbReleaseInterface, value.cast());
      _claimed.remove(interface);
    } finally {
      calloc.free(value);
    }
  }

  /// Writes [bytes] to [endpoint], returning how many the device took.
  int write(int endpoint, Uint8List bytes, {int timeoutMs = 1000}) {
    final Pointer<Uint8> buffer = calloc<Uint8>(bytes.length);
    final Pointer<_BulkTransfer> transfer = calloc<_BulkTransfer>();
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      transfer.ref
        ..endpoint = endpoint
        ..length = bytes.length
        ..timeout = timeoutMs
        ..padding = 0
        ..data = buffer;
      final int moved = _ioctl(dvUsbBulk, transfer.cast());
      if (moved < 0) throw StateError(dvUsbFailure(_errno(), node));
      return moved;
    } finally {
      calloc.free(buffer);
      calloc.free(transfer);
    }
  }

  /// Reads up to [max] bytes from [endpoint].
  ///
  /// The endpoint number carries the direction in its top bit, and a caller
  /// that passes the wrong one gets a transfer that waits for a device which
  /// is not going to speak. It is set here rather than left to be remembered.
  Uint8List read(int endpoint, {int max = 512, int timeoutMs = 1000}) {
    final Pointer<Uint8> buffer = calloc<Uint8>(max);
    final Pointer<_BulkTransfer> transfer = calloc<_BulkTransfer>();
    try {
      transfer.ref
        ..endpoint = endpoint | 0x80
        ..length = max
        ..timeout = timeoutMs
        ..padding = 0
        ..data = buffer;
      final int moved = _ioctl(dvUsbBulk, transfer.cast());
      if (moved < 0) throw StateError(dvUsbFailure(_errno(), node));
      return Uint8List.fromList(buffer.asTypedList(moved));
    } finally {
      calloc.free(buffer);
      calloc.free(transfer);
    }
  }

  /// Releases everything claimed and closes the descriptor.
  ///
  /// The claims go back first: a descriptor closed with an interface still
  /// claimed leaves the kernel driver unbound until the device is replugged,
  /// so the next run of the application finds hardware that no longer works
  /// and nothing that says why.
  void close() {
    for (final int interface in _claimed.toList()) {
      release(interface);
    }
    _c.lookupFunction<_CloseNative, _CloseDart>('close')(_fd);
  }

  int _ioctl(int request, Pointer<Void> argument) =>
      _c.lookupFunction<_IoctlNative, _IoctlDart>('ioctl')(
          _fd, request, argument);

  static int _errno() {
    final Pointer<Int32> Function() location = _c
        .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            '__errno_location');
    return location().value;
  }
}

/// The bindings, over a handle a caller can hold.
///
/// A file descriptor is a small integer the process shares with every other
/// file it has open, and handing one to application code invites it to be
/// closed twice or read from after the device has gone. Callers get a handle
/// of this layer's own instead, which means nothing outside it.
class DVLinuxUsbTransfers {
  DVLinuxUsbTransfers._();

  static const Set<String> bindings = <String>{
    'device.usb.open',
    'device.usb.claim',
    'device.usb.write',
    'device.usb.read',
    'device.usb.close',
  };

  static final Map<int, DVLinuxUsbTransfer> _open =
      <int, DVLinuxUsbTransfer>{};
  static int _next = 1;

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind,
  ) {
    bind('device.usb.open', (Object? args) {
      final Map<Object?, Object?> a = _args(args);
      final DVLinuxUsbTransfer device = DVLinuxUsbTransfer.open(
        bus: a['bus'] is int ? a['bus']! as int : 0,
        address: a['address'] is int ? a['address']! as int : 0,
      );
      final int handle = _next++;
      _open[handle] = device;
      return handle;
    });
    bind('device.usb.claim', (Object? args) {
      final Map<Object?, Object?> a = _args(args);
      _device(a).claim(a['interface'] is int ? a['interface']! as int : 0);
      return true;
    });
    bind('device.usb.write', (Object? args) {
      final Map<Object?, Object?> a = _args(args);
      final Object? bytes = a['bytes'];
      return _device(a).write(
        a['endpoint'] is int ? a['endpoint']! as int : 0,
        Uint8List.fromList(<int>[
          for (final Object? b in bytes is List ? bytes : const <Object?>[])
            if (b is int) b,
        ]),
        timeoutMs: a['timeoutMs'] is int ? a['timeoutMs']! as int : 1000,
      );
    });
    bind('device.usb.read', (Object? args) {
      final Map<Object?, Object?> a = _args(args);
      return _device(a).read(
        a['endpoint'] is int ? a['endpoint']! as int : 0,
        max: a['max'] is int ? a['max']! as int : 512,
        timeoutMs: a['timeoutMs'] is int ? a['timeoutMs']! as int : 1000,
      );
    });
    bind('device.usb.close', (Object? args) {
      final Map<Object?, Object?> a = _args(args);
      final int handle = a['handle'] is int ? a['handle']! as int : 0;
      _open.remove(handle)?.close();
      return true;
    });
  }

  static Map<Object?, Object?> _args(Object? args) =>
      args is Map ? args : const <Object?, Object?>{};

  /// The device a handle names, or a refusal that says the handle is stale.
  ///
  /// A closed handle used again is the ordinary way this goes wrong -- a
  /// retry after an unplug -- and it has to say so rather than reach into an
  /// empty map and fail on null.
  static DVLinuxUsbTransfer _device(Map<Object?, Object?> args) {
    final int handle = args['handle'] is int ? args['handle']! as int : 0;
    final DVLinuxUsbTransfer? device = _open[handle];
    if (device == null) {
      throw StateError('USB handle $handle is not open. It was closed, or the '
          'device was unplugged and the handle released with it.');
    }
    return device;
  }
}
