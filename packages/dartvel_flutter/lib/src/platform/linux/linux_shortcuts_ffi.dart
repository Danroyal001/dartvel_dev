/// Global shortcuts on Linux, through XGrabKey.
///
/// A grab belongs to the X connection that made it and its key events arrive
/// on that connection only, so the grabbing and the listening have to happen
/// on one connection -- and listening means pumping events, which must not
/// block the UI isolate. So a pump isolate owns a connection of its own:
/// grabs and ungrabs are sent to it as commands, key presses come back as
/// events, and the UI isolate matches them against what was registered.
///
/// Xlib's default error handler exits the process. A grab that collides with
/// another application's is an X error, so a handler is installed that
/// records it instead, and the collision is reported as a refused register
/// rather than as the application vanishing.
library dartvel.platform.linux.shortcuts;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVShortcuts, DVAccelerator;
import 'x11_keys.dart';

// --- Xlib --------------------------------------------------------------------

typedef _XOpenDisplayN = Pointer<Void> Function(Pointer<Utf8>);
typedef _XOpenDisplayD = Pointer<Void> Function(Pointer<Utf8>);
typedef _XCloseDisplayN = Int32 Function(Pointer<Void>);
typedef _XCloseDisplayD = int Function(Pointer<Void>);
typedef _XDefaultRootWindowN = Uint64 Function(Pointer<Void>);
typedef _XDefaultRootWindowD = int Function(Pointer<Void>);
typedef _XGrabKeyN = Int32 Function(
    Pointer<Void>, Int32, Uint32, Uint64, Int32, Int32, Int32);
typedef _XGrabKeyD = int Function(Pointer<Void>, int, int, int, int, int, int);
typedef _XUngrabKeyN = Int32 Function(Pointer<Void>, Int32, Uint32, Uint64);
typedef _XUngrabKeyD = int Function(Pointer<Void>, int, int, int);
typedef _XStringToKeysymN = Uint64 Function(Pointer<Utf8>);
typedef _XStringToKeysymD = int Function(Pointer<Utf8>);
typedef _XKeysymToKeycodeN = Uint8 Function(Pointer<Void>, Uint64);
typedef _XKeysymToKeycodeD = int Function(Pointer<Void>, int);
typedef _XPendingN = Int32 Function(Pointer<Void>);
typedef _XPendingD = int Function(Pointer<Void>);
typedef _XNextEventN = Int32 Function(Pointer<Void>, Pointer<Uint8>);
typedef _XNextEventD = int Function(Pointer<Void>, Pointer<Uint8>);
typedef _XSyncN = Int32 Function(Pointer<Void>, Int32);
typedef _XSyncD = int Function(Pointer<Void>, int);
typedef _XErrorHandlerN = Int32 Function(Pointer<Void>, Pointer<Uint8>);
typedef _XSetErrorHandlerN = Pointer<NativeFunction<_XErrorHandlerN>> Function(
    Pointer<NativeFunction<_XErrorHandlerN>>);
typedef _XSetErrorHandlerD = Pointer<NativeFunction<_XErrorHandlerN>> Function(
    Pointer<NativeFunction<_XErrorHandlerN>>);

const int _keyPress = 2;
const int _grabModeAsync = 1;

/// XEvent is 192 bytes; these are XKeyEvent's field offsets on LP64.
const int _eventBytes = 192;
const int _typeOffset = 0;
const int _stateOffset = 80;
const int _keycodeOffset = 84;

/// The last X error code the handler saw, or 0. Reset before a request whose
/// failure is an error rather than a return value -- XGrabKey is one.
int _lastXError = 0;

int _onXError(Pointer<Void> display, Pointer<Uint8> event) {
  // XErrorEvent: type @0, display @8, resourceid @16, serial @24,
  // error_code @32 (uchar).
  _lastXError = event[32];
  return 0;
}

// --- The pump isolate --------------------------------------------------------

