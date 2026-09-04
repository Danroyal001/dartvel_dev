/// File associations on macOS: LaunchServices, at run time.
///
/// A macOS application declares what it opens in its bundle's Info.plist,
/// which the build writes. LaunchServices only learns about it when the
/// bundle is registered -- normally by the installer, or by the system
/// noticing a new application in /Applications. An application copied into
/// place, or one that gained a file type after it shipped, is not registered
/// and opens nothing: double-clicking its own document offers a list of
/// other applications.
///
/// So this registers the running bundle with LaunchServices and asks to be
/// the default for the types it declares. Both are per-user; there is no
/// machine-wide equivalent, which is what macOS wants.
///
/// The one asymmetry is deliberate and stated: LaunchServices has no public
/// call to stop being the default for a type. Unregistering hands the
/// default back to whoever held it before this process took it, which is the
/// only honest undo available -- and it says so when it cannot.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _CFStringCreateN = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Uint32);
typedef _CFStringCreateD = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _CFStringGetCStringN = Bool Function(Pointer<Void>, Pointer<Utf8>, IntPtr, Uint32);
typedef _CFStringGetCStringD = bool Function(Pointer<Void>, Pointer<Utf8>, int, int);
typedef _CFReleaseN = Void Function(Pointer<Void>);
typedef _CFReleaseD = void Function(Pointer<Void>);
typedef _CFBundleGetMainN = Pointer<Void> Function();
typedef _CFBundleGetMainD = Pointer<Void> Function();
typedef _CFBundleGetIdentifierN = Pointer<Void> Function(Pointer<Void>);
typedef _CFBundleGetIdentifierD = Pointer<Void> Function(Pointer<Void>);
typedef _CFBundleCopyUrlN = Pointer<Void> Function(Pointer<Void>);
typedef _CFBundleCopyUrlD = Pointer<Void> Function(Pointer<Void>);

typedef _UtiForTagN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _UtiForTagD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _CopyHandlerN = Pointer<Void> Function(Pointer<Void>, Uint32);
typedef _CopyHandlerD = Pointer<Void> Function(Pointer<Void>, int);
typedef _SetHandlerN = Int32 Function(Pointer<Void>, Uint32, Pointer<Void>);
typedef _SetHandlerD = int Function(Pointer<Void>, int, Pointer<Void>);
typedef _CopySchemeHandlerN = Pointer<Void> Function(Pointer<Void>);
typedef _CopySchemeHandlerD = Pointer<Void> Function(Pointer<Void>);
typedef _SetSchemeHandlerN = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _SetSchemeHandlerD = int Function(Pointer<Void>, Pointer<Void>);
typedef _RegisterUrlN = Int32 Function(Pointer<Void>, Bool);
typedef _RegisterUrlD = int Function(Pointer<Void>, bool);

const int _utf8 = 0x08000100;

/// `kLSRolesAll`: viewer, editor and shell alike. A design that asked only
/// to view its own documents would open them read-only.
const int _rolesAll = 0xFFFFFFFF;

/// `kUTTagClassFilenameExtension`, written out rather than looked up: it is a
/// CFStringRef constant whose value is this string, and creating it here is
/// one symbol fewer to resolve.
const String _extensionTagClass = 'public.filename-extension';

class DVMacosAssociations {
  const DVMacosAssociations._();

  static DynamicLibrary? _cf;
  static DynamicLibrary? _services;

  static const Set<String> implemented = <String>{
    'associations.register',
    'associations.unregister',
    'associations.handlerFor',
  };

  /// Why the last register did not take. Null when it did.
  static String? lastError;

  /// What held each type before this process took it, so unregistering can
  /// hand it back. In memory only: LaunchServices keeps no history, and a
  /// note written to disk would be a second source of truth about something
  /// the system already owns.
  static final Map<String, String> _displaced = <String, String>{};

  static void register(
    void Function(String, Object? Function(Object?)) bind, {
    required DynamicLibrary coreFoundation,
    required DynamicLibrary services,
  }) {
    _cf = coreFoundation;
    _services = services;
    bind('associations.register', (Object? arguments) => _apply(arguments, add: true));
    bind('associations.unregister', (Object? arguments) => _apply(arguments, add: false));
    bind('associations.handlerFor', (Object? arguments) {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      return handlerFor('${map['extension'] ?? ''}');
    });
  }

