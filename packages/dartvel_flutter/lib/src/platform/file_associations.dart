/// Telling the desktop what this application opens, while it is running.
///
/// The build writes the declaration -- a `.desktop` file and MIME info on
/// Linux, document types into the macOS plist, a registry script beside the
/// Windows binary -- and on Windows and macOS somebody still has to run an
/// installer for any of it to take effect. An application that was copied
/// into place, or that gained a file type after it shipped, opens nothing:
/// double-clicking its own document offers a list of other applications.
///
/// So the same declaration can be registered at run time, for the user who
/// is running the application. Per-user, always: registering for every user
/// on the machine needs administrator rights, and an API that asked for them
/// would be one most applications could not call.
library;

import 'package:dartvel_flutter/dartvel_flutter.dart';

/// One file type this application opens.
class DVFileType {
  const DVFileType({
    required this.mimeType,
    this.extensions = const <String>[],
    this.description,
  });

  /// The type's name, e.g. `application/x-shop-order`. On macOS this is the
  /// content type; on Windows it names the ProgId the extensions point at.
  final String mimeType;

  /// The extensions that are this type, without their dots.
  final List<String> extensions;

  /// What a file manager calls it.
  final String? description;

  Map<String, Object?> toJson() => <String, Object?>{
        'mimeType': mimeType,
        'extensions': <String>[
          for (final String extension in extensions) _bare(extension),
        ],
        if (description != null) 'description': description,
      };
}

/// An extension without its leading dot.
///
/// Windows registry keys are `.order` and Linux globs are `*.order`, so a
/// caller writes it either way and every binding is given the same thing.
String _bare(String extension) =>
    extension.startsWith('.') ? extension.substring(1) : extension;

/// Registering this application as the handler for its own file types.
class DVFileAssociations {
  const DVFileAssociations();

  /// Whether this platform can register at run time.
  ///
  /// For deciding what to offer, not for deciding whether to call: [register]
  /// throws where there is no binding rather than reporting a success
  /// nothing did.
  bool get supported => DVNativeBridge.isRegistered('associations.register');

  /// Registers [types], and any [schemes] the application answers, for the
  /// user running it.
  ///
  /// An empty list is refused rather than treated as a no-op, and so is a
  /// type with no extensions: every platform matches a file by its
  /// extension, so a type that names none names nothing.
  Future<bool> register(
    List<DVFileType> types, {
    List<String> schemes = const <String>[],
  }) =>
      DVNativeBridge.require<bool>(
          'associations.register', _arguments(types, schemes));

  /// Takes them back off, for the same user.
  Future<bool> unregister(
    List<DVFileType> types, {
    List<String> schemes = const <String>[],
  }) =>
      DVNativeBridge.require<bool>(
          'associations.unregister', _arguments(types, schemes));

  /// What a binding is given, once the declaration is known to be usable.
  ///
  /// The names are written out at each call site rather than passed in,
  /// because a binding name is a bare string on both sides and the check that
  /// every name is declared reads the source for them.
  Map<String, Object?> _arguments(
    List<DVFileType> types,
    List<String> schemes,
  ) {
    if (types.isEmpty && schemes.isEmpty) {
      throw ArgumentError.value(types, 'types',
          'Registering nothing is a mistake in the caller rather than a '
              'no-op: name at least one file type or URL scheme.');
    }
    for (final DVFileType type in types) {
      if (type.extensions.isEmpty) {
        throw ArgumentError.value(
            type.mimeType,
            'types',
            'Every platform matches a file by its extension, so a type with '
                'none can never be opened. Name the extensions this type '
                'uses.');
      }
    }
    return <String, Object?>{
      'types': <Object?>[for (final DVFileType type in types) type.toJson()],
      'schemes': schemes,
    };
  }

  /// Which application opens [extension] now, as the platform names it, or
  /// null when nothing does.
  ///
  /// A question rather than a promise: nothing opening `.order` yet is the
  /// normal state before registering.
  Future<String?> handlerFor(String extension) =>
      DVNativeBridge.invoke<String>('associations.handlerFor',
          <String, Object?>{'extension': _bare(extension)});
}
