/// Account deletions waiting out the grace period the project configures.
///
/// A deletion request is recorded here and the person's sessions end; the
/// account and its data stay until the window closes, and signing in within
/// it cancels. Once due, [DVAccountErasureJob] runs the erasure through
/// `DVQueues`.
///
/// Every change of state is a compare-and-set on the row: signing in moves a
/// deletion from scheduled to cancelled only while it is still scheduled, and
/// the erasure moves it from scheduled to erasing only while it is still
/// scheduled. Whichever comes second finds the row moved and does nothing --
/// so an erasure never runs for somebody who cancelled, and a sign-in never
/// cancels an erasure already under way.
library dartvel_core.auth.account_deletions;

import '../database/adapter.dart' show DVDatabaseAdapter;

/// Where a deletion is.
enum DVAccountDeletionState {
  /// Waiting for its window to close.
  scheduled,

  /// The person signed in within the window.
  cancelled,

  /// Claimed by an erasure job.
  erasing,

  /// Erased, and the account removed.
  erased,
}

/// One account's deletion request.
class DVAccountDeletion {
  const DVAccountDeletion({
    required this.userId,
    required this.requestedAt,
    required this.dueAt,
    required this.state,
    this.claimedAt,
  });

  final String userId;

  /// When the person asked. The erasure's deadline runs from here.
  final DateTime requestedAt;

  /// When the window closes and the erasure may run.
  final DateTime dueAt;

  final DVAccountDeletionState state;

  /// When an erasure job last claimed it, for one that stopped half way.
  final DateTime? claimedAt;

  @override
  String toString() => 'DVAccountDeletion($userId, ${state.name}, due $dueAt)';
}

/// The deletion requests of one deployment, in its database: every process
/// that signs somebody in, or sweeps, reads the same rows.
class DVAccountDeletionStore {
  DVAccountDeletionStore(this.database, {this.table = 'dv_account_deletions'});

  final DVDatabaseAdapter database;
  final String table;

  Future<void>? _ready;

  Future<void> _ensure() => _ready ??= database.execute(
        'CREATE TABLE IF NOT EXISTS $table ('
        'user_id TEXT, requested_at INTEGER, due_at INTEGER, state TEXT, '
        'claimed_at INTEGER)',
      );

  /// Records a deletion request, replacing any earlier one for the account.
  Future<void> schedule(String userId,
      {required DateTime requestedAt, required DateTime dueAt}) async {
    await _ensure();
    await database.execute('DELETE FROM $table WHERE user_id = ?', <Object?>[userId]);
    await database.execute(
      'INSERT INTO $table (user_id, requested_at, due_at, state, claimed_at) '
      'VALUES (?, ?, ?, ?, ?)',
      <Object?>[
        userId,
        requestedAt.toUtc().millisecondsSinceEpoch,
        dueAt.toUtc().millisecondsSinceEpoch,
        DVAccountDeletionState.scheduled.name,
        0,
      ],
    );
  }

  /// The account's deletion request, or null when it has none.
  Future<DVAccountDeletion?> find(String userId) async {
    await _ensure();
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT user_id, requested_at, due_at, state, claimed_at FROM $table '
      'WHERE user_id = ?',
      <Object?>[userId],
    );
    return rows.isEmpty ? null : _read(rows.first);
  }

  /// Scheduled deletions whose window closed at or before [now], and
  /// erasures claimed before [staleBefore] that never finished.
  Future<List<DVAccountDeletion>> due(DateTime now, {required DateTime staleBefore}) async {
    await _ensure();
    final List<Map<String, Object?>> scheduled = await database.query(
      'SELECT user_id, requested_at, due_at, state, claimed_at FROM $table '
      'WHERE state = ? AND due_at <= ?',
      <Object?>[DVAccountDeletionState.scheduled.name, now.toUtc().millisecondsSinceEpoch],
    );
    final List<Map<String, Object?>> stale = await database.query(
      'SELECT user_id, requested_at, due_at, state, claimed_at FROM $table '
      'WHERE state = ? AND claimed_at <= ?',
      <Object?>[DVAccountDeletionState.erasing.name, staleBefore.toUtc().millisecondsSinceEpoch],
    );
    return <DVAccountDeletion>[
      for (final Map<String, Object?> row in <Map<String, Object?>>[...scheduled, ...stale])
        _read(row),
    ];
  }

  /// Moves the account's deletion from [from] to [to], only if it is still
  /// exactly [from] -- claimed at [claimedAt] when [from] is erasing -- and
  /// answers whether it moved.
  Future<bool> move(
    String userId, {
    required DVAccountDeletionState from,
    required DVAccountDeletionState to,
    DateTime? claimedAt,
    DateTime? newClaimedAt,
  }) async {
    await _ensure();
    final int claimed = claimedAt?.toUtc().millisecondsSinceEpoch ?? 0;
    final int affected = await database.execute(
      'UPDATE $table SET state = ?, claimed_at = ? '
      'WHERE user_id = ? AND state = ? AND claimed_at = ?',
      <Object?>[
        to.name,
        newClaimedAt?.toUtc().millisecondsSinceEpoch ?? 0,
        userId,
        from.name,
        from == DVAccountDeletionState.erasing ? claimed : 0,
      ],
    );
    return affected > 0;
  }

  static DVAccountDeletion _read(Map<String, Object?> row) {
    DateTime at(Object? value) =>
        DateTime.fromMillisecondsSinceEpoch((value as num).toInt(), isUtc: true);
    final Object? claimed = row['claimed_at'];
    return DVAccountDeletion(
      userId: '${row['user_id']}',
      requestedAt: at(row['requested_at']),
      dueAt: at(row['due_at']),
      state: DVAccountDeletionState.values.byName('${row['state']}'),
      claimedAt: claimed is num && claimed > 0 ? at(claimed) : null,
    );
  }
}

/// The job that erases an account whose grace period has ended.
class DVAccountErasureJob {
  const DVAccountErasureJob(this.userId);

  final String userId;

  /// The name the job is stored under in a durable queue.
  static const String codecName = 'dartvel.auth.account_erasure';

  static Map<String, Object?> encode(DVAccountErasureJob job) =>
      <String, Object?>{'userId': job.userId};

  static DVAccountErasureJob decode(Map<String, Object?> json) =>
      DVAccountErasureJob('${json['userId']}');

  @override
  String toString() => 'DVAccountErasureJob($userId)';
}