  /// The bundle identifier of the running application, or null when this
  /// process is not one -- a test harness, a command-line tool.
  static String? get bundleIdentifier {
    final DynamicLibrary? cf = _cf;
    if (cf == null) return null;
    final Pointer<Void> bundle =
        cf.lookupFunction<_CFBundleGetMainN, _CFBundleGetMainD>('CFBundleGetMainBundle')();
    if (bundle == nullptr) return null;
    final Pointer<Void> identifier = cf
        .lookupFunction<_CFBundleGetIdentifierN, _CFBundleGetIdentifierD>(
            'CFBundleGetIdentifier')(bundle);
    // Not released: CFBundleGetIdentifier follows the Get rule and hands
    // back a reference this code does not own.
    return identifier == nullptr ? null : _dartString(identifier);
  }

  /// Which application opens [extension] now, by bundle identifier.
  static String? handlerFor(String extension) {
    if (extension.isEmpty || _cf == null || _services == null) return null;
    final Pointer<Void> uti = _utiFor(extension);
    if (uti == nullptr) return null;
    try {
      final Pointer<Void> handler = _services!
          .lookupFunction<_CopyHandlerN, _CopyHandlerD>(
              'LSCopyDefaultRoleHandlerForContentType')(uti, _rolesAll);
      if (handler == nullptr) return null;
      try {
        final String value = _dartString(handler);
        return value.isEmpty ? null : value;
      } finally {
        _release(handler);
      }
    } finally {
      _release(uti);
    }
  }

  static bool _apply(Object? arguments, {required bool add}) {
    lastError = null;
    if (_cf == null || _services == null) return false;
    final String? identifier = bundleIdentifier;
    if (identifier == null) {
      // Said rather than swallowed: LaunchServices identifies an application
      // by its bundle, and a process without one has nothing to register.
      // Reporting success here would be an application that believes it
      // opens its own documents and does not.
      lastError = 'This process is not an application bundle, so '
          'LaunchServices has no application to register. Build the app '
          'bundle and run it from there.';
      return false;
    }

    final Map<Object?, Object?> map =
        arguments is Map ? arguments : const <Object?, Object?>{};
    final List<Object?> types =
        map['types'] is List ? map['types']! as List<Object?> : const <Object?>[];
    final List<Object?> schemes =
        map['schemes'] is List ? map['schemes']! as List<Object?> : const <Object?>[];

    // The bundle first: its Info.plist is what declares the types, and
    // LaunchServices does not know about a bundle nobody installed.
    if (add) _registerBundle();

    bool ok = true;
    for (final Object? raw in types) {
      if (raw is! Map) continue;
      final List<Object?> extensions =
          raw['extensions'] is List ? raw['extensions']! as List<Object?> : const <Object?>[];
      for (final Object? extension in extensions) {
        ok = _setHandler('$extension', identifier, add: add) && ok;
      }
    }
    for (final Object? raw in schemes) {
      ok = _setScheme('$raw', identifier, add: add) && ok;
    }
    return ok;
  }

  static bool _setHandler(String extension, String identifier, {required bool add}) {
    final Pointer<Void> uti = _utiFor(extension);
    if (uti == nullptr) return false;
    try {
      final String? previous = handlerFor(extension);
      final String? wanted;
      if (add) {
        if (previous != null && previous != identifier) {
          _displaced[extension] = previous;
        }
        wanted = identifier;
      } else {
        // The only honest undo. LaunchServices has no call to stop being the
        // default for a type, so what can be done is hand it back to whoever
        // held it before -- and when nobody did, say so rather than pretend.
        wanted = _displaced.remove(extension);
        if (wanted == null) {
          lastError = 'macOS has no way to withdraw a default handler, and '
              'nothing else claimed .$extension before this application did. '
              'It stays the default until another application takes it.';
          return false;
        }
      }
      final Pointer<Void> handler = _cfString(wanted);
      try {
        return _services!.lookupFunction<_SetHandlerN, _SetHandlerD>(
                'LSSetDefaultRoleHandlerForContentType')(uti, _rolesAll, handler) ==
            0;
      } finally {
        _release(handler);
      }
    } finally {
      _release(uti);
    }
  }

