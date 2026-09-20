// The owner an app has before anybody has signed up.
//
// A fixed default password is a published credential: the same secret in
// every Dartvel app, and the first scanner that learns it owns all of them.
// This mints one per app at first run, shows it once, and refuses to serve
// Studio until it has been changed.
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io' show Directory, File;

import 'package:dartvel_core/dartvel.dart';

import 'package:test/test.dart';

late Directory data;
late SqliteDVDatabaseAdapter database;
late DVDatabaseAuthProvider accounts;
late DVStudioGrants grants;
late List<String> printed;

Future<DVFirstRunOwner?> firstRun() => DVFirstRunOwner.ensure(
      accounts: accounts,
      grants: grants,
      dataDirectory: data.path,
      email: 'owner@oakline.test',
      announce: printed.add,
    );

void main() {
  wiring();
  reachable();
  setUp(() {
    data = Directory.systemTemp.createTempSync('dartvel_first_run_');
    database = SqliteDVDatabaseAdapter.memory();
    const DVDatabase().configure(database);
    accounts = DVDatabaseAuthProvider(database);
    grants = DVStudioGrants(database);
    printed = <String>[];
  });

  tearDown(() {
    database.close();
    const DVDatabase().unconfigure();
    if (data.existsSync()) data.deleteSync(recursive: true);
  });

  test('mints an owner, a long password, and a Studio grant', () async {
    final DVFirstRunOwner? owner = await firstRun();

    expect(owner, isNotNull);
    expect(owner!.password.length, 32);
    expect(await accounts.userByEmail('owner@oakline.test'), isNotNull);
    expect(await grants.isGranted(owner.userId), isTrue);
    expect(
      await accounts.signIn('owner@oakline.test', owner.password),
      isNotNull,
      reason: 'the password printed is the password that works',
    );
  });

  test('says it once, on the console and in a file only the owner can read',
      () async {
    final DVFirstRunOwner? owner = await firstRun();

    expect(printed.join('\n'), contains(owner!.password));
    final File file = File('${data.path}/initial-owner-password.txt');
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains(owner.password));
    if (!io.Platform.isWindows) {
      final String mode = (file.statSync().mode & 0x1FF).toRadixString(8);
      expect(mode, '600', reason: 'nobody else on the machine reads it');
    }
  });

  test('a second start mints nothing and says nothing', () async {
    final DVFirstRunOwner? first = await firstRun();
    printed.clear();

    final DVFirstRunOwner? again = await firstRun();

    expect(first, isNotNull);
    expect(again, isNull);
    expect(printed, isEmpty);
  });

  test('an app that already has an account is not a first run', () async {
    await accounts.signUp('ada@oakline.test', 'a-long-enough-password');

    expect(await firstRun(), isNull);
  });

  // A hard screen: until the owner has set their own password and turned on
  // a second factor, the mount serves that screen and nothing else. Jenkins
  // prints a password and leaves the instance open while somebody wanders
  // off; an abandoned first run should not be an open door.
  group('the setup screen', () {
    late DVAdminServer server;
    late DVFirstRunOwner owner;

    Future<Response?> get(String path) => server.respond(Request(
          method: 'GET',
          url: Uri.parse('http://localhost:8080$path'),
          headers: Headers(const <String, String>{}),
          bodyStream: const Stream<List<int>>.empty(),
        ));

    setUp(() async {
      owner = (await firstRun())!;
      final Directory root = Directory.systemTemp.createTempSync('dv_setup_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/index.html').writeAsStringSync('<title>Studio</title>');
      server = DVAdminServer(
        mount: const DVAdminMount(
            path: '/__studio', enabled: true, requiresAuth: true),
        root: root.path,
        authenticated: (Request _) async => true,
        models: const <DVStudioModelSpec>[],
        database: database,
      );
    });

    test('is what every route on the mount answers with', () async {
      for (final String path in <String>[
        '/__studio/',
        '/__studio/pages',
        '/__studio/api/models',
      ]) {
        final Response? response = await get(path);
        expect(response?.status, 200, reason: path);
        final String body = utf8.decode(await response!.body!.bytes());
        expect(body, contains('Finish setting up'), reason: path);
        expect(body, isNot(contains('<title>Studio</title>')), reason: path);
      }
    });

    test('opens only when the password and the second factor are both done',
        () async {
      await DVFirstRunOwner.changed(owner.userId);
      expect(await DVFirstRunOwner.setupPending(database: database), isTrue,
          reason: 'a password with no second factor is half a setup');

      await DVFirstRunOwner.secondFactorEnrolled(owner.userId);
      expect(await DVFirstRunOwner.setupPending(database: database), isFalse);

      final Response? open = await get('/__studio/');
      expect(open?.status, 200);
      expect(utf8.decode(await open!.body!.bytes()),
          contains('<title>Studio</title>'));
    });
  });

  test('Studio stays shut until the password has been changed', () async {
    final DVFirstRunOwner? owner = await firstRun();

    expect(await DVFirstRunOwner.mustChangePassword(), isTrue);

    await DVFirstRunOwner.changed(owner!.userId);

    expect(await DVFirstRunOwner.mustChangePassword(), isFalse);
    expect(File('${data.path}/initial-owner-password.txt').existsSync(), isFalse,
        reason: 'the file is of no use once the password has changed');
  });
}

