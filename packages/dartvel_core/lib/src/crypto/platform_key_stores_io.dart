import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'app_key.dart';
import 'key_custody.dart';

// --- Windows: DPAPI -----------------------------------------------------------
//
// CryptProtectData seals bytes to this user on this machine; what is written
// to disk is the sealed blob, which no other account can open and which is
// worthless copied elsewhere. Per user, per machine -- the custody the spec's
// table names for Windows.

typedef _CryptProtectN = Int32 Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>,
    Pointer<Void>, Pointer<Void>, Uint32, Pointer<_DataBlob>);
typedef _CryptProtectD = int Function(Pointer<_DataBlob>, Pointer<Utf16>, Pointer<_DataBlob>,
    Pointer<Void>, Pointer<Void>, int, Pointer<_DataBlob>);
typedef _LocalFreeN = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeD = Pointer<Void> Function(Pointer<Void>);

final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;
  external Pointer<Uint8> pbData;
}

const int _cryptProtectUiForbidden = 0x1;

class DVDpapiAppKeyStore implements DVAppKeyStore {
  /// Where the sealed blob is kept.
  final String path;

  const DVDpapiAppKeyStore(this.path);

  static bool get isAvailable => Platform.isWindows;

  static DynamicLibrary get _crypt32 => DynamicLibrary.open('crypt32.dll');
  static DynamicLibrary get _kernel32 => DynamicLibrary.open('kernel32.dll');

  static Uint8List _call(String symbol, Uint8List input) {
    final _CryptProtectD fn = _crypt32.lookupFunction<_CryptProtectN, _CryptProtectD>(symbol);
    final Pointer<_DataBlob> inBlob = calloc<_DataBlob>();
    final Pointer<_DataBlob> outBlob = calloc<_DataBlob>();
    final Pointer<Uint8> bytes = calloc<Uint8>(input.length);
    final Pointer<Utf16> description = 'Dartvel application key'.toNativeUtf16();
    try {
      bytes.asTypedList(input.length).setAll(0, input);
      inBlob.ref.cbData = input.length;
      inBlob.ref.pbData = bytes;
      final int ok = fn(inBlob, description, nullptr, nullptr, nullptr, _cryptProtectUiForbidden, outBlob);
      if (ok == 0) throw StateError('$symbol failed.');
      final Uint8List out = Uint8List.fromList(outBlob.ref.pbData.asTypedList(outBlob.ref.cbData));
      _kernel32.lookupFunction<_LocalFreeN, _LocalFreeD>('LocalFree')(outBlob.ref.pbData.cast<Void>());
      return out;
    } finally {
      calloc.free(inBlob);
      calloc.free(outBlob);
      calloc.free(bytes);
      calloc.free(description);
    }
  }

