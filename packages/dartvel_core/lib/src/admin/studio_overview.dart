/// Studio's Home: what the project holds, whether it is healthy, what changed
/// lately and what a person most often comes to do.
///
/// wp-admin opens on its Dashboard and Webflow on a site's overview; Studio
/// used to open on the page builder, which answered none of the questions a
/// person signing in has first -- is the site up, what changed since I was
/// last here, where do I start. This file is the data behind that screen,
/// shared by the API that answers it, the document the server prints for it
/// and the client that draws it, so the three cannot say different things.
///
/// Recent changes are a short list of what was saved in Studio, and when:
/// pages, records, data models, functions and grants. It names no person.
/// Who did what is an audit trail, which is Studio Pro's; this is the
/// "Activity" box a site's own dashboard has, kept to the last
/// [dvStudioActivityKept] changes.
library;

import '../database/records.dart';

/// The collection recent changes are kept in.
const String dvStudioActivityTable = 'dartvel_studio_activity';

/// How many changes are kept. Older ones are let go as new ones arrive: this
/// is "what changed lately", not a history to search.
const int dvStudioActivityKept = 50;

/// A change as a record.
const DVRecordShape dvStudioActivityShape = DVRecordShape(
  collection: dvStudioActivityTable,
  key: 'id',
  fields: <String, DVFieldType>{
    'id': DVFieldType.text,
    'at': DVFieldType.integer,
    'kind': DVFieldType.text,
    'action': DVFieldType.text,
    'label': DVFieldType.text,
    'screen': DVFieldType.text,
    'object': DVFieldType.text,
  },
);

/// One thing saved in Studio.
class DVStudioActivity {
  const DVStudioActivity({
    required this.at,
    required this.kind,
    required this.action,
    required this.label,
    required this.screen,
    this.object,
  });

  /// When, in milliseconds since the epoch, UTC.
  final int at;

  /// What kind of thing changed: `page`, `record`, `model`, `function`,
  /// `component` or `team`.
  final String kind;

  /// `created`, `saved` or `deleted`.
  final String action;

  /// What a person reads for it: a page's title, a model's name, or "A
  /// Product record" -- never a record's values.
  final String label;

  /// The Studio screen that opens it.
  final String screen;

  /// What opens it inside [screen], or null for the screen itself.
  final String? object;

  Map<String, Object?> toJson() => <String, Object?>{
    'at': at,
    'kind': kind,
    'action': action,
    'label': label,
    'screen': screen,
    'object': ?object,
  };

  factory DVStudioActivity.fromJson(Map<String, Object?> json) =>
      DVStudioActivity(
        at: switch (json['at']) {
          final int at => at,
          final num at => at.toInt(),
          final Object? at => int.tryParse('$at') ?? 0,
        },
        kind: '${json['kind'] ?? ''}',
        action: '${json['action'] ?? ''}',
        label: '${json['label'] ?? ''}',
        screen: '${json['screen'] ?? ''}',
        object: switch (json['object']) {
          null || '' => null,
          final Object object => '$object',
        },
      );
}

/// How a health check came out, in the three words WordPress's Site Health
/// uses, because they are the right three: fine, worth doing, do it now.
enum DVStudioHealthStatus { good, recommended, critical }

/// One line of Home's Site health.
class DVStudioHealthCheck {
  const DVStudioHealthCheck({
    required this.id,
    required this.status,
    required this.title,
    required this.detail,
    this.screen,
  });

  /// Stable, for tests and for a client to key on. An application's own
  /// check is `check:<name>`.
  final String id;
  final DVStudioHealthStatus status;

  /// What was checked, in a few words.
  final String title;

  /// What the result means, and what to do about it when there is anything.
  final String detail;

  /// The Studio screen that fixes it, when one does.
  final String? screen;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'status': status.name,
    'title': title,
    'detail': detail,
    'screen': ?screen,
  };

  factory DVStudioHealthCheck.fromJson(Map<String, Object?> json) =>
      DVStudioHealthCheck(
        id: '${json['id'] ?? ''}',
        status: DVStudioHealthStatus.values.firstWhere(
          (DVStudioHealthStatus s) => s.name == json['status'],
          orElse: () => DVStudioHealthStatus.recommended,
        ),
        title: '${json['title'] ?? ''}',
        detail: '${json['detail'] ?? ''}',
        screen: json['screen'] == null ? null : '${json['screen']}',
      );
}

/// What a person reads for [status].
String dvStudioHealthWords(DVStudioHealthStatus status) => switch (status) {
  DVStudioHealthStatus.good => 'Good',
  DVStudioHealthStatus.recommended => 'Recommended',
  DVStudioHealthStatus.critical => 'Needs attention now',
};

/// Home's data.
class DVStudioOverview {
  const DVStudioOverview({
    this.glance = const <String, int>{},
    this.health = const <DVStudioHealthCheck>[],
    this.recent = const <DVStudioActivity>[],
  });

  /// Counts by what they count: `pages`, `components`, `models`, `records`,
  /// `functions`, `tasks`, `team`.
  final Map<String, int> glance;
  final List<DVStudioHealthCheck> health;

