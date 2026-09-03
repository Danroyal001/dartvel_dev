/// Global shortcuts on Windows: RegisterHotKey on a pump thread of its own.
///
/// Win32 delivers WM_HOTKEY to the message queue of the thread that made the
/// registration, so the hot keys are taken by an isolate that does nothing
/// but block in GetMessage: it needs no window, it never touches the Flutter
/// thread's loop, and it works in a test harness that has no loop at all.
/// Commands reach it as thread messages -- WM_APP+1 to register, WM_APP+2 to
/// unregister, each carrying the numeric id and the key -- and presses and
/// replies come back over a port. A refusal carries Win32's error, because
/// "the grab was refused" without the reason is not something the operator
/// can act on.
library;

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVShortcuts;
import '../accelerator.dart';
import 'windows_kiosk_ffi.dart' show DVWindowsKiosk;

final class _Msg extends Struct {
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int message;
  @IntPtr()
  external int wParam;
  @IntPtr()
  external int lParam;
  @Uint32()
  external int time;
  @Int32()
  external int ptX;
  @Int32()
  external int ptY;
}

const int _wmQuit = 0x0012;
const int _wmHotKey = 0x0312;
const int _wmApp = 0x8000;
const int _wmRegister = _wmApp + 1;
const int _wmUnregister = _wmApp + 2;

/// Hot-key ids the shortcuts own: 0xA000 up, clear of the kiosk's block.
const int _firstId = 0xA000;

class DVWindowsShortcuts {
  const DVWindowsShortcuts._();

  static const Set<String> implemented = <String>{'shortcuts.register', 'shortcuts.unregister'};

  static ReceivePort? _fromPump;
  static int? _pumpThread;
  static int _nextId = _firstId;
  static final Map<String, int> _ids = <String, int>{};
  static final Map<int, String> _names = <int, String>{};
  static final Map<int, Completer<Map<Object?, Object?>>> _replies = <int, Completer<Map<Object?, Object?>>>{};

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    bind('shortcuts.register', (Object? arguments) async {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final String id = '${map['id'] ?? ''}';
      if (id.isEmpty) throw ArgumentError('shortcuts.register needs an id.');
      final DVAccelerator parsed = DVAccelerator.parse('${map['accelerator'] ?? ''}');
      final int? vk = DVWindowsKiosk.virtualKeyFor(parsed.key);
      if (vk == null) throw StateError('no Win32 virtual key named "${parsed.key}"');

      if (_ids.containsKey(id)) await _unregister(id);
      final int numeric = _nextId++;
      final Map<Object?, Object?> reply = await _post(
        numeric,
        _wmRegister,
        (DVWindowsKiosk.modifiersFor(parsed) << 16) | vk,
      );
      if (reply['ok'] != true) {
        throw StateError('${reply['error'] ?? 'RegisterHotKey refused'}');
      }
      _ids[id] = numeric;
      _names[numeric] = id;
      return true;
    });