  @override
  Future<Uint8List?> read() async {
    final File file = File(path);
    if (!file.existsSync()) return null;
    try {
      final Uint8List key = _call('CryptUnprotectData', file.readAsBytesSync());
      return key.length == DVAppKey.lengthBytes ? key : null;
    } on StateError {
      // Another user's blob, or another machine's: not this key.
      return null;
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    final File file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(_call('CryptProtectData', key), flush: true);
  }

  @override
  Future<void> clear() async {
    final File file = File(path);
    if (file.existsSync()) file.deleteSync();
  }
}

// --- macOS and iOS: the Keychain -----------------------------------------------
//
// One generic-password item per service and account, through the Security
// framework's SecItem API with CoreFoundation dictionaries built by hand.
//
// The item is kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly and not
// synchronizable: readable once the device has been unlocked after a boot, so
// a background task after that still has its key, and never carried to
// iCloud Keychain or restored from a backup onto another device, where the
// data it sealed does not exist.

typedef _CFStringCreateN = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _CFStringCreateD = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _CFStringGetCStringN = Uint8 Function(Pointer<Void>, Pointer<Utf8>, IntPtr, Uint32);
typedef _CFStringGetCStringD = int Function(Pointer<Void>, Pointer<Utf8>, int, int);
typedef _CFDataCreateN = Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _CFDataCreateD = Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _CFDictCreateN = Pointer<Void> Function(
    Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Pointer<Void>>, IntPtr, Pointer<Void>, Pointer<Void>);
typedef _CFDictCreateD = Pointer<Void> Function(
    Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Pointer<Void>>, int, Pointer<Void>, Pointer<Void>);
typedef _CFDictGetValueN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _CFDictGetValueD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _CFReleaseN = Void Function(Pointer<Void>);
typedef _CFReleaseD = void Function(Pointer<Void>);
typedef _CFDataLenN = IntPtr Function(Pointer<Void>);
typedef _CFDataLenD = int Function(Pointer<Void>);
typedef _CFDataPtrN = Pointer<Uint8> Function(Pointer<Void>);
typedef _CFDataPtrD = Pointer<Uint8> Function(Pointer<Void>);
typedef _CFTypeIdN = UintPtr Function(Pointer<Void>);
typedef _CFTypeIdD = int Function(Pointer<Void>);
typedef _CFTypeIdOfN = UintPtr Function();
typedef _CFTypeIdOfD = int Function();
typedef _CFBooleanGetValueN = Uint8 Function(Pointer<Void>);
typedef _CFBooleanGetValueD = int Function(Pointer<Void>);
typedef _CFNumberGetValueN = Uint8 Function(Pointer<Void>, IntPtr, Pointer<Int64>);
typedef _CFNumberGetValueD = int Function(Pointer<Void>, int, Pointer<Int64>);
typedef _SecItemAddN = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecItemAddD = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecItemCopyN = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecItemCopyD = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecItemUpdateN = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _SecItemUpdateD = int Function(Pointer<Void>, Pointer<Void>);
typedef _SecItemDeleteN = Int32 Function(Pointer<Void>);
typedef _SecItemDeleteD = int Function(Pointer<Void>);

const int _kCFStringEncodingUTF8 = 0x08000100;
const int _kCFNumberSInt64Type = 4;
const int _errSecItemNotFound = -25300;
const int _errSecDuplicateItem = -25299;

class DVKeychainAppKeyStore implements DVAppKeyStore {
  final String service;
  final String account;

  const DVKeychainAppKeyStore({required this.service, required this.account});

  static bool get isAvailable => Platform.isMacOS || Platform.isIOS;

  /// The value of `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, as the
  /// Keychain reports it back in an item's attributes.
  static const String accessibleAfterFirstUnlockThisDeviceOnly = 'cku';

  static DynamicLibrary? _cfLib;
  static DynamicLibrary? _securityLib;

  /// A system framework by path, or the process when the path does not open.
  ///
  /// The path is how macOS is reached, and how the other iOS bindings reach
  /// their frameworks. On iOS the framework is already mapped into every
  /// application that links Foundation, so the process image answers for its
  /// symbols when a path lookup is refused.
  static DynamicLibrary _framework(String name) {
    try {
      return DynamicLibrary.open('/System/Library/Frameworks/$name.framework/$name');
    } on ArgumentError {
      if (Platform.isIOS) return DynamicLibrary.process();
      rethrow;
    }
  }

  static DynamicLibrary get _cf => _cfLib ??= _framework('CoreFoundation');
  static DynamicLibrary get _security => _securityLib ??= _framework('Security');

  /// Both frameworks, or the refusal that says they are not here.
  static void _require() {
    if (!isAvailable) {
      throw const DVAppKeyStoreUnavailable(
          'the Keychain', 'there is no Keychain on this platform');
    }
    try {
      _cf;
      _security;
    } on Object catch (error) {
      throw DVAppKeyStoreUnavailable(
          'the Keychain', 'the Security framework could not be loaded',
          cause: error);
    }
  }

  static Pointer<Void> _constant(DynamicLibrary lib, String name) =>
      lib.lookup<Pointer<Void>>(name).value;

  static Pointer<Void> _string(String text) {
    final Pointer<Utf8> c = text.toNativeUtf8();
    try {
      return _cf.lookupFunction<_CFStringCreateN, _CFStringCreateD>('CFStringCreateWithCString')(
          nullptr, c, _kCFStringEncodingUTF8);
    } finally {
      calloc.free(c);
    }
  }

