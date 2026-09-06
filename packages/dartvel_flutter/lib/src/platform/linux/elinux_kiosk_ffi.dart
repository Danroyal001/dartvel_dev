/// Holding a kiosk on an embedded Linux device.
///
/// The desktop implementation grabs keys through X11. An eLinux kiosk has no
/// X11 and no window manager: it draws on DRM/KMS and already owns the
/// display, so "which application is on top" is not the question. The
/// question is whether somebody can get off it, and there are two ways they
/// can.
///
/// A virtual terminal switch. Ctrl+Alt+F2 leaves the application running and
/// puts a login prompt in front of it, on a unit in a lobby, and the
/// application never finds out. `VT_LOCKSWITCH` is the kernel's answer and it
/// is one ioctl.
///
/// And the console underneath, which is still in text mode: kernel messages
/// paint over the framebuffer while the application is drawing on it, so a
/// unit that has been up for a month has a USB reset notice across the middle
/// of it. `KD_GRAPHICS` says the console is not to draw.
///
/// Both need `CAP_SYS_TTY_CONFIG`. A kiosk unit started by the generated
/// systemd unit has it; a developer's shell and a CI runner do not -- so the
/// refusal is the common path and it is the one that has to be right. The
/// specification's rule for a kiosk that cannot hold is that it says so:
/// DV-KIOSK-007, naming the part that was not held. A kiosk reporting success
/// while somebody can Ctrl+Alt+F2 out of it is worse than one that says it
/// could not.
library dartvel_flutter.platform.linux.elinux_kiosk;

import 'dart:async';
import 'dart:ffi';

// Not a show clause: the code for a degradation lives on an extension in
// that library, and a show list that names only the enum filters the
// extension out of scope -- so .code stops existing, in every package that
// compiles this file.
import 'package:dartvel_core/dartvel.dart';
import 'package:ffi/ffi.dart';

/// `VT_LOCKSWITCH`: no more virtual terminal switching until it is undone.
const int dvVtLockSwitch = 0x560B;

/// `VT_UNLOCKSWITCH`.
const int dvVtUnlockSwitch = 0x560C;

/// `KDSETMODE`, with the two modes it takes.
const int dvKdSetMode = 0x4B3A;
const int dvKdText = 0;
const int dvKdGraphics = 1;

/// The console this works on.
///
/// `/dev/tty0` is the current virtual terminal rather than a particular one,
/// which is what a service that did not open a terminal of its own wants.
const String dvConsole = '/dev/tty0';

/// What a failure means here, in words somebody can act on.
///
/// Two errnos matter and they send a person to entirely different places, so
/// telling them apart is the whole value of this function.
String dvElinuxKioskFailure(int errno, String operation) {
  switch (errno) {
    case 1: // EPERM
      return 'Not allowed to $operation. This needs CAP_SYS_TTY_CONFIG, which '
          'the generated systemd unit grants and a shell does not: run the '
          'application as the unit does, or add the capability to it.';
    case 13: // EACCES
      return 'Not allowed to open the console to $operation. The device node '
          'belongs to root and to the tty group; the generated systemd unit '
          'runs where it can be opened.';
    case 19: // ENODEV
    case 2: // ENOENT
      return 'There is no virtual terminal on this machine, so there is '
          'nothing to $operation. That is a container or a device booted '
          'without one, and it is not a permissions problem.';
    default:
      return 'Could not $operation (errno $errno).';
  }
}

/// What enforcing actually achieved.
class DVElinuxKioskResult {
  const DVElinuxKioskResult({required this.held, required this.unheld});

  /// Whether every part was held.
  final bool held;

  /// The parts that were not, by what they were, and why.
  ///
  /// Never empty when [held] is false. A kiosk that could not hold and says
  /// nothing about which part is one an operator reads as working.
  final Map<String, String> unheld;

  /// The diagnostic for this result.
  DVKioskDegradation get degradation => held
      ? DVKioskDegradation.none
      : DVKioskDegradation.bindingMissing;
}

typedef _OpenNative = Int32 Function(Pointer<Utf8> path, Int32 flags);
typedef _OpenDart = int Function(Pointer<Utf8> path, int flags);
typedef _CloseNative = Int32 Function(Int32 fd);
typedef _CloseDart = int Function(int fd);
typedef _IoctlNative = Int32 Function(Int32 fd, Uint64 request, Uint64 argument);
typedef _IoctlDart = int Function(int fd, int request, int argument);

