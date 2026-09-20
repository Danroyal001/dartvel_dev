/// The owner an application has before anybody has signed up.
///
/// A fixed default password is a published credential: the same secret in
/// every Dartvel application, and the first scanner that learns it owns all
/// of them. Mirai took hundreds of thousands of devices with a list of about
/// sixty such pairs. So each application mints its own at first run, shows it
/// once, and will not serve Studio again until it has been changed.
library dartvel_core.auth.first_run_owner;

import 'dart:io';
import 'dart:math';

import '../admin/studio_access.dart';
import '../database/adapter.dart';
import '../database/records.dart';
import 'auth.dart';

/// The owner a first run created, and the password to sign in with once.
class DVFirstRunOwner {
  const DVFirstRunOwner({
    required this.userId,
    required this.email,
    required this.password,
  });

  final String userId;
  final String email;

  /// 32 characters from a secure random. Shown once, then never again.
  final String password;

  /// Where the password is written beside the database, for an operator who
  /// lost the console output -- a container's log, a scrollback, a service
  /// manager that swallowed it. Removed the moment the password changes.
  static const String passwordFileName = 'initial-owner-password.txt';

  /// The table that remembers the first run, so a restart does not mint a
  /// second owner and Studio knows the password is still the printed one.
  static const String table = 'dv_first_run_owner';

  static const DVRecordShape _shape = DVRecordShape(
    collection: table,
    key: 'user_id',
    fields: <String, DVFieldType>{
      'user_id': DVFieldType.text,
      'created_at': DVFieldType.integer,
      'changed_at': DVFieldType.integer,
      'mfa_at': DVFieldType.integer,
      'email': DVFieldType.text,
    },
  );

  /// Where [passwordFileName] was written, so [changed] can remove it.
  static String? _dataDirectory;

  /// Creates the owner when the application has no accounts at all.
  ///
  /// Answers null on every later start, and on an application somebody has
  /// already signed up to: a first run is a database with nobody in it.
  static Future<DVFirstRunOwner?> ensure({
    required AuthProvider accounts,
    required DVStudioGrants grants,
    required String dataDirectory,
    required String email,
    void Function(String line)? announce,
    Random? random,
  }) async {
    _dataDirectory = dataDirectory;
    final DVRecordAdapter records = const DVDatabase().records;
    await records.ensure(_shape);
    // Somebody is here already: either a person who signed up, or the owner
    // a previous start minted.
    if (await records.count(table) > 0) return null;
    if (accounts is DVAccountLookup &&
        await (accounts as DVAccountLookup).userByEmail(email) != null) {
      return null;
    }
    if (await _anyAccount(accounts)) return null;

    final String password = _password(random);
    final AuthUser? user =
        await accounts.signUp(email, password, name: 'Owner');
    if (user == null) {
      throw StateError(
        'The account provider would not create the first owner. Create one '
        'with dartvel admin, or configure a provider that can.',
      );
    }
    await records.insert(table, <String, Object?>{
      'user_id': user.id,
      'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      'changed_at': null,
      'mfa_at': null,
      'email': email,
    });
    await grants.grant(user.id);

    final DVFirstRunOwner owner =
        DVFirstRunOwner(userId: user.id, email: email, password: password);
    _write(owner, dataDirectory, announce ?? stdout.writeln);
    return owner;
  }

  /// Whether the first owner still has setting up to do: their own
  /// password, and a second factor on it.
  ///
  /// Studio serves its setup screen and nothing else until this is false. An
  /// application left running on the password its console printed is one
  /// anybody who saw that console can open, and an owner who wandered off
  /// mid-setup is exactly that.
  static Future<bool> setupPending({DVDatabaseAdapter? database}) async {
    try {
      final DVRecordAdapter records = database == null
          ? const DVDatabase().records
          : DVRecordAdapter.over(database);
      await records.ensure(_shape);
      final List<Map<String, Object?>> rows = await records.find(table);
      for (final Map<String, Object?> row in rows) {
        if (row['changed_at'] == null || row['mfa_at'] == null) return true;
      }
      return false;
    } on Object {
      return false;
    }
  }

