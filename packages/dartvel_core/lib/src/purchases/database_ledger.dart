/// The purchase ledger in the application's own database.
///
/// The in-memory ledger forgets every grant on restart and cannot be seen by
/// a second instance, which for purchases is worse than for most things: a
/// store retries a notification against whichever instance answers, so a
/// claim recorded on one instance and invisible to another is a replay
/// applied twice, and a refund applied on one instance leaves the other
/// granting.
library dartvel.purchases.database_ledger;

import '../database/adapter.dart';
import 'purchases.dart';

class DVDatabasePurchaseLedger implements DVPurchaseLedger {
  DVDatabasePurchaseLedger(
    this.db, {
    this.grantsTable = 'dv_purchase_grants',
    this.notificationsTable = 'dv_purchase_notifications',
  }) {
    for (final String table in <String>[grantsTable, notificationsTable]) {
      if (!RegExp(r'^[A-Za-z_]\w*$').hasMatch(table)) {
        throw ArgumentError.value(table, 'table', 'is not a table name');
      }
    }
  }

  final DVDatabaseAdapter db;
  final String grantsTable;
  final String notificationsTable;
  Future<void>? _ready;

  /// The primary keys are what make a claim and a grant unique across
  /// instances on a real database. The development adapter reads no column
  /// definitions, so there the check before each insert is the only guard.
  Future<void> _ensureTables() => _ready ??= () async {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS $grantsTable (store TEXT NOT NULL, '
          'original_transaction_id TEXT NOT NULL, '
          'transaction_id TEXT NOT NULL, customer_key TEXT NOT NULL, '
          'product_id TEXT NOT NULL, store_product_id TEXT NOT NULL, '
          'purchased_at_us INTEGER NOT NULL, not_after_us INTEGER, '
          'revoked_at_us INTEGER, acknowledged INTEGER NOT NULL, '
          'last_event_at_us INTEGER NOT NULL, '
          'PRIMARY KEY (store, original_transaction_id))',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS $notificationsTable (store TEXT NOT NULL, '
          'notification_id TEXT NOT NULL, claimed_at_us INTEGER NOT NULL, '
          'PRIMARY KEY (store, notification_id))',
        );
      }();

  @override
  Future<DVPurchaseGrant?> find(
    DVStore store,
    String originalTransactionId,
  ) async {
    await _ensureTables();
    final List<Map<String, Object?>> rows = await db.query(
      'SELECT * FROM $grantsTable WHERE store = ? AND '
      'original_transaction_id = ?',
      <Object?>[store.name, originalTransactionId],
    );
    return rows.isEmpty ? null : _read(rows.first);
  }

  @override
  Future<void> put(DVPurchaseGrant grant) async {
    await _ensureTables();
    if (await _update(grant) > 0) return;
    try {
      await db.execute(
        'INSERT INTO $grantsTable (store, original_transaction_id, '
        'transaction_id, customer_key, product_id, store_product_id, '
        'purchased_at_us, not_after_us, revoked_at_us, acknowledged, '
        'last_event_at_us) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          grant.store.name,
          grant.originalTransactionId,
          ..._columns(grant),
        ],
      );
    } on Object catch (error) {
      // Another instance inserted it between the update and this insert.
      if (!_isUniqueViolation(error)) rethrow;
      await _update(grant);
    }
  }

  Future<int> _update(DVPurchaseGrant grant) => db.execute(
        'UPDATE $grantsTable SET transaction_id = ?, customer_key = ?, '
        'product_id = ?, store_product_id = ?, purchased_at_us = ?, '
        'not_after_us = ?, revoked_at_us = ?, acknowledged = ?, '
        'last_event_at_us = ? WHERE store = ? AND original_transaction_id = ?',
        <Object?>[
          ..._columns(grant),
          grant.store.name,
          grant.originalTransactionId,
        ],
      );

  static List<Object?> _columns(DVPurchaseGrant grant) => <Object?>[
        grant.transactionId,
        grant.customerKey,
        grant.productId,
        grant.storeProductId,
        grant.purchasedAt.microsecondsSinceEpoch,
        grant.notAfter?.microsecondsSinceEpoch,
        grant.revokedAt?.microsecondsSinceEpoch,
        grant.acknowledged ? 1 : 0,
        grant.lastEventAt.microsecondsSinceEpoch,
      ];

  @override
  Future<void> remove(DVStore store, String originalTransactionId) async {
    await _ensureTables();
    await db.execute(
      'DELETE FROM $grantsTable WHERE store = ? AND original_transaction_id = ?',
      <Object?>[store.name, originalTransactionId],
    );
  }

  @override
  Future<List<DVPurchaseGrant>> forCustomer(String customerKey) async {
    await _ensureTables();
    final List<Map<String, Object?>> rows = await db.query(
      'SELECT * FROM $grantsTable WHERE customer_key = ?',
      <Object?>[customerKey],
    );
    return rows.map(_read).toList();
  }

  @override
  Future<List<DVPurchaseGrant>> unacknowledged() async {
    await _ensureTables();
    final List<Map<String, Object?>> rows = await db.query(
      'SELECT * FROM $grantsTable WHERE acknowledged = ?',
      const <Object?>[0],
    );
    return rows.map(_read).toList();
  }

  @override
  Future<bool> claimNotification(DVStore store, String notificationId) async {
    await _ensureTables();
    final List<Map<String, Object?>> rows = await db.query(
      'SELECT COUNT(*) AS n FROM $notificationsTable WHERE store = ? AND '
      'notification_id = ?',
      <Object?>[store.name, notificationId],
    );
    if (rows.isNotEmpty && ((rows.first['n'] as num?) ?? 0) > 0) return false;
    try {
      await db.execute(
        'INSERT INTO $notificationsTable (store, notification_id, '
        'claimed_at_us) VALUES (?, ?, ?)',
        <Object?>[
          store.name,
          notificationId,
          DateTime.now().toUtc().microsecondsSinceEpoch,
        ],
      );
      return true;
    } on Object catch (error) {
      if (_isUniqueViolation(error)) return false;
      rethrow;
    }
  }

  @override
  Future<void> releaseNotification(DVStore store, String notificationId) async {
    await _ensureTables();
    await db.execute(
      'DELETE FROM $notificationsTable WHERE store = ? AND notification_id = ?',
      <Object?>[store.name, notificationId],
    );
  }

  static bool _isUniqueViolation(Object error) {
    final String text = '$error'.toUpperCase();
    return text.contains('UNIQUE') || text.contains('DUPLICATE');
  }

  static DVPurchaseGrant _read(Map<String, Object?> row) {
    DateTime at(Object? value) => DateTime.fromMicrosecondsSinceEpoch(
        (value! as num).toInt(),
        isUtc: true);
    DateTime? maybe(Object? value) => value == null ? null : at(value);
    return DVPurchaseGrant(
      store: DVStore.values.byName('${row['store']}'),
      originalTransactionId: '${row['original_transaction_id']}',
      transactionId: '${row['transaction_id']}',
      customerKey: '${row['customer_key']}',
      productId: '${row['product_id']}',
      storeProductId: '${row['store_product_id']}',
      purchasedAt: at(row['purchased_at_us']),
      notAfter: maybe(row['not_after_us']),
      revokedAt: maybe(row['revoked_at_us']),
      acknowledged: (row['acknowledged']! as num) != 0,
      lastEventAt: at(row['last_event_at_us']),
    );
  }
}
