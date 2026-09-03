import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// One editor mutation as data.
///
/// Every mutation [DVStudioEditorController] performs is also published as
/// one of these, and one can be applied to another controller. It is the
/// seam multi-user editing attaches through: a collaborator's controller
/// applies what this one published. The seam is free; what rides on it need
/// not be.
///
/// Undo and redo are `replace` edits carrying the whole document -- the
/// controller's own undo is a snapshot, and inverting an operation log is
/// how collaborative editors get subtly wrong.
class DVStudioEdit {
  /// `insert`, `move`, `update`, `remove` or `replace`.
  final String kind;

  /// The node acted on: the moved, updated or removed node's id. Null for
  /// insert (the node carries its own id) and replace.
  final String? id;

  /// Where an inserted or moved node goes.
  final String? parent;
  final int? index;

  /// The inserted node, or the updated node's new shape.
  final Map<String, Object?>? node;

  /// The whole document, for replace.
  final Map<String, Object?>? document;

  const DVStudioEdit._({
    required this.kind,
    this.id,
    this.parent,
    this.index,
    this.node,
    this.document,
  });

  factory DVStudioEdit.insert(DVPageNode node, {required String parent, int? index}) =>
      DVStudioEdit._(kind: 'insert', parent: parent, index: index, node: node.toJson());

  factory DVStudioEdit.move(String id, {required String parent, int? index}) =>
      DVStudioEdit._(kind: 'move', id: id, parent: parent, index: index);

  factory DVStudioEdit.update(String id, DVPageNode node) =>
      DVStudioEdit._(kind: 'update', id: id, node: node.toJson());

  factory DVStudioEdit.remove(String id) => DVStudioEdit._(kind: 'remove', id: id);

  factory DVStudioEdit.replace(DVPageDocument document) =>
      DVStudioEdit._(kind: 'replace', document: document.toJson());

  factory DVStudioEdit.fromJson(Map<String, Object?> json) => DVStudioEdit._(
        kind: json['kind']! as String,
        id: json['id'] as String?,
        parent: json['parent'] as String?,
        index: (json['index'] as num?)?.toInt(),
        node: (json['node'] as Map?)?.cast<String, Object?>(),
        document: (json['document'] as Map?)?.cast<String, Object?>(),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind,
        if (id != null) 'id': id,
        if (parent != null) 'parent': parent,
        if (index != null) 'index': index,
        if (node != null) 'node': node,
        if (document != null) 'document': document,
      };

  /// Performs this edit on [editor]. Throws [ArgumentError] when it cannot --
  /// a node that is not there, a drop into its own subtree -- leaving the
  /// document as it was.
  void applyTo(DVPageDocumentEditor editor) {
    switch (kind) {
      case 'insert':
        editor.insert(DVPageNode.fromJson(node!), parent: parent!, index: index);
      case 'move':
        editor.move(id!, parent: parent!, index: index);
      case 'update':
        final DVPageNode replacement = DVPageNode.fromJson(node!);
        editor.update(id!, (DVPageNode _) => replacement);
      case 'remove':
        editor.remove(id!);
      case 'replace':
        editor.document.root = DVPageDocument.fromJson(document!).root;
        editor.document.title = DVPageDocument.fromJson(document!).title;
      default:
        throw ArgumentError.value(kind, 'kind', 'Not an edit.');
    }
  }
}

/// Attaches to an editor when the Studio screen opens one; the returned
/// callback is called when that editor goes away.
///
/// ```dart
/// DVStudioScreen(editorHooks: <DVStudioEditorHook>[
///   (DVStudioEditorController controller) {
///     final sub = controller.edits.listen(publish);
///     return sub.cancel;
///   },
/// ])
/// ```
typedef DVStudioEditorHook = VoidCallback Function(
  DVStudioEditorController controller,
);