  /// The address the first owner signs in with, for the setup screen.
  static Future<String?> ownerAddress({DVDatabaseAdapter? database}) async {
    try {
      final DVRecordAdapter records = database == null
          ? const DVDatabase().records
          : DVRecordAdapter.over(database);
      await records.ensure(_shape);
      final List<Map<String, Object?>> rows = await records.find(table);
      for (final Map<String, Object?> row in rows) {
        if (row['email'] != null) return '${row['email']}';
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// Records that the first owner changed their password, if [userId] is
  /// the first owner. Called by the application's own password endpoint.
  ///
  /// Guarded, because every account goes through that endpoint. A hook that
  /// did not check whose password it was would open Studio the first time
  /// any user changed one, and delete the owner's file on the way.
  static Future<void> recordPasswordChanged(String userId) async {
    if (!await _isOwner(userId)) return;
    await changed(userId);
  }

  /// Records that the first owner turned on a second factor, if [userId] is
  /// the first owner. Called by the application's own confirm endpoint.
  static Future<void> recordSecondFactor(String userId) async {
    if (!await _isOwner(userId)) return;
    await secondFactorEnrolled(userId);
  }

  /// Whether [userId] is the account this application's first run minted.
  ///
  /// Answers false when there is no database or no first-run table, so a
  /// password change on an application that never had a first run is
  /// untouched by any of this.
  static Future<bool> _isOwner(String userId) async {
    try {
      final DVRecordAdapter records = const DVDatabase().records;
      await records.ensure(_shape);
      final List<Map<String, Object?>> rows = await records
          .find(table, where: DVFilter.equals('user_id', userId));
      return rows.isNotEmpty;
    } on Object {
      return false;
    }
  }

  /// Records that the owner turned on a second factor.
  static Future<void> secondFactorEnrolled(String userId,
      {DVDatabaseAdapter? database}) async {
    final DVRecordAdapter records = database == null
        ? const DVDatabase().records
        : DVRecordAdapter.over(database);
    await records.ensure(_shape);
    await records.update(
      table,
      <String, Object?>{
        'mfa_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: DVFilter.equals('user_id', userId),
    );
  }

  /// Whether the owner is still signing in with the password that was
  /// printed. Studio is closed until this is false.
  static Future<bool> mustChangePassword({DVDatabaseAdapter? database}) async {
    try {
      final DVRecordAdapter records = database == null
          ? const DVDatabase().records
          : DVRecordAdapter.over(database);
      await records.ensure(_shape);
      final List<Map<String, Object?>> rows =
          await records.find(table, where: const DVFilter.isNull('changed_at'));
      return rows.isNotEmpty;
    } on Object {
      // No database, or none this process can read: an application with no
      // accounts store has no first-run owner either, and a Studio nobody
      // can sign in to is already shut.
      return false;
    }
  }

  /// Records that the owner has chosen their own password, and removes the
  /// file that carried the printed one.
  static Future<void> changed(String userId) async {
    final DVRecordAdapter records = const DVDatabase().records;
    await records.ensure(_shape);
    await records.update(
      table,
      <String, Object?>{
        'changed_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      where: DVFilter.equals('user_id', userId),
    );
    final String? directory = _dataDirectory;
    if (directory == null) return;
    final File file = File('$directory/$passwordFileName');
    if (file.existsSync()) file.deleteSync();
  }

  /// Forgets where the file was written. For tests.
  static void debugReset() => _dataDirectory = null;

  static Future<bool> _anyAccount(AuthProvider accounts) async {
    if (accounts is! DVAccountRoll) return false;
    return (accounts as DVAccountRoll).anyAccount();
  }

  /// Characters that cannot be misread when somebody copies them by hand:
  /// no O and 0, no l, I and 1.
  static const String _alphabet =
      'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _password(Random? random) {
    final Random source = random ?? Random.secure();
    return String.fromCharCodes(<int>[
      for (int i = 0; i < 32; i++)
        _alphabet.codeUnitAt(source.nextInt(_alphabet.length)),
    ]);
  }

  static void _write(
    DVFirstRunOwner owner,
    String dataDirectory,
    void Function(String line) announce,
  ) {
    final Directory directory = Directory(dataDirectory);
    directory.createSync(recursive: true);
    final File file = File('$dataDirectory/$passwordFileName');
    file.writeAsStringSync(
      'Dartvel created the first owner of this application.\n'
      '\n'
      '  address:  ${owner.email}\n'
      '  password: ${owner.password}\n'
      '\n'
      'Sign in at /__studio and change it. This file is removed then, and\n'
      'the password is never printed again.\n',
    );
    if (!Platform.isWindows) {
      // Nobody else on the machine reads it.
      Process.runSync('chmod', <String>['600', file.path]);
    }
    announce('');
    announce('Dartvel created the first owner of this application:');
    announce('');
    announce('  address:  ${owner.email}');
    announce('  password: ${owner.password}');
    announce('');
    announce('It is also in ${file.path}, which is removed when you change');
    announce('the password. Studio does not open until you do.');
    announce('');
  }
}

/// An account store that can say whether it holds anybody at all.
///
/// Separate from [DVAccountProvider] because a provider backed by somebody
/// else's directory cannot always answer it.
abstract interface class DVAccountRoll {
  /// Whether any account exists.
  Future<bool> anyAccount();
}
