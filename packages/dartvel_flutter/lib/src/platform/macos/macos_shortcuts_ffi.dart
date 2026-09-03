/// Global shortcuts on macOS: Carbon's RegisterEventHotKey.
///
/// Deprecated in name and the only system-wide hot key API there is; every
/// menu-bar utility uses it. The press arrives as a Carbon event on the main
/// run loop, which on macOS is the thread Flutter runs the root isolate on,
/// so the handler is an isolate-local callable and dispatches by id. A
/// refusal -- the same combo twice, a combo the system holds -- carries the
/// OSStatus, because "refused" without the reason is nothing to act on.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVShortcuts;
import '../accelerator.dart';

final class _EventHotKeyID extends Struct {
  @Uint32()
  external int signature;
  @Uint32()
  external int id;
}

final class _EventTypeSpec extends Struct {
  @Uint32()
  external int eventClass;
  @Uint32()
  external int eventKind;
}

typedef _HandlerNative = Int32 Function(Pointer<Void> callRef, Pointer<Void> event, Pointer<Void> userData);

const int _signature = 0x44565348; // 'DVSH'
const int _kEventClassKeyboard = 0x6B657962; // 'keyb'
const int _kEventHotKeyPressed = 5;
const int _kEventParamDirectObject = 0x2D2D2D2D; // '----'
const int _typeEventHotKeyID = 0x686B6964; // 'hkid'

const int _cmdKey = 0x0100;
const int _shiftKey = 0x0200;
const int _optionKey = 0x0800;
const int _controlKey = 0x1000;

class DVMacosShortcuts {
  const DVMacosShortcuts._();

  static const Set<String> implemented = <String>{'shortcuts.register', 'shortcuts.unregister'};

  static DynamicLibrary? _carbon;
  static DynamicLibrary? _cf;
  static NativeCallable<_HandlerNative>? _handler;
  static Pointer<Void>? _handlerRef;
  static int _nextId = 1;
  static final Map<String, int> _ids = <String, int>{};
  static final Map<int, String> _names = <int, String>{};
  static final Map<int, Pointer<Void>> _refs = <int, Pointer<Void>>{};

  /// Virtual key codes, as HIToolbox names them (kVK_*).
  static const Map<String, int> _keyCodes = <String, int>{
    'a': 0x00, 's': 0x01, 'd': 0x02, 'f': 0x03, 'h': 0x04, 'g': 0x05, 'z': 0x06, 'x': 0x07,
    'c': 0x08, 'v': 0x09, 'b': 0x0B, 'q': 0x0C, 'w': 0x0D, 'e': 0x0E, 'r': 0x0F, 'y': 0x10,
    't': 0x11, '1': 0x12, '2': 0x13, '3': 0x14, '4': 0x15, '6': 0x16, '5': 0x17, '=': 0x18,
    '9': 0x19, '7': 0x1A, '-': 0x1B, '8': 0x1C, '0': 0x1D, ']': 0x1E, 'o': 0x1F, 'u': 0x20,
    '[': 0x21, 'i': 0x22, 'p': 0x23, 'enter': 0x24, 'return': 0x24, 'l': 0x25, 'j': 0x26,
    "'": 0x27, 'k': 0x28, ';': 0x29, '\\': 0x2A, ',': 0x2B, '/': 0x2C, 'n': 0x2D, 'm': 0x2E,
    '.': 0x2F, 'tab': 0x30, 'space': 0x31, '`': 0x32, 'backspace': 0x33, 'escape': 0x35, 'esc': 0x35,
    'f5': 0x60, 'f6': 0x61, 'f7': 0x62, 'f3': 0x63, 'f8': 0x64, 'f9': 0x65, 'f11': 0x67,
    'f13': 0x69, 'f14': 0x6B, 'f10': 0x6D, 'f12': 0x6F, 'f15': 0x71, 'home': 0x73, 'pageup': 0x74,
    'delete': 0x75, 'del': 0x75, 'f4': 0x76, 'end': 0x77, 'f2': 0x78, 'pagedown': 0x79, 'f1': 0x7A,
    'left': 0x7B, 'right': 0x7C, 'down': 0x7D, 'up': 0x7E,
  };

  static int? keyCodeFor(String key) => _keyCodes[key.toLowerCase()];

