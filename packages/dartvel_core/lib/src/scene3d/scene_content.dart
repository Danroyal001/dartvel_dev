/// Scene documents as content: stored, versioned and delivered like pages.
///
/// A `DV3DSceneDocument` is stored through the database, goes through the
/// same content workflow as a page document under its own kind, and reaches
/// an installed application as a bundle with the same rules as a page bundle:
/// applying a version twice is a no-op, and a rollback is the previous bundle
/// shipped again. That is what lets a signage fleet's scene change without an
/// application release.
library dartvel.scene3d.content;

import 'dart:async';
import 'dart:convert';

import '../../dartvel.dart' show DVAuthAuthorization, DVNotificationMessage;
import '../content/content_workflow.dart';
import '../database/adapter.dart';
import '../database/framework_tables.dart';
import 'scene_document.dart';

/// Published scene documents, by id.
final class DV3DSceneStore {
  DV3DSceneStore(this.database);

  static const String table = 'dartvel_scenes';

  final DVDatabaseAdapter database;
  final StreamController<String> _changes = StreamController<String>.broadcast();

  /// Ids whose stored document changed, as it changes, so a running viewport
  /// can pick up a publish.
  Stream<String> get changes => _changes.stream;

  Future<void> ensureSchema() async {
    await dvEnsureFrameworkTable(
      database,
      'CREATE TABLE IF NOT EXISTS $table (id TEXT, document TEXT)',
    );
  }

  /// Stores [document] under its id, replacing what was there.
  Future<void> save(DV3DSceneDocument document) async {
    await ensureSchema();
    await database.execute('DELETE FROM $table WHERE id = ?', <Object?>[document.id]);
    await database.execute(
      'INSERT INTO $table (id, document) VALUES (?, ?)',
      <Object?>[document.id, document.encode()],
    );
    _changes.add(document.id);
  }

  /// The stored document, or null. A stored document that no longer decodes
  /// throws rather than reading as absent: a scene that silently disappeared
  /// would look like a withdrawal nobody made.
  Future<DV3DSceneDocument?> load(String id) async {
    await ensureSchema();
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT document FROM $table WHERE id = ?',
      <Object?>[id],
    );
    if (rows.isEmpty) return null;
    return DV3DSceneDocument.decode(rows.first['document']! as String);
  }

  Future<List<String>> ids() async {
    await ensureSchema();
    final List<Map<String, Object?>> rows =
        await database.query('SELECT id FROM $table');
    return <String>[for (final Map<String, Object?> row in rows) row['id']! as String]
      ..sort();
  }

  Future<void> delete(String id) async {
    await ensureSchema();
    await database.execute('DELETE FROM $table WHERE id = ?', <Object?>[id]);
    _changes.add(id);
  }

  Future<void> close() => _changes.close();
}

/// A set of scene documents shipped together: the unit an OTA patch carries.
final class DV3DSceneBundle {
  const DV3DSceneBundle({
    required this.version,
    this.scenes = const <DV3DSceneDocument>[],
    this.removedScenes = const <String>[],
    this.approvals = const <String, DVContentApproval>{},
  });

  /// The release this bundle belongs to.
  final String version;
  final List<DV3DSceneDocument> scenes;

  /// Scene ids this bundle removes.
  final List<String> removedScenes;

  /// Which version of each scene was approved, by whom and when, by id.
  final Map<String, DVContentApproval> approvals;