// Finishing the setup is the application's own auth endpoints doing their
// ordinary job: there is no first-run password endpoint and no first-run
// second-factor endpoint, because a second pair of those is a second place
// for a rate limit, a CSRF check and a session rotation to be got wrong.
// What the first run adds is the record that it happened.
void wiring() {
  group('the gate is cleared by the endpoints that do the work', () {
    test('the owner changing their password clears the first half', () async {
      final DVFirstRunOwner owner = (await firstRun())!;
      expect(await DVFirstRunOwner.mustChangePassword(database: database),
          isTrue);

      await DVFirstRunOwner.recordPasswordChanged(owner.userId);

      expect(await DVFirstRunOwner.mustChangePassword(database: database),
          isFalse);
      expect(File('${data.path}/initial-owner-password.txt').existsSync(),
          isFalse);
    });

    test('somebody else changing theirs clears nothing', () async {
      // Every account on the application goes through the same endpoint. A
      // hook that did not check whose password it was would open Studio the
      // first time any user changed one, and delete the owner's file on the
      // way.
      await firstRun();
      final AuthUser? ada =
          await accounts.signUp('ada@oakline.test', 'a-long-enough-password');

      await DVFirstRunOwner.recordPasswordChanged(ada!.id);
      await DVFirstRunOwner.recordSecondFactor(ada.id);

      expect(await DVFirstRunOwner.setupPending(database: database), isTrue);
      expect(File('${data.path}/initial-owner-password.txt').existsSync(),
          isTrue);
    });

    test('the owner enrolling a second factor opens Studio', () async {
      final DVFirstRunOwner owner = (await firstRun())!;

      await DVFirstRunOwner.recordPasswordChanged(owner.userId);
      await DVFirstRunOwner.recordSecondFactor(owner.userId);

      expect(await DVFirstRunOwner.setupPending(database: database), isFalse);
    });
  });
}

// The screen has to be reachable by somebody who has not signed in, because
// signing in is what it is for. Studio's own rule is that a request from
// somebody not allowed to open it is answered exactly as a route that does
// not exist -- and applying that here made the setup screen unreachable by
// the only person who needs it.
void reachable() {
  group('reaching the setup screen', () {
    late DVAdminServer shut;

    Future<Response?> get(DVAdminServer server, String path) =>
        server.respond(Request(
          method: 'GET',
          url: Uri.parse('http://localhost:8080$path'),
          headers: Headers(const <String, String>{}),
          bodyStream: const Stream<List<int>>.empty(),
        ));

    setUp(() async {
      await firstRun();
      final Directory root = Directory.systemTemp.createTempSync('dv_shut_');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/index.html').writeAsStringSync('<title>Studio</title>');
      shut = DVAdminServer(
        mount: const DVAdminMount(
            path: '/__studio', enabled: true, requiresAuth: true),
        root: root.path,
        // Nobody is signed in, which is the state the owner is in.
        authenticated: (Request _) async => false,
        database: database,
      );
    });

    test('a browser that has not signed in is given the setup screen',
        () async {
      final Response? response = await get(shut, '/__studio/');

      expect(response?.status, 200);
      expect(utf8.decode(await response!.body!.bytes()),
          contains('Finish setting up'));
    });

    test('it does not name the owner to whoever found the mount', () async {
      // The page is open to the internet while the setup is pending. Printing
      // the address on it hands half a credential to whoever asks.
      final Response? response = await get(shut, '/__studio/');

      expect(utf8.decode(await response!.body!.bytes()),
          isNot(contains('owner@oakline.test')));
    });

    test('once the setup is done the mount is shut to them again', () async {
      final DVFirstRunOwner owner =
          DVFirstRunOwner(userId: '', email: '', password: '');
      expect(owner.password, '');
      final List<Map<String, Object?>> rows = await DVRecordAdapter.over(database)
          .find(DVFirstRunOwner.table);
      await DVFirstRunOwner.recordPasswordChanged('${rows.first['user_id']}');
      await DVFirstRunOwner.recordSecondFactor('${rows.first['user_id']}');

      expect(await get(shut, '/__studio/'), isNull,
          reason: 'a request from somebody not signed in is answered exactly '
              'as a route that does not exist');
    });
  });
}