  /// Newest first.
  final List<DVStudioActivity> recent;

  Map<String, Object?> toJson() => <String, Object?>{
    'glance': glance,
    'health': <Object?>[for (final DVStudioHealthCheck c in health) c.toJson()],
    'recent': <Object?>[for (final DVStudioActivity a in recent) a.toJson()],
  };

  factory DVStudioOverview.fromJson(
    Map<String, Object?> json,
  ) => DVStudioOverview(
    glance: <String, int>{
      for (final MapEntry<Object?, Object?> entry
          in ((json['glance'] as Map?) ?? const <Object?, Object?>{}).entries)
        if (entry.value is num) '${entry.key}': (entry.value! as num).toInt(),
    },
    health: <DVStudioHealthCheck>[
      for (final Object? check
          in (json['health'] as List?) ?? const <Object?>[])
        if (check is Map)
          DVStudioHealthCheck.fromJson(check.cast<String, Object?>()),
    ],
    recent: <DVStudioActivity>[
      for (final Object? row in (json['recent'] as List?) ?? const <Object?>[])
        if (row is Map) DVStudioActivity.fromJson(row.cast<String, Object?>()),
    ],
  );
}

/// One "At a glance" line: the count in words and the screen it opens.
///
/// Shared by the document and the client so both say "1 data model" and "3
/// records" the same way.
({String words, String screen})? dvStudioGlanceLine(String key, int count) {
  String plural(String one, String many) => '$count ${count == 1 ? one : many}';
  return switch (key) {
    'pages' => (words: plural('page', 'pages'), screen: 'pages'),
    'components' => (
      words: plural('component', 'components'),
      screen: 'components',
    ),
    'models' => (words: plural('data model', 'data models'), screen: 'models'),
    'records' => (words: plural('record', 'records'), screen: 'models'),
    'functions' => (
      words: plural('backend function', 'backend functions'),
      screen: 'functions',
    ),
    'tasks' => (
      words: plural('background task', 'background tasks'),
      screen: 'jobs',
    ),
    'team' => (
      words: count == 1
          ? '1 person can open Studio'
          : '$count people can open Studio',
      screen: 'access',
    ),
    _ => null,
  };
}

/// The order "At a glance" lists its counts in.
const List<String> dvStudioGlanceOrder = <String>[
  'pages',
  'components',
  'models',
  'records',
  'functions',
  'tasks',
  'team',
];

/// What Home offers to do, each the screen that does it: the same four in the
/// document and on screen.
const List<({String label, String screen})> dvStudioQuickActions =
    <({String label, String screen})>[
      (label: 'Add a page', screen: 'pages'),
      (label: 'Design a data model', screen: 'models'),
      (label: 'Add a teammate', screen: 'access'),
    ];

/// The change log, over whatever database the API was given.
class DVStudioActivityLog {
  DVStudioActivityLog(this.records);

  final DVRecordAdapter records;

  /// The last time handed out, so two changes in the same millisecond still
  /// sort in the order they were made.
  static int _last = 0;

  static int _now() {
    final int now = DateTime.now().toUtc().millisecondsSinceEpoch;
    _last = now > _last ? now : _last + 1;
    return _last;
  }

  /// Notes [kind]/[action] on [label]. Never throws: a change that was made
  /// is not undone because the note about it could not be written.
  Future<void> note({
    required String kind,
    required String action,
    required String label,
    required String screen,
    String? object,
  }) async {
    try {
      await records.ensure(dvStudioActivityShape);
      final int at = _now();
      await records.insert(dvStudioActivityTable, <String, Object?>{
        'id': '$at-$kind-${label.hashCode.toUnsigned(32)}',
        'at': at,
        'kind': kind,
        'action': action,
        'label': label,
        'screen': screen,
        'object': object ?? '',
      });
      final int count = await records.count(dvStudioActivityTable);
      if (count > dvStudioActivityKept) {
        final List<Map<String, Object?>> oldest = await records.find(
          dvStudioActivityTable,
          fields: const <String>['id'],
          orderBy: const <DVSort>[DVSort('at')],
          limit: count - dvStudioActivityKept,
        );
        for (final Map<String, Object?> row in oldest) {
          await records.delete(
            dvStudioActivityTable,
            where: DVFilter.equals('id', row['id']),
          );
        }
      }
    } on Object {
      // Recent changes are a convenience; the change itself stands.
    }
  }

  /// The latest [limit] changes, newest first.
  Future<List<DVStudioActivity>> recent({int limit = 20}) async {
    try {
      await records.ensure(dvStudioActivityShape);
      final List<Map<String, Object?>> rows = await records.find(
        dvStudioActivityTable,
        orderBy: const <DVSort>[DVSort('at', descending: true)],
        limit: limit,
      );
      return <DVStudioActivity>[
        for (final Map<String, Object?> row in rows)
          DVStudioActivity.fromJson(row),
      ];
    } on Object {
      return const <DVStudioActivity>[];
    }
  }
}
