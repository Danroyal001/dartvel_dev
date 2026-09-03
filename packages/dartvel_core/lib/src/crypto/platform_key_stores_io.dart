import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'app_key.dart';

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

// --- macOS: the Keychain -------------------------------------------------------
//
// One generic-password item per service and account, through the Security
// framework's SecItem API with CoreFoundation dictionaries built by hand.

typedef _CFStringCreateN = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _CFStringCreateD = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _CFDataCreateN = Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, IntPtr);
typedef _CFDataCreateD = Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>, int);
typedef _CFDictCreateN = Pointer<Void> Function(
    Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Pointer<Void>>, IntPtr, Pointer<Void>, Pointer<Void>);
typedef _CFDictCreateD = Pointer<Void> Function(
    Pointer<Void>, Pointer<Pointer<Void>>, Pointer<Pointer<Void>>, int, Pointer<Void>, Pointer<Void>);
typedef _CFReleaseN = Void Function(Pointer<Void>);
typedef _CFReleaseD = void Function(Pointer<Void>);
typedef _CFDataLenN = IntPtr Function(Pointer<Void>);
typedef _CFDataLenD = int Function(Pointer<Void>);
typedef _CFDataPtrN = Pointer<Uint8> Function(Pointer<Void>);
typedef _CFDataPtrD = Pointer<Uint8> Function(Pointer<Void>);
typedef _SecItemAddN = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecItemAddD = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecItemCopyN = Int32 Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecItemCopyD = int Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _SecItemDeleteN = Int32 Function(Pointer<Void>);
typedef _SecItemDeleteD = int Function(Pointer<Void>);

const int _kCFStringEncodingUTF8 = 0x08000100;
const int _errSecItemNotFound = -25300;
const int _errSecDuplicateItem = -25299;

class DVKeychainAppKeyStore implements DVAppKeyStore {
  final String service;
  final String account;

  const DVKeychainAppKeyStore({required this.service, required this.account});

  static bool get isAvailable => Platform.isMacOS;

  static DynamicLibrary get _cf =>
      DynamicLibrary.open('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation');
  static DynamicLibrary get _security =>
      DynamicLibrary.open('/System/Library/Frameworks/Security.framework/Security');

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

  @override
  Future<Uint8List?> read() async {
    final List<Pointer<Void>> owned = <Pointer<Void>>[];
    final Pointer<Void> query = _dictionary(<Pointer<Void>, Pointer<Void>>{
      ..._identity(owned),
      _constant(_security, 'kSecReturnData'): _constant(_cf, 'kCFBooleanTrue'),
      _constant(_security, 'kSecMatchLimit'): _constant(_security, 'kSecMatchLimitOne'),
    });
    final Pointer<Pointer<Void>> result = calloc<Pointer<Void>>();
    try {
      final int status =
          _security.lookupFunction<_SecItemCopyN, _SecItemCopyD>('SecItemCopyMatching')(query, result);
      if (status == _errSecItemNotFound) return null;
      if (status != 0) throw StateError('SecItemCopyMatching failed ($status).');
      final Pointer<Void> data = result.value;
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
    } finally {
      calloc.free(result);
      _release(query);
      owned.forEach(_release);
    }
  }

  @override
  Future<void> write(Uint8List key) async {
    // Replace rather than update: SecItemUpdate needs a second dictionary and
    // the same care, and a key is written a handful of times in its life.
    await clear();
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
      _constant(_security, 'kSecValueData'): data,
    });
    try {
      final int status = _security.lookupFunction<_SecItemAddN, _SecItemAddD>('SecItemAdd')(item, nullptr);
      if (status != 0 && status != _errSecDuplicateItem) {
        throw StateError('SecItemAdd failed ($status).');
      }
    } finally {
      _release(item);
      owned.forEach(_release);
    }
  }

  @override
  Future<void> clear() async {
    final List<Pointer<Void>> owned = <Pointer<Void>>[];
    final Pointer<Void> query = _dictionary(_identity(owned));
    try {
      final int status = _security.lookupFunction<_SecItemDeleteN, _SecItemDeleteD>('SecItemDelete')(query);
      if (status != 0 && status != _errSecItemNotFound) {
        throw StateError('SecItemDelete failed ($status).');
      }
    } finally {
      _release(query);
      owned.forEach(_release);
    }
  }
}