/// Runs on its own isolate with its own connection.
Future<void> _pumpMain(SendPort toMain) async {
  final ReceivePort commands = ReceivePort();
  toMain.send(commands.sendPort);

  final DynamicLibrary x11 = DynamicLibrary.open('libX11.so.6');
  final _XOpenDisplayD open =
      x11.lookupFunction<_XOpenDisplayN, _XOpenDisplayD>('XOpenDisplay');
  final Pointer<Void> display = open(nullptr);
  if (display == nullptr) {
    toMain.send(<String, Object?>{'op': 'dead', 'reason': 'no X display'});
    commands.close();
    return;
  }

  x11.lookupFunction<_XSetErrorHandlerN, _XSetErrorHandlerD>('XSetErrorHandler')(
      Pointer.fromFunction<_XErrorHandlerN>(_onXError, 0));

  final int root = x11.lookupFunction<_XDefaultRootWindowN,
      _XDefaultRootWindowD>('XDefaultRootWindow')(display);
  final _XGrabKeyD grabKey =
      x11.lookupFunction<_XGrabKeyN, _XGrabKeyD>('XGrabKey');
  final _XUngrabKeyD ungrabKey =
      x11.lookupFunction<_XUngrabKeyN, _XUngrabKeyD>('XUngrabKey');
  final _XStringToKeysymD stringToKeysym =
      x11.lookupFunction<_XStringToKeysymN, _XStringToKeysymD>('XStringToKeysym');
  final _XKeysymToKeycodeD keysymToKeycode = x11
      .lookupFunction<_XKeysymToKeycodeN, _XKeysymToKeycodeD>('XKeysymToKeycode');
  final _XPendingD pending =
      x11.lookupFunction<_XPendingN, _XPendingD>('XPending');
  final _XNextEventD nextEvent =
      x11.lookupFunction<_XNextEventN, _XNextEventD>('XNextEvent');
  final _XSyncD sync = x11.lookupFunction<_XSyncN, _XSyncD>('XSync');
  final _XCloseDisplayD close =
      x11.lookupFunction<_XCloseDisplayN, _XCloseDisplayD>('XCloseDisplay');

  final Pointer<Uint8> event = calloc<Uint8>(_eventBytes);

  // Polled rather than blocked in XNextEvent, so commands keep arriving
  // between events. 20ms is well under what a person notices for a shortcut.
  final Timer pump = Timer.periodic(const Duration(milliseconds: 20), (_) {
    while (pending(display) > 0) {
      nextEvent(display, event);
      if (event[_typeOffset] == _keyPress) {
        final int state = event.cast<Uint32>()[_stateOffset ~/ 4];
        final int keycode = event.cast<Uint32>()[_keycodeOffset ~/ 4];
        toMain.send(<String, Object?>{'op': 'key', 'keycode': keycode, 'state': state});
      }
    }
  });

  await for (final Object? message in commands) {
    if (message is! Map) continue;
    switch (message['op']) {
      case 'grab':
        final String keysymName = '${message['keysym']}';
        final int mask = message['mask']! as int;
        final Pointer<Utf8> name = keysymName.toNativeUtf8();
        final int keysym = stringToKeysym(name);
        calloc.free(name);
        if (keysym == 0) {
          toMain.send(<String, Object?>{
            'op': 'grabbed',
            'id': message['id'],
            'ok': false,
            'error': '"$keysymName" is not a key this X server knows.',
          });
          continue;
        }
        final int keycode = keysymToKeycode(display, keysym);
        if (keycode == 0) {
          toMain.send(<String, Object?>{
            'op': 'grabbed',
            'id': message['id'],
            'ok': false,
            'error': '"$keysymName" is not on this keyboard layout.',
          });
          continue;
        }
        _lastXError = 0;
        for (final int m in dvX11GrabMasks(mask)) {
          grabKey(display, keycode, m, root, 1, _grabModeAsync, _grabModeAsync);
        }
        // The grab is a request; its failure is an error event, not a return
        // value. Sync forces the server to answer before this reports success.
        sync(display, 0);
        if (_lastXError != 0) {
          for (final int m in dvX11GrabMasks(mask)) {
            ungrabKey(display, keycode, m, root);
          }
          sync(display, 0);
          toMain.send(<String, Object?>{
            'op': 'grabbed',
            'id': message['id'],
            'ok': false,
            'error': 'The X server refused the grab (error $_lastXError); '
                'another application probably holds that shortcut.',
          });
          continue;
        }
        toMain.send(<String, Object?>{
          'op': 'grabbed',
          'id': message['id'],
          'ok': true,
          'keycode': keycode,
          'mask': mask,
        });
      case 'ungrab':
        final int keycode = message['keycode']! as int;
        final int mask = message['mask']! as int;
        for (final int m in dvX11GrabMasks(mask)) {
          ungrabKey(display, keycode, m, root);
        }
        sync(display, 0);
        toMain.send(<String, Object?>{'op': 'ungrabbed', 'id': message['id']});
      case 'stop':
        pump.cancel();
        calloc.free(event);
        close(display);
        commands.close();
        return;
    }
  }
}

// --- The UI-isolate side ------------------------------------------------------

/// What one registered shortcut grabbed.
class _Grab {
  const _Grab(this.keycode, this.mask);
  final int keycode;
  final int mask;
}