  static int modifiersFor(DVAccelerator combo) {
    var mods = 0;
    for (final DVModifierKey m in combo.modifiers) {
      mods |= switch (m) {
        DVModifierKey.control => _controlKey,
        DVModifierKey.alt => _optionKey,
        DVModifierKey.shift => _shiftKey,
        DVModifierKey.meta => _cmdKey,
      };
    }
    return mods;
  }

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind) {
    bind('shortcuts.register', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final String id = '${map['id'] ?? ''}';
      if (id.isEmpty) throw ArgumentError('shortcuts.register needs an id.');
      final DVAccelerator parsed = DVAccelerator.parse('${map['accelerator'] ?? ''}', primaryIsMeta: true);
      final int? keyCode = keyCodeFor(parsed.key);
      if (keyCode == null) throw StateError('no macOS virtual key named "${parsed.key}"');

      if (_ids.containsKey(id)) _unregister(id);
      _ensureHandler();
      final int numeric = _nextId++;
      final Pointer<_EventHotKeyID> hotKeyId = calloc<_EventHotKeyID>();
      final Pointer<Pointer<Void>> ref = calloc<Pointer<Void>>();
      try {
        hotKeyId.ref
          ..signature = _signature
          ..id = numeric;
        final registerHotKey = _carbon!.lookupFunction<
            Int32 Function(Uint32, Uint32, _EventHotKeyID, Pointer<Void>, Uint32, Pointer<Pointer<Void>>),
            int Function(int, int, _EventHotKeyID, Pointer<Void>, int, Pointer<Pointer<Void>>)>('RegisterEventHotKey');
        final int status = registerHotKey(keyCode, modifiersFor(parsed), hotKeyId.ref, _applicationTarget(), 0, ref);
        if (status != 0) {
          throw StateError('RegisterEventHotKey refused (OSStatus $status'
              '${status == -9878 ? ', that combo is already registered' : ''})');
        }
        _ids[id] = numeric;
        _names[numeric] = id;
        _refs[numeric] = ref.value;
        return true;
      } finally {
        calloc.free(hotKeyId);
        calloc.free(ref);
      }
    });

    bind('shortcuts.unregister', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final String id = '${map['id'] ?? ''}';
      if (_ids.containsKey(id)) _unregister(id);
      return true;
    });
  }

  static void _unregister(String id) {
    final int? numeric = _ids.remove(id);
    if (numeric == null) return;
    _names.remove(numeric);
    final Pointer<Void>? ref = _refs.remove(numeric);
    if (ref != null) {
      _carbon!.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('UnregisterEventHotKey')(ref);
    }
  }

  static Pointer<Void> _applicationTarget() =>
      _carbon!.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('GetApplicationEventTarget')();

  /// One handler for every hot key, installed on the application target.
  static void _ensureHandler() {
    _carbon ??= DynamicLibrary.open('/System/Library/Frameworks/Carbon.framework/Carbon');
    _cf ??= DynamicLibrary.open('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');
    if (_handler != null) return;

    int onEvent(Pointer<Void> callRef, Pointer<Void> event, Pointer<Void> userData) {
      final getParameter = _carbon!.lookupFunction<
          Int32 Function(Pointer<Void>, Uint32, Uint32, Pointer<Uint32>, IntPtr, Pointer<IntPtr>, Pointer<Void>),
          int Function(Pointer<Void>, int, int, Pointer<Uint32>, int, Pointer<IntPtr>, Pointer<Void>)>('GetEventParameter');
      final Pointer<_EventHotKeyID> hotKeyId = calloc<_EventHotKeyID>();
      try {
        final int status = getParameter(event, _kEventParamDirectObject, _typeEventHotKeyID, nullptr,
            sizeOf<_EventHotKeyID>(), nullptr, hotKeyId.cast());
        if (status == 0 && hotKeyId.ref.signature == _signature) {
          final String? id = _names[hotKeyId.ref.id];
          if (id != null) DVShortcuts.dispatch(id);
        }
      } finally {
        calloc.free(hotKeyId);
      }
      return 0; // noErr
    }

    final NativeCallable<_HandlerNative> handler = NativeCallable<_HandlerNative>.isolateLocal(onEvent, exceptionalReturn: 0);
    final Pointer<_EventTypeSpec> spec = calloc<_EventTypeSpec>();
    final Pointer<Pointer<Void>> ref = calloc<Pointer<Void>>();
    try {
      spec.ref
        ..eventClass = _kEventClassKeyboard
        ..eventKind = _kEventHotKeyPressed;
      final install = _carbon!.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<NativeFunction<_HandlerNative>>, IntPtr, Pointer<_EventTypeSpec>, Pointer<Void>, Pointer<Pointer<Void>>),
          int Function(Pointer<Void>, Pointer<NativeFunction<_HandlerNative>>, int, Pointer<_EventTypeSpec>, Pointer<Void>, Pointer<Pointer<Void>>)>('InstallEventHandler');
      final int status = install(_applicationTarget(), handler.nativeFunction, 1, spec, nullptr, ref);
      if (status != 0) {
        handler.close();
        throw StateError('InstallEventHandler refused (OSStatus $status)');
      }
      _handler = handler;
      _handlerRef = ref.value;
    } finally {
      calloc.free(spec);
      calloc.free(ref);
    }
  }

  /// Runs the main run loop for [slice], so a process with no loop of its
  /// own -- a test harness -- receives the presses. A running application
  /// never needs this.
  static void pump(Duration slice) {
    _cf ??= DynamicLibrary.open('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');
    final Pointer<Void> mode = _cf!.lookup<Pointer<Void>>('kCFRunLoopDefaultMode').value;
    _cf!.lookupFunction<Int32 Function(Pointer<Void>, Double, Bool), int Function(Pointer<Void>, double, bool)>(
        'CFRunLoopRunInMode')(mode, slice.inMicroseconds / 1e6, false);
  }

  /// Lets go of every hot key and the handler. For tests and shutdown.
  static void unregister() {
    for (final String id in List<String>.of(_ids.keys)) {
      _unregister(id);
    }
    final Pointer<Void>? ref = _handlerRef;
    if (ref != null) {
      _carbon!.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('RemoveEventHandler')(ref);
      _handlerRef = null;
    }
    _handler?.close();
    _handler = null;
  }
}
