/// What a branch's preview environment and each of its resources is called.
///
/// Every name carries a digest of the branch exactly as it was typed. A slug
/// alone collides: `feature/a-b` and `feature-a/b` both become `feature-a-b`,
/// and two branches sharing one database is the failure this section is
/// arranged to prevent -- each reviewer seeing the other's writes, and the
/// second preview's teardown taking the first one's data with it.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The names of one branch's preview and its resources.
final class DVPreviewIdentity {
  const DVPreviewIdentity._({
    required this.branch,
    required this.name,
    required this.hostLabel,
    required this.database,
    required this.bucket,
    required this.queueNamespace,
  });

  /// The branch as it was typed.
  final String branch;

  /// The preview's own name: a slug of the branch and its digest.
  final String name;

  /// The DNS label the preview is served under. At most 63 characters.
  final String hostLabel;

  /// The database, as a SQL identifier. At most 63 characters, the Postgres
  /// limit past which a name is silently truncated -- into another preview's.
  final String database;

  /// The storage bucket, valid under S3's naming rules.
  final String bucket;

  /// The prefix every queue of this preview lives under.
  final String queueNamespace;

  static const int _labelLimit = 63;

  factory DVPreviewIdentity.forBranch({
    required String app,
    required String branch,
  }) {
    if (branch.trim().isEmpty) {
      throw ArgumentError.value(branch, 'branch', 'a preview needs a branch');
    }
    final String appSlug = _slug(app).isEmpty ? 'app' : _slug(app);
    final String digest =
        sha256.convert(utf8.encode(branch)).toString().substring(0, 8);
    final String branchSlug = _slug(branch).isEmpty ? 'branch' : _slug(branch);

    // Each name is `<fixed part>-<branch slug cut to fit>-<digest>`, so the
    // digest -- the part that keeps branches apart -- is never what the cut
    // removes.
    String fit(String prefix, String separator) {
      final int room = _labelLimit - prefix.length - digest.length - 2;
      String slug = branchSlug;
      if (slug.length > room) slug = slug.substring(0, room < 1 ? 1 : room);
      slug = slug.replaceAll(RegExp(r'-+$'), '');
      final String joined = '$prefix-$slug-$digest';
      return separator == '-' ? joined : joined.replaceAll('-', separator);
    }

    String appPart(int max) =>
        appSlug.length > max ? appSlug.substring(0, max) : appSlug;

    final String name = fit('preview', '-').substring('preview-'.length);
    final String dbApp = appPart(20);
    return DVPreviewIdentity._(
      branch: branch,
      name: name,
      hostLabel: fit('${appPart(20)}-preview', '-'),
      database: _startsWithLetter(fit('$dbApp-preview', '_')),
      bucket: fit('${appPart(20)}-preview', '-'),
      queueNamespace: 'preview-$name',
    );
  }

  static String _slug(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static String _startsWithLetter(String identifier) =>
      RegExp(r'^[a-z]').hasMatch(identifier)
          ? identifier
          : 'p${identifier.substring(1)}';

  /// Reads back what [toJson] wrote. The names are taken as recorded rather
  /// than derived again, so a record written before a naming change still
  /// names the resources that actually exist -- which are the ones a
  /// teardown has to reach.
  factory DVPreviewIdentity.fromJson(Map<String, Object?> json) {
    String field(String key) {
      final Object? value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('a preview identity has no $key');
      }
      return value;
    }

    return DVPreviewIdentity._(
      branch: field('branch'),
      name: field('name'),
      hostLabel: field('hostLabel'),
      database: field('database'),
      bucket: field('bucket'),
      queueNamespace: field('queueNamespace'),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'branch': branch,
        'name': name,
        'hostLabel': hostLabel,
        'database': database,
        'bucket': bucket,
        'queueNamespace': queueNamespace,
      };

  /// The names of every resource, for comparing against production's.
  Set<String> get resourceNames => <String>{
        hostLabel,
        database,
        bucket,
        queueNamespace,
      };
}