/// The Linux global-shortcut binding.
class DVLinuxShortcuts {
  const DVLinuxShortcuts._();

  static SendPort? _toPump;
  static ReceivePort? _fromPump;
  static final Map<String, _Grab> _grabs = <String, _Grab>{};
  static final Map<String, Completer<Map<Object?, Object?>>> _replies =
      <String, Completer<Map<Object?, Object?>>>{};

  static const Set<String> implemented = <String>{
    'shortcuts.register',
    'shortcuts.unregister',
  };

  /// Registers the bindings. The pump starts on the first grab, so an
  /// application that never registers a shortcut never opens a second X
  /// connection.
  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    bind('shortcuts.register', (Object? arguments) async {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      final String id = '${map['id'] ?? ''}';
      final String accelerator = '${map['accelerator'] ?? ''}';
      if (id.isEmpty) throw ArgumentError('shortcuts.register needs an id.');
      final DVAccelerator parsed = DVAccelerator.parse(accelerator);

      // Re-registering an id releases what it held first, or the old keys
      // stay grabbed with nothing listening for them.
      if (_grabs.containsKey(id)) await _ungrab(id);

      final Map<Object?, Object?> reply = await _send(id, <String, Object?>{
        'op': 'grab',
        'id': id,
        'keysym': dvX11KeysymName(parsed.key),
        'mask': dvX11ModifierMask(parsed.modifiers),
      });
      if (reply['ok'] != true) {
        throw StateError('${reply['error'] ?? 'the grab was refused'}');
      }
      _grabs[id] = _Grab(reply['keycode']! as int, reply['mask']! as int);
      return true;
    });

    bind('shortcuts.unregister', (Object? arguments) async {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      final String id = '${map['id'] ?? ''}';
      if (!_grabs.containsKey(id)) return true;
      await _ungrab(id);
      return true;
    });
  }

  static Future<void> _ungrab(String id) async {
    final _Grab? grab = _grabs.remove(id);
    if (grab == null) return;
    await _send(id, <String, Object?>{
      'op': 'ungrab',
      'id': id,
      'keycode': grab.keycode,
      'mask': grab.mask,
    });
  }

  /// Sends a command and waits for the reply carrying the same id.
  static Future<Map<Object?, Object?>> _send(
      String id, Map<String, Object?> command) async {
    await _ensurePump();
    final Completer<Map<Object?, Object?>> reply =
        Completer<Map<Object?, Object?>>();
    _replies[id] = reply;
    _toPump!.send(command);
    return reply.future.timeout(const Duration(seconds: 5), onTimeout: () {
      _replies.remove(id);
      return <Object?, Object?>{'ok': false, 'error': 'the X server did not answer'};
    });
  }

  static Future<void> _ensurePump() async {
    if (_toPump != null) return;
    final ReceivePort fromPump = ReceivePort();
    final Completer<SendPort> ready = Completer<SendPort>();
    fromPump.listen((Object? message) {
      if (message is SendPort) {
        ready.complete(message);
        return;
      }
      if (message is! Map) return;
      switch (message['op']) {
        case 'key':
          _onKey(message['keycode']! as int, message['state']! as int);
        case 'grabbed':
        case 'ungrabbed':
          _replies.remove('${message['id']}')?.complete(message);
        case 'dead':
          for (final Completer<Map<Object?, Object?>> c in _replies.values) {
            c.complete(<Object?, Object?>{'ok': false, 'error': message['reason']});
          }
          _replies.clear();
      }
    });
    _fromPump = fromPump;
    // The isolate exits itself on 'stop'; no handle is kept because there is
    // nothing to do with one that the command does not already do.
    await Isolate.spawn(_pumpMain, fromPump.sendPort,
        debugName: 'dartvel-shortcuts');
    _toPump = await ready.future;
  }

  /// A key event from the pump: every registered id whose grab it matches is
  /// dispatched.
  static void _onKey(int keycode, int state) {
    for (final MapEntry<String, _Grab> entry in _grabs.entries) {
      if (entry.value.keycode == keycode &&
          dvX11StateMatches(state: state, requested: entry.value.mask)) {
        DVShortcuts.dispatch(entry.key);
      }
    }
  }

  /// Releases every grab and stops the pump. Intended for tests and for a
  /// clean shutdown: a grab left behind eats the keys for every other
  /// application until the process dies.
  static Future<void> unregister() async {
    for (final String id in List<String>.of(_grabs.keys)) {
      await _ungrab(id);
    }
    _toPump?.send(<String, Object?>{'op': 'stop'});
    _fromPump?.close();
    _toPump = null;
    _fromPump = null;
  }
}
