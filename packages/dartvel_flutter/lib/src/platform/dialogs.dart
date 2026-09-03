// System dialogs: the platform's own file chooser and message box.
//
// `openFile` and friends resolve when the dialog closes; cancel is an empty
// or null answer, not an error. Everything goes through the `dialogs.*`
// bindings and fails naming the binding where there is none.
import '../../dartvel_flutter.dart' show DVNativeBridge;

/// A file-type filter the chooser offers: `Text (*.txt)`.
class DVFileFilter {
  final String label;
  final List<String> extensions;

  const DVFileFilter({required this.label, required this.extensions});

  Map<String, Object?> toMap() => <String, Object?>{'label': label, 'extensions': extensions};
}

enum DVDialogKind { info, warning, error, question }

class DVDialogs {
  const DVDialogs();

  /// Paths the user picked; empty if they cancelled.
  Future<List<String>> openFile({
    String? title,
    List<DVFileFilter> filters = const <DVFileFilter>[],
    bool multiple = false,
    String? initialDirectory,
  }) async {
    final Object? result = await DVNativeBridge.require<Object?>('dialogs.openFile', <String, Object?>{
      if (title != null) 'title': title,
      'filters': <Map<String, Object?>>[for (final DVFileFilter f in filters) f.toMap()],
      'multiple': multiple,
      if (initialDirectory != null) 'initialDirectory': initialDirectory,
    });
    if (result is Map && result['paths'] is List) {
      return <String>[for (final Object? p in result['paths']! as List) '$p'];
    }
    return const <String>[];
  }

  /// The path to save to; null if the user cancelled.
  Future<String?> saveFile({
    String? title,
    String? suggestedName,
    List<DVFileFilter> filters = const <DVFileFilter>[],
    String? initialDirectory,
  }) async {
    final Object? result = await DVNativeBridge.require<Object?>('dialogs.saveFile', <String, Object?>{
      if (title != null) 'title': title,
      if (suggestedName != null) 'suggestedName': suggestedName,
      'filters': <Map<String, Object?>>[for (final DVFileFilter f in filters) f.toMap()],
      if (initialDirectory != null) 'initialDirectory': initialDirectory,
    });
    return result is Map ? result['path'] as String? : null;
  }

  /// The directory chosen; null if the user cancelled.
  Future<String?> chooseDirectory({String? title, String? initialDirectory}) async {
    final Object? result = await DVNativeBridge.require<Object?>('dialogs.chooseDirectory', <String, Object?>{
      if (title != null) 'title': title,
      if (initialDirectory != null) 'initialDirectory': initialDirectory,
    });
    return result is Map ? result['path'] as String? : null;
  }

  /// Shows a message and resolves when it is dismissed.
  Future<void> message({
    required String text,
    String? title,
    DVDialogKind kind = DVDialogKind.info,
  }) async {
    await DVNativeBridge.require<Object?>('dialogs.message', <String, Object?>{
      'text': text,
      if (title != null) 'title': title,
      'kind': kind.name,
    });
  }
}