/// The eLinux kiosk.
class DVElinuxKiosk {
  DVElinuxKiosk._();

  static DynamicLibrary? _libc;
  static DynamicLibrary get _c => _libc ??= DynamicLibrary.open('libc.so.6');

  /// What was actually taken, so release gives back only that.
  ///
  /// Restoring a mode that was never changed would put a console into text
  /// mode that the operator had deliberately left in graphics.
  static bool _switchLocked = false;
  static bool _consoleSilenced = false;

  /// The bindings, under the names a kiosk already uses.
  ///
  /// Registered only where X11 is absent. A desktop holds a kiosk by
  /// grabbing keys from a window manager, and taking the console there would
  /// be a second enforcement nobody asked for -- on a developer's own
  /// machine, in the middle of their session.
  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind,
  ) {
    bind('kiosk.enforce', (Object? _) async {
      final DVElinuxKioskResult result = await enforce();
      return <String, Object?>{
        'held': result.held,
        'unheld': result.unheld,
        // The code travels with the result rather than being worked out
        // again by whoever reads it, because a kiosk that could not hold
        // and reports no code reads exactly like one that did.
        'code': result.degradation.code,
      };
    });
    bind('kiosk.release', (Object? _) async {
      await release();
      return true;
    });
  }

  /// Takes the console, as far as this machine will allow.
  ///
  /// Both parts are attempted even when the first fails: they are
  /// independent, and a device that allows one and not the other should hold
  /// the one it can rather than neither.
  static Future<DVElinuxKioskResult> enforce() async {
    final Map<String, String> unheld = <String, String>{};

    final int fd = _openConsole();
    if (fd < 0) {
      final int code = _errno();
      final String why = dvElinuxKioskFailure(code, 'open $dvConsole');
      return DVElinuxKioskResult(
        held: false,
        unheld: <String, String>{
          'the virtual terminal switch': why,
          'the console text mode': why,
        },
      );
    }

    try {
      if (_ioctl(fd, dvVtLockSwitch, 0) < 0) {
        unheld['the virtual terminal switch'] =
            dvElinuxKioskFailure(_errno(), 'lock the console switch');
      } else {
        _switchLocked = true;
      }

      if (_ioctl(fd, dvKdSetMode, dvKdGraphics) < 0) {
        unheld['the console text mode'] =
            dvElinuxKioskFailure(_errno(), 'stop the console drawing');
      } else {
        _consoleSilenced = true;
      }
    } finally {
      _closeConsole(fd);
    }

    return DVElinuxKioskResult(held: unheld.isEmpty, unheld: unheld);
  }

  /// Gives back whatever was taken.
  ///
  /// Only what was taken. An application that always releases on shutdown
  /// runs this on the path where the hold never happened, and putting the
  /// console into text mode there would change a machine this never touched.
  static Future<void> release() async {
    if (!_switchLocked && !_consoleSilenced) return;
    final int fd = _openConsole();
    if (fd < 0) return;
    try {
      if (_switchLocked) {
        _ioctl(fd, dvVtUnlockSwitch, 0);
        _switchLocked = false;
      }
      if (_consoleSilenced) {
        _ioctl(fd, dvKdSetMode, dvKdText);
        _consoleSilenced = false;
      }
    } finally {
      _closeConsole(fd);
    }
  }

  static int _openConsole() {
    final Pointer<Utf8> path = dvConsole.toNativeUtf8();
    try {
      // O_RDWR | O_NOCTTY: opening a terminal without this makes it the
      // process's controlling terminal, and a service that acquires one
      // starts receiving signals meant for whoever is sitting at it.
      return _c.lookupFunction<_OpenNative, _OpenDart>('open')(path, 2 | 0x100);
    } finally {
      calloc.free(path);
    }
  }

  static void _closeConsole(int fd) =>
      _c.lookupFunction<_CloseNative, _CloseDart>('close')(fd);

  static int _ioctl(int fd, int request, int argument) =>
      _c.lookupFunction<_IoctlNative, _IoctlDart>('ioctl')(fd, request, argument);

  static int _errno() {
    final Pointer<Int32> Function() location = _c
        .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            '__errno_location');
    return location().value;
  }
}