  static bool _setScheme(String scheme, String identifier, {required bool add}) {
    if (scheme.isEmpty) return false;
    final Pointer<Void> name = _cfString(scheme);
    try {
      final String? wanted;
      if (add) {
        final Pointer<Void> current = _services!
            .lookupFunction<_CopySchemeHandlerN, _CopySchemeHandlerD>(
                'LSCopyDefaultHandlerForURLScheme')(name);
        if (current != nullptr) {
          final String held = _dartString(current);
          _release(current);
          if (held.isNotEmpty && held != identifier) {
            _displaced['scheme:$scheme'] = held;
          }
        }
        wanted = identifier;
      } else {
        wanted = _displaced.remove('scheme:$scheme');
        if (wanted == null) {
          lastError = 'macOS has no way to withdraw a URL scheme handler, and '
              'nothing else claimed $scheme: before this application did.';
          return false;
        }
      }
      final Pointer<Void> handler = _cfString(wanted);
      try {
        return _services!.lookupFunction<_SetSchemeHandlerN, _SetSchemeHandlerD>(
                'LSSetDefaultHandlerForURLScheme')(name, handler) ==
            0;
      } finally {
        _release(handler);
      }
    } finally {
      _release(name);
    }
  }

  /// Tells LaunchServices this bundle exists, and to re-read its Info.plist.
  ///
  /// The half an installer normally does. Without it a bundle that was
  /// copied into place declares its document types to nobody.
  static void _registerBundle() {
    final Pointer<Void> bundle =
        _cf!.lookupFunction<_CFBundleGetMainN, _CFBundleGetMainD>('CFBundleGetMainBundle')();
    if (bundle == nullptr) return;
    final Pointer<Void> url = _cf!
        .lookupFunction<_CFBundleCopyUrlN, _CFBundleCopyUrlD>('CFBundleCopyBundleURL')(bundle);
    if (url == nullptr) return;
    try {
      _services!.lookupFunction<_RegisterUrlN, _RegisterUrlD>('LSRegisterURL')(url, true);
    } finally {
      _release(url);
    }
  }

  /// The type identifier macOS knows [extension] by.
  ///
  /// A type nothing has declared gets a dynamic identifier, which is how
  /// macOS names an extension it has never seen: it works, and it is why a
  /// registration on its own is not the same as declaring the type in the
  /// bundle's Info.plist.
  static Pointer<Void> _utiFor(String extension) {
    final Pointer<Void> tagClass = _cfString(_extensionTagClass);
    final Pointer<Void> tag = _cfString(extension);
    try {
      return _services!.lookupFunction<_UtiForTagN, _UtiForTagD>(
          'UTTypeCreatePreferredIdentifierForTag')(tagClass, tag, nullptr);
    } finally {
      _release(tagClass);
      _release(tag);
    }
  }

  static Pointer<Void> _cfString(String value) {
    final Pointer<Utf8> utf8 = value.toNativeUtf8();
    try {
      return _cf!.lookupFunction<_CFStringCreateN, _CFStringCreateD>(
          'CFStringCreateWithCString')(nullptr, utf8, _utf8);
    } finally {
      calloc.free(utf8);
    }
  }

  static String _dartString(Pointer<Void> value) {
    // A buffer rather than CFStringGetCStringPtr, which is allowed to answer
    // null for any string that is not already in the encoding asked for --
    // and does, often enough that reading it as the whole answer is a bug
    // that only shows up on somebody else's machine.
    const int room = 512;
    final Pointer<Utf8> buffer = calloc<Uint8>(room).cast<Utf8>();
    try {
      final bool got = _cf!.lookupFunction<_CFStringGetCStringN, _CFStringGetCStringD>(
          'CFStringGetCString')(value, buffer, room, _utf8);
      return got ? buffer.toDartString() : '';
    } finally {
      calloc.free(buffer);
    }
  }

  static void _release(Pointer<Void> value) {
    if (value == nullptr) return;
    _cf!.lookupFunction<_CFReleaseN, _CFReleaseD>('CFRelease')(value);
  }

  /// Test-only: forgets what was displaced, so one test's registration does
  /// not undo another's.
  static void reset() => _displaced.clear();
}