  static String? _dartString(Pointer<Void> cfString) {
    if (cfString == nullptr) return null;
    final Pointer<Utf8> buffer = calloc<Uint8>(256).cast<Utf8>();
    try {
      final int ok = _cf.lookupFunction<_CFStringGetCStringN, _CFStringGetCStringD>('CFStringGetCString')(
          cfString, buffer, 256, _kCFStringEncodingUTF8);
      return ok == 0 ? null : buffer.toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  static void _release(Pointer<Void> object) {
    if (object != nullptr) _cf.lookupFunction<_CFReleaseN, _CFReleaseD>('CFRelease')(object);
  }

  /// A CFDictionary over [entries]; the caller releases it and the values.
  static Pointer<Void> _dictionary(Map<Pointer<Void>, Pointer<Void>> entries) {
    final int n = entries.length;
    final Pointer<Pointer<Void>> keys = calloc<Pointer<Void>>(n);
    final Pointer<Pointer<Void>> values = calloc<Pointer<Void>>(n);
    int i = 0;
    for (final MapEntry<Pointer<Void>, Pointer<Void>> e in entries.entries) {
      keys[i] = e.key;
      values[i] = e.value;
      i++;
    }
    try {
      return _cf.lookupFunction<_CFDictCreateN, _CFDictCreateD>('CFDictionaryCreate')(
        nullptr,
        keys,
        values,
        n,
        _cf.lookup<Void>('kCFTypeDictionaryKeyCallBacks'),
        _cf.lookup<Void>('kCFTypeDictionaryValueCallBacks'),
      );
    } finally {
      calloc.free(keys);
      calloc.free(values);
    }
  }

  Map<Pointer<Void>, Pointer<Void>> _identity(List<Pointer<Void>> owned) {
    final Pointer<Void> svc = _string(service);
    final Pointer<Void> acct = _string(account);
    owned.addAll(<Pointer<Void>>[svc, acct]);
    return <Pointer<Void>, Pointer<Void>>{
      _constant(_security, 'kSecClass'): _constant(_security, 'kSecClassGenericPassword'),
      _constant(_security, 'kSecAttrService'): svc,
      _constant(_security, 'kSecAttrAccount'): acct,
    };
  }

  /// Where the item may be read and where it may travel.
  static Map<Pointer<Void>, Pointer<Void>> _protection() => <Pointer<Void>, Pointer<Void>>{
        _constant(_security, 'kSecAttrAccessible'):
            _constant(_security, 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly'),
        _constant(_security, 'kSecAttrSynchronizable'): _constant(_cf, 'kCFBooleanFalse'),
      };

  /// The item's matching result for [returning], or null when there is none.
  /// The caller releases what comes back.
  Pointer<Void> _copy(String returning) {
    final List<Pointer<Void>> owned = <Pointer<Void>>[];
    final Pointer<Void> query = _dictionary(<Pointer<Void>, Pointer<Void>>{
      ..._identity(owned),
      _constant(_security, returning): _constant(_cf, 'kCFBooleanTrue'),
      _constant(_security, 'kSecMatchLimit'): _constant(_security, 'kSecMatchLimitOne'),
    });
    final Pointer<Pointer<Void>> result = calloc<Pointer<Void>>();
    try {
      final int status =
          _security.lookupFunction<_SecItemCopyN, _SecItemCopyD>('SecItemCopyMatching')(query, result);
      if (status == _errSecItemNotFound) return nullptr;
      if (status != 0) throw dvKeychainRefusal(status, 'SecItemCopyMatching');
      return result.value;
    } finally {
      calloc.free(result);
      _release(query);
      owned.forEach(_release);
    }
  }

  @override
  Future<Uint8List?> read() async {
    _require();
    final Pointer<Void> data = _copy('kSecReturnData');
    if (data == nullptr) return null;
    final int length = _cf.lookupFunction<_CFDataLenN, _CFDataLenD>('CFDataGetLength')(data);
    final Pointer<Uint8> bytes = _cf.lookupFunction<_CFDataPtrN, _CFDataPtrD>('CFDataGetBytePtr')(data);
    final Uint8List out = Uint8List.fromList(bytes.asTypedList(length));
    _release(data);
    try {
      final Uint8List key = base64Decode(utf8.decode(out));
      return key.length == DVAppKey.lengthBytes ? key : null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    _require();
    final List<Pointer<Void>> owned = <Pointer<Void>>[];
    final List<int> encoded = utf8.encode(base64Encode(key));
    final Pointer<Uint8> raw = calloc<Uint8>(encoded.length);
    raw.asTypedList(encoded.length).setAll(0, encoded);
    final Pointer<Void> data =
        _cf.lookupFunction<_CFDataCreateN, _CFDataCreateD>('CFDataCreate')(nullptr, raw, encoded.length);
    calloc.free(raw);
    owned.add(data);
    final Pointer<Void> item = _dictionary(<Pointer<Void>, Pointer<Void>>{
      ..._identity(owned),
      ..._protection(),
      _constant(_security, 'kSecValueData'): data,
    });
    Pointer<Void> query = nullptr;
    Pointer<Void> changes = nullptr;
    try {
      final int added = _security.lookupFunction<_SecItemAddN, _SecItemAddD>('SecItemAdd')(item, nullptr);
      if (added == 0) return;
      if (added != _errSecDuplicateItem) throw dvKeychainRefusal(added, 'SecItemAdd');
      // Updated in place rather than deleted and added again: a delete that
      // succeeds before an add that is refused -- a device locked between the
      // two -- would leave no key at all.
      query = _dictionary(_identity(owned));
      changes = _dictionary(<Pointer<Void>, Pointer<Void>>{
        ..._protection(),
        _constant(_security, 'kSecValueData'): data,
      });
      final int updated =
          _security.lookupFunction<_SecItemUpdateN, _SecItemUpdateD>('SecItemUpdate')(query, changes);
      if (updated != 0) throw dvKeychainRefusal(updated, 'SecItemUpdate');
    } finally {
      _release(item);
      _release(query);
      _release(changes);
      owned.forEach(_release);
    }
  }

  @override
  Future<void> clear() async {
    _require();
    final List<Pointer<Void>> owned = <Pointer<Void>>[];
    final Pointer<Void> query = _dictionary(_identity(owned));
    try {
      final int status = _security.lookupFunction<_SecItemDeleteN, _SecItemDeleteD>('SecItemDelete')(query);
      if (status != 0 && status != _errSecItemNotFound) {
        throw dvKeychainRefusal(status, 'SecItemDelete');
      }
    } finally {
      _release(query);
      owned.forEach(_release);
    }
  }

  /// What the Keychain says about the stored item: its accessibility class
  /// (`accessible`, e.g. [accessibleAfterFirstUnlockThisDeviceOnly]) and
  /// whether it synchronizes (`synchronizable`). Null when there is no item.
  ///
  /// For tests, which have to ask the Keychain rather than trust what was
  /// passed to it: an attribute a platform ignores is still accepted.
  Future<Map<String, Object?>?> debugItemAttributes() async {
    _require();
    final Pointer<Void> attributes = _copy('kSecReturnAttributes');
    if (attributes == nullptr) return null;
    try {
      final _CFDictGetValueD get =
          _cf.lookupFunction<_CFDictGetValueN, _CFDictGetValueD>('CFDictionaryGetValue');
      final Pointer<Void> accessible = get(attributes, _constant(_security, 'kSecAttrAccessible'));
      final Pointer<Void> sync = get(attributes, _constant(_security, 'kSecAttrSynchronizable'));
      return <String, Object?>{
        'accessible': _dartString(accessible),
        'synchronizable': _truth(sync),
      };
    } finally {
      _release(attributes);
    }
  }

  /// A CFBoolean or CFNumber as a bool; null when absent or neither.
  static bool? _truth(Pointer<Void> value) {
    if (value == nullptr) return null;
    final int type = _cf.lookupFunction<_CFTypeIdN, _CFTypeIdD>('CFGetTypeID')(value);
    if (type == _cf.lookupFunction<_CFTypeIdOfN, _CFTypeIdOfD>('CFBooleanGetTypeID')()) {
      return _cf.lookupFunction<_CFBooleanGetValueN, _CFBooleanGetValueD>('CFBooleanGetValue')(value) != 0;
    }
    if (type == _cf.lookupFunction<_CFTypeIdOfN, _CFTypeIdOfD>('CFNumberGetTypeID')()) {
      final Pointer<Int64> out = calloc<Int64>();
      try {
        _cf.lookupFunction<_CFNumberGetValueN, _CFNumberGetValueD>('CFNumberGetValue')(
            value, _kCFNumberSInt64Type, out);
        return out.value != 0;
      } finally {
        calloc.free(out);
      }
    }
    return null;
  }
}
