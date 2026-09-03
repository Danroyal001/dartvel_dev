import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'app_key.dart';

// libsecret's password API, in the non-variadic "v" forms that take a
// GHashTable of attributes, so nothing here depends on C varargs.
typedef _StorevN = Int32 Function(Pointer<Void> schema, Pointer<Void> attributes,
    Pointer<Utf8> collection, Pointer<Utf8> label, Pointer<Utf8> password,
    Pointer<Void> cancellable, Pointer<Pointer<Void>> error);
typedef _StorevD = int Function(Pointer<Void>, Pointer<Void>, Pointer<Utf8>,
    Pointer<Utf8>, Pointer<Utf8>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _LookupvN = Pointer<Utf8> Function(Pointer<Void> schema,
    Pointer<Void> attributes, Pointer<Void> cancellable, Pointer<Pointer<Void>> error);
typedef _LookupvD = Pointer<Utf8> Function(
    Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _ClearvN = Int32 Function(Pointer<Void> schema, Pointer<Void> attributes,
    Pointer<Void> cancellable, Pointer<Pointer<Void>> error);
typedef _ClearvD = int Function(
    Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _PasswordFreeN = Void Function(Pointer<Utf8>);
typedef _PasswordFreeD = void Function(Pointer<Utf8>);
typedef _ServiceGetN = Pointer<Void> Function(
    Int32 flags, Pointer<Void> cancellable, Pointer<Pointer<Void>> error);
typedef _ServiceGetD = Pointer<Void> Function(int, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _ObjectUnrefN = Void Function(Pointer<Void>);
typedef _ObjectUnrefD = void Function(Pointer<Void>);
typedef _ErrorFreeN = Void Function(Pointer<Void>);
typedef _ErrorFreeD = void Function(Pointer<Void>);
typedef _HashNewN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _HashNewD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _HashInsertN = Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _HashInsertD = int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _HashUnrefN = Void Function(Pointer<Void>);
typedef _HashUnrefD = void Function(Pointer<Void>);

/// The application key in the Secret Service -- GNOME Keyring, KWallet's
/// bridge, or whatever else answers `org.freedesktop.secrets` on the session
/// bus -- through libsecret. Keyring-backed, so it is unlocked with the
/// user's login and other users never see it.
///
/// One item per `(service, account)`: the application's name and the
/// install it belongs to.
class DVSecretServiceAppKeyStore implements DVAppKeyStore {
  final String service;
  final String account;

  /// The keyring: null for the user's default, `session` for one that lives
  /// as long as the login does.
  final String? collection;

  const DVSecretServiceAppKeyStore({
    required this.service,
    required this.account,
    this.collection,
  });

  static DynamicLibrary? _secret;
  static DynamicLibrary? _glib;
  static DynamicLibrary? _gobject;

  static bool _load() {
    if (_secret != null) return true;
    if (!Platform.isLinux) return false;
    try {
      _secret = DynamicLibrary.open('libsecret-1.so.0');
      _glib = DynamicLibrary.open('libglib-2.0.so.0');
      _gobject = DynamicLibrary.open('libgobject-2.0.so.0');
      return true;
    } on ArgumentError {
      return false;
    }
  }

  /// Whether a Secret Service answers on this session bus. A boolean, never
  /// a throw: the store chooser has to be able to ask on any machine.
  static Future<bool> isAvailable() async {
    if (!_load()) return false;
    final Pointer<Pointer<Void>> error = calloc<Pointer<Void>>();
    try {
      final Pointer<Void> service = _secret!
          .lookupFunction<_ServiceGetN, _ServiceGetD>('secret_service_get_sync')(
              0, nullptr, error);
      if (service == nullptr) {
        _freeError(error);
        return false;
      }
      _gobject!.lookupFunction<_ObjectUnrefN, _ObjectUnrefD>('g_object_unref')(service);
      return true;
    } catch (_) {
      return false;
    } finally {
      calloc.free(error);
    }
  }

  static void _freeError(Pointer<Pointer<Void>> error) {
    if (error.value != nullptr) {
      _glib!.lookupFunction<_ErrorFreeN, _ErrorFreeD>('g_error_free')(error.value);
      error.value = nullptr;
    }
  }

  static String _errorMessage(Pointer<Pointer<Void>> error) {
    if (error.value == nullptr) return 'unknown error';
    // GError: GQuark domain @0, gint code @4, gchar* message @8.
    final Pointer<Utf8> message = error.value.cast<Uint8>().elementAt(8).cast<Pointer<Utf8>>().value;
    return message == nullptr ? 'unknown error' : message.toDartString();
  }

  /// A SecretSchema with two string attributes. Built once per call and
  /// freed after: the struct is small and the calls are rare.
  ///
  /// Layout: `const gchar *name` @0, `SecretSchemaFlags flags` @8, then
  /// `SecretSchemaAttribute attributes[32]` @16, each `{const gchar *name;
  /// SecretSchemaAttributeType type;}` at 16 bytes. Zeroed beyond that.
  Pointer<Void> _schema(Pointer<Utf8> name, Pointer<Utf8> attr1, Pointer<Utf8> attr2) {
    final Pointer<Uint8> raw = calloc<Uint8>(1024);
    raw.cast<Pointer<Utf8>>().value = name;
    raw.elementAt(8).cast<Int32>().value = 0; // SECRET_SCHEMA_NONE
    raw.elementAt(16).cast<Pointer<Utf8>>().value = attr1;
    raw.elementAt(24).cast<Int32>().value = 0; // SECRET_SCHEMA_ATTRIBUTE_STRING
    raw.elementAt(32).cast<Pointer<Utf8>>().value = attr2;
    raw.elementAt(40).cast<Int32>().value = 0;
    return raw.cast<Void>();
  }

  Future<T> _withAttributes<T>(
      T Function(Pointer<Void> schema, Pointer<Void> attributes, Pointer<Pointer<Void>> error) body) async {
    if (!_load()) throw StateError('libsecret is not available on this machine.');
    final Pointer<Utf8> schemaName = 'org.dartvel.AppKey'.toNativeUtf8();
    final Pointer<Utf8> serviceKey = 'service'.toNativeUtf8();
    final Pointer<Utf8> accountKey = 'account'.toNativeUtf8();
    final Pointer<Utf8> serviceValue = service.toNativeUtf8();
    final Pointer<Utf8> accountValue = account.toNativeUtf8();
    final Pointer<Void> schema = _schema(schemaName, serviceKey, accountKey);
    final Pointer<Void> table = _glib!.lookupFunction<_HashNewN, _HashNewD>('g_hash_table_new')(
      _glib!.lookup<NativeFunction<Void Function()>>('g_str_hash').cast<Void>(),
      _glib!.lookup<NativeFunction<Void Function()>>('g_str_equal').cast<Void>(),
    );
    final _HashInsertD insert = _glib!.lookupFunction<_HashInsertN, _HashInsertD>('g_hash_table_insert');
    insert(table, serviceKey.cast<Void>(), serviceValue.cast<Void>());
    insert(table, accountKey.cast<Void>(), accountValue.cast<Void>());
    final Pointer<Pointer<Void>> error = calloc<Pointer<Void>>();
    try {
      return body(schema, table, error);
    } finally {
      _freeError(error);
      calloc.free(error);
      _glib!.lookupFunction<_HashUnrefN, _HashUnrefD>('g_hash_table_unref')(table);
      calloc.free(schema);
      calloc.free(schemaName);
      calloc.free(serviceKey);
      calloc.free(accountKey);
      calloc.free(serviceValue);
      calloc.free(accountValue);
    }
  }

  @override
  Future<Uint8List?> read() => _withAttributes((Pointer<Void> schema, Pointer<Void> attributes, Pointer<Pointer<Void>> error) {
        final Pointer<Utf8> found = _secret!
            .lookupFunction<_LookupvN, _LookupvD>('secret_password_lookupv_sync')(schema, attributes, nullptr, error);
        if (error.value != nullptr) {
          throw StateError('Secret Service lookup failed: ${_errorMessage(error)}');
        }
        if (found == nullptr) return null;
        try {
          final Uint8List bytes = base64Decode(found.toDartString());
          return bytes.length == DVAppKey.lengthBytes ? bytes : null;
        } on FormatException {
          return null;
        } finally {
          _secret!.lookupFunction<_PasswordFreeN, _PasswordFreeD>('secret_password_free')(found);
        }
      });

  @override
  Future<void> write(Uint8List key) => _withAttributes((Pointer<Void> schema, Pointer<Void> attributes, Pointer<Pointer<Void>> error) {
        final Pointer<Utf8> label = 'Dartvel application key ($service)'.toNativeUtf8();
        final Pointer<Utf8> password = base64Encode(key).toNativeUtf8();
        final Pointer<Utf8> where = collection == null ? nullptr : collection!.toNativeUtf8();
        try {
          final int ok = _secret!.lookupFunction<_StorevN, _StorevD>('secret_password_storev_sync')(
              schema, attributes, where, label, password, nullptr, error);
          if (ok == 0) {
            throw StateError('Secret Service refused to store the key: ${_errorMessage(error)}');
          }
        } finally {
          calloc.free(label);
          calloc.free(password);
          if (where != nullptr) calloc.free(where);
        }
      });

  @override
  Future<void> clear() => _withAttributes((Pointer<Void> schema, Pointer<Void> attributes, Pointer<Pointer<Void>> error) {
        _secret!.lookupFunction<_ClearvN, _ClearvD>('secret_password_clearv_sync')(schema, attributes, nullptr, error);
        if (error.value != nullptr) {
          throw StateError('Secret Service could not clear the key: ${_errorMessage(error)}');
        }
      });
}