  /// Throws [DV3DSceneFormatException] for a bundle that cannot be applied
  /// unambiguously.
  void validate() {
    if (version.isEmpty) {
      throw const DV3DSceneFormatException('version',
          'a bundle needs a non-empty version so it can be identified and rolled back');
    }
    final Set<String> shipped = <String>{};
    for (int i = 0; i < scenes.length; i++) {
      if (!shipped.add(scenes[i].id)) {
        throw DV3DSceneFormatException(
            'scenes[$i].id', "'${scenes[i].id}' is shipped twice in one bundle");
      }
    }
    for (int i = 0; i < removedScenes.length; i++) {
      if (shipped.contains(removedScenes[i])) {
        throw DV3DSceneFormatException('removedScenes[$i]',
            "'${removedScenes[i]}' is both shipped and removed by one bundle");
      }
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'scenes': <Object?>[for (final DV3DSceneDocument s in scenes) s.toJson()],
        if (removedScenes.isNotEmpty) 'removedScenes': removedScenes,
        if (approvals.isNotEmpty)
          'approvals': <String, Object?>{
            for (final String id in approvals.keys.toList()..sort())
              id: approvals[id]!.toJson(),
          },
      };

  String encode() => jsonEncode(toJson());

  static DV3DSceneBundle decode(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (error) {
      throw DV3DSceneFormatException(r'$', 'not JSON: ${error.message}');
    }
    return DV3DSceneBundle.fromJson(json);
  }

  /// Reads a bundle, decoding every scene before returning, so a bundle with
  /// one malformed scene is refused whole and nothing of it is applied.
  factory DV3DSceneBundle.fromJson(Object? json) {
    if (json is! Map) {
      throw const DV3DSceneFormatException(r'$', 'a bundle must be an object');
    }
    final Object? version = json['version'];
    if (version is! String) {
      throw const DV3DSceneFormatException('version', 'must be a string');
    }
    final Object? rawScenes = json['scenes'] ?? const <Object?>[];
    final Object? rawRemoved = json['removedScenes'] ?? const <Object?>[];
    final Object? rawApprovals = json['approvals'] ?? const <String, Object?>{};
    if (rawScenes is! List || rawRemoved is! List || rawApprovals is! Map) {
      throw const DV3DSceneFormatException(r'$',
          'scenes and removedScenes must be lists and approvals an object');
    }
    final DV3DSceneBundle bundle = DV3DSceneBundle(
      version: version,
      scenes: <DV3DSceneDocument>[
        for (int i = 0; i < rawScenes.length; i++)
          (() {
            try {
              return DV3DSceneDocument.fromJson(rawScenes[i]);
            } on DV3DSceneFormatException catch (error) {
              throw DV3DSceneFormatException('scenes[$i].${error.path}', error.message);
            }
          })(),
      ],
      removedScenes: <String>[
        for (int i = 0; i < rawRemoved.length; i++)
          if (rawRemoved[i] is String)
            rawRemoved[i] as String
          else
            throw DV3DSceneFormatException('removedScenes[$i]', 'must be a string'),
      ],
      approvals: <String, DVContentApproval>{
        for (final MapEntry<Object?, Object?> e in rawApprovals.entries)
          e.key! as String: DVContentApproval.fromJson(
              (e.value! as Map).cast<String, Object?>()),
      },
    );
    bundle.validate();
    return bundle;
  }
}

/// Applies scene bundles delivered with a release or OTA patch.
final class DV3DSceneBundleInstaller {
  DV3DSceneBundleInstaller(this.store);

  static const String table = 'dartvel_scene_bundles';

  final DV3DSceneStore store;

  Future<void> _ensureSchema() async {
    await dvEnsureFrameworkTable(
      store.database,
      'CREATE TABLE IF NOT EXISTS $table (version TEXT, applied_at TEXT, seq INTEGER)',
    );
  }

  Future<List<({String version, num seq})>> _rows() async {
    await _ensureSchema();
    final List<Map<String, Object?>> rows =
        await store.database.query('SELECT version, seq FROM $table');
    return <({String version, num seq})>[
      for (final Map<String, Object?> row in rows)
        (version: row['version']! as String, seq: num.parse(row['seq'].toString())),
    ]..sort((a, b) => a.seq.compareTo(b.seq));
  }

  /// Versions applied, oldest first -- ordered by a counter rather than a
  /// timestamp, which two applies in one millisecond would tie.
  Future<List<String>> appliedVersions() async => <String>[
        for (final ({String version, num seq}) row in await _rows()) row.version,
      ];

  Future<bool> isApplied(String version) async =>
      (await appliedVersions()).contains(version);