    bind('shortcuts.unregister', (Object? arguments) async {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final String id = '${map['id'] ?? ''}';
      if (!_ids.containsKey(id)) return true;
      await _unregister(id);
      return true;
    });
  }

  static Future<void> _unregister(String id) async {
    final int? numeric = _ids.remove(id);
    if (numeric == null) return;
    _names.remove(numeric);
    await _post(numeric, _wmUnregister, 0);
  }

  static Future<Map<Object?, Object?>> _post(int numeric, int message, int lParam) async {
    await _ensurePump();
    final Completer<Map<Object?, Object?>> reply = Completer<Map<Object?, Object?>>();
    _replies[numeric] = reply;
    final postThreadMessage = DynamicLibrary.open('user32.dll').lookupFunction<
        Int32 Function(Uint32, Uint32, IntPtr, IntPtr),
        int Function(int, int, int, int)>('PostThreadMessageW');
    if (postThreadMessage(_pumpThread!, message, numeric, lParam) == 0) {
      _replies.remove(numeric);
      return <Object?, Object?>{'ok': false, 'error': 'the shortcut pump did not take the message'};
    }
    return reply.future.timeout(const Duration(seconds: 5), onTimeout: () {
      _replies.remove(numeric);
      return <Object?, Object?>{'ok': false, 'error': 'the shortcut pump did not answer'};
    });
  }

  static Future<void> _ensurePump() async {
    if (_pumpThread != null) return;
    final ReceivePort fromPump = ReceivePort();
    final Completer<int> ready = Completer<int>();
    fromPump.listen((Object? message) {
      if (message is! Map) return;
      switch (message['op']) {
        case 'ready':
          ready.complete(message['thread']! as int);
        case 'key':
          final String? id = _names[message['id']! as int];
          if (id != null) DVShortcuts.dispatch(id);
        case 'registered':
        case 'unregistered':
          _replies.remove(message['id']! as int)?.complete(message);
      }
    });
    _fromPump = fromPump;
    await Isolate.spawn(_pumpMain, fromPump.sendPort, debugName: 'dartvel-shortcuts');
    _pumpThread = await ready.future;
  }

  /// The pump thread's id, for a test that posts to its queue.
  static int? get debugPumpThread => _pumpThread;

  /// The hot-key id [id] was registered under, for a test.
  static int? debugNumericId(String id) => _ids[id];

  /// Lets go of everything and stops the pump. For tests and shutdown.
  static Future<void> unregister() async {
    for (final String id in List<String>.of(_ids.keys)) {
      await _unregister(id);
    }
    final int? thread = _pumpThread;
    if (thread != null) {
      DynamicLibrary.open('user32.dll').lookupFunction<
          Int32 Function(Uint32, Uint32, IntPtr, IntPtr),
          int Function(int, int, int, int)>('PostThreadMessageW')(thread, _wmQuit, 0, 0);
    }
    _pumpThread = null;
    _fromPump?.close();
    _fromPump = null;
  }

  /// The pump: one thread, a message queue, and the hot keys it owns.
  static void _pumpMain(SendPort toMain) {
    final DynamicLibrary user32 = DynamicLibrary.open('user32.dll');
    final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
    final getMessage = user32.lookupFunction<
        Int32 Function(Pointer<_Msg>, IntPtr, Uint32, Uint32),
        int Function(Pointer<_Msg>, int, int, int)>('GetMessageW');
    final registerHotKey = user32.lookupFunction<
        Int32 Function(IntPtr, Int32, Uint32, Uint32),
        int Function(int, int, int, int)>('RegisterHotKey');
    final unregisterHotKey = user32.lookupFunction<
        Int32 Function(IntPtr, Int32),
        int Function(int, int)>('UnregisterHotKey');
    final lastError = kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
    final threadId = kernel32.lookupFunction<Uint32 Function(), int Function()>('GetCurrentThreadId');

    // A thread has no message queue until it asks for one; PeekMessage makes
    // it, so a PostThreadMessage sent before the first GetMessage is not lost.
    final peekMessage = user32.lookupFunction<
        Int32 Function(Pointer<_Msg>, IntPtr, Uint32, Uint32, Uint32),
        int Function(Pointer<_Msg>, int, int, int, int)>('PeekMessageW');
    final Pointer<_Msg> msg = calloc<_Msg>();
    peekMessage(msg, 0, _wmApp, _wmApp, 0);
    toMain.send(<String, Object?>{'op': 'ready', 'thread': threadId()});

    final Set<int> held = <int>{};
    try {
      while (getMessage(msg, 0, 0, 0) > 0) {
        final _Msg m = msg.ref;
        switch (m.message) {
          case _wmHotKey:
            toMain.send(<String, Object?>{'op': 'key', 'id': m.wParam});
          case _wmRegister:
            final int id = m.wParam;
            final int modifiers = (m.lParam >> 16) & 0xFFFF;
            final int vk = m.lParam & 0xFFFF;
            if (registerHotKey(0, id, modifiers, vk) == 0) {
              final int error = lastError();
              toMain.send(<String, Object?>{
                'op': 'registered',
                'id': id,
                'ok': false,
                'error': 'RegisterHotKey refused (Win32 error $error'
                    '${error == 1409 ? ', already registered by another window' : ''})',
              });
            } else {
              held.add(id);
              toMain.send(<String, Object?>{'op': 'registered', 'id': id, 'ok': true});
            }
          case _wmUnregister:
            final int id = m.wParam;
            unregisterHotKey(0, id);
            held.remove(id);
            toMain.send(<String, Object?>{'op': 'unregistered', 'id': id, 'ok': true});
        }
      }
    } finally {
      for (final int id in held) {
        unregisterHotKey(0, id);
      }
      calloc.free(msg);
    }
  }
}