  /// Writes [bundle]'s scenes, removes the scenes it names and records its
  /// version. Idempotent: a version already applied writes nothing, because a
  /// patch delivered twice must not undo edits made since. Returns whether
  /// anything was written.
  Future<bool> apply(DV3DSceneBundle bundle) async {
    bundle.validate();
    final List<({String version, num seq})> rows = await _rows();
    if (rows.any((({String version, num seq}) r) => r.version == bundle.version)) {
      return false;
    }
    for (final DV3DSceneDocument scene in bundle.scenes) {
      await store.save(scene);
    }
    for (final String id in bundle.removedScenes) {
      await store.delete(id);
    }
    final num next = rows.isEmpty ? 1 : rows.last.seq + 1;
    await store.database.execute(
      'INSERT INTO $table (version, applied_at, seq) VALUES (?, ?, ?)',
      <Object?>[bundle.version, DateTime.now().toUtc().toIso8601String(), next],
    );
    return true;
  }

  /// Forgets that [version] was applied, so shipping it again applies it.
  /// This does not restore anything by itself: a rollback ships the previous
  /// bundle, which is the only way to be sure what a device ends up with.
  Future<void> forget(String version) async {
    await _ensureSchema();
    await store.database.execute(
      'DELETE FROM $table WHERE version = ?',
      <Object?>[version],
    );
  }
}

/// The content workflow for scene documents, wired to a [DV3DSceneStore].
///
/// Policies register against `DV3DSceneDocument` for the `DVContentAction`s.
/// Only a published version reaches the store; a withdrawal removes it.
final class DV3DSceneContent {
  DV3DSceneContent._(this.store, this.workflow);

  factory DV3DSceneContent({
    required String Function(Object? user) actorId,
    required DVDatabaseAdapter database,
    Future<Object?> Function(String actorId)? findActor,
    List<int>? previewKey,
    DVAuthAuthorization authorization = const DVAuthAuthorization(),
    Future<void> Function(String recipient, DVNotificationMessage message)? notify,
    bool requireApproval = true,
    Duration missedAfter = const Duration(minutes: 5),
    DateTime Function()? clock,
    DV3DSceneStore? store,
  }) {
    final DV3DSceneStore target = store ?? DV3DSceneStore(database);
    return DV3DSceneContent._(
      target,
      DVContentWorkflow<DV3DSceneDocument>(
        kind: kind,
        encode: (DV3DSceneDocument document) => document.toJson(),
        decode: DV3DSceneDocument.fromJson,
        documentId: (DV3DSceneDocument document) => document.id,
        actorId: actorId,
        findActor: findActor,
        previewKey: previewKey,
        database: database,
        authorization: authorization,
        notify: notify,
        requireApproval: requireApproval,
        missedAfter: missedAfter,
        clock: clock,
        // After commit: nothing reads a scene the workflow has not published.
        onPublished: (DVContentVersion<DV3DSceneDocument> version) =>
            target.save(version.document),
        onWithdrawn: (DVContentVersion<DV3DSceneDocument> version) =>
            target.delete(version.documentId),
      ),
    );
  }

  /// The document kind scene versions are stored under.
  static const String kind = 'scene';

  final DV3DSceneStore store;
  final DVContentWorkflow<DV3DSceneDocument> workflow;

  Future<void> ensureSchema() async {
    await workflow.ensureSchema();
    await store.ensureSchema();
  }

  /// A bundle of every published scene, in id order, with the approval each
  /// was published under.
  Future<DV3DSceneBundle> bundle({required String version}) async {
    final List<DVContentVersion<DV3DSceneDocument>> published =
        (await workflow.publicVersions())
          ..sort((DVContentVersion<DV3DSceneDocument> a,
                  DVContentVersion<DV3DSceneDocument> b) =>
              a.documentId.compareTo(b.documentId));
    return DV3DSceneBundle(
      version: version,
      scenes: <DV3DSceneDocument>[
        for (final DVContentVersion<DV3DSceneDocument> v in published) v.document,
      ],
      approvals: <String, DVContentApproval>{
        for (final DVContentVersion<DV3DSceneDocument> v in published)
          if (v.approval != null) v.documentId: v.approval!,
      },
    );
  }
}
