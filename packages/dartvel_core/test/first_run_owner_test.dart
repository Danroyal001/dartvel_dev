// The owner an app has before anybody has signed up.
//
// A fixed default password is a published credential: the same secret in
// every Dartvel app, and the first scanner that learns it owns all of them.
// This mints one per app at first run, shows it once, and refuses to serve
// Studio until it has been changed.
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io' show Directory, File;
import 'dart:typed_data';

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

/// A response's status and its body, read once: a body stream cannot be read
/// twice, and an auth endpoint's own message is the only thing that says which
/// of the credential guard, the CSRF check or the session said no.
Future<(int, String)> _read(Response? response) async =>
    (response?.status ?? 0, await _bodyText(response));

/// The bytes of [response] as text.
Future<String> _bodyText(Response? response) async =>
    utf8.decode(await response?.body?.bytes() ?? const <int>[]);

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
      File('${root.path}/main.dart.js').writeAsStringSync('// Studio');
      server = DVAdminServer(
        mount: const DVAdminMount(
            path: '/__studio', enabled: true, requiresAuth: true),
        root: root.path,
        // The application's shell, which Studio's pages are rendered from.
        webRoot: root.path,
        authenticated: (Request _) async => true,
        models: const <DVStudioModelSpec>[],
        database: database,
      );
    });

    // The setup is a page of the Studio app, at <mount>/setup, exactly as its
    // sign-in is a page at <mount>/login. The server serves the shell and the
    // app draws the screen; a page of the server's own would be the last
    // hand-written HTML in Dartvel.
    test('is a page of the Studio app at <mount>/setup, and every other route '
        'on the mount goes there', () async {
      for (final String path in <String>[
        '/__studio',
        '/__studio/',
        '/__studio/pages',
        '/__studio/login',
      ]) {
        final Response? response = await get(path);
        expect(response?.status, 302, reason: path);
        expect(response!.headers.get('location'), '/__studio/setup',
            reason: path);
        expect(response.headers.get('cache-control'), 'no-store', reason: path);
      }

      final Response? setup = await get('/__studio/setup');
      expect(setup?.status, 200);
      expect(setup!.headers.get('content-type'), 'text/html; charset=utf-8');
      // Byte for byte the shell: the server writes no page of its own.
      expect(utf8.decode(await setup.body!.bytes()), '<title>Studio</title>');
    });

    test('serves the app\'s own code, so the screen can be drawn at all',
        () async {
      // The sign-in page is only reachable the same way, and a mount that
      // answered the shell but not its code served a blank page.
      final Response? code = await get('/__studio/main.dart.js');
      expect(code?.status, 200);
      expect(code!.headers.get('content-type'), 'text/javascript; charset=utf-8');
      expect(utf8.decode(await code.body!.bytes()), '// Studio');
    });

    test('never framed, never cached, and never a referrer', () async {
      final Response? setup = await get('/__studio/setup');
      expect(setup!.headers.get('cache-control'), 'no-store');
      expect(setup.headers.get('x-frame-options'), 'DENY');
      expect(setup.headers.get('referrer-policy'), 'no-referrer');
    });

    test('answers Studio\'s data to nobody until the setup is done', () async {
      // The hard screen: the graph and the records are not handed to a
      // stranger, and a path the mount does not serve gets the answer any
      // other path it does not serve gets.
      expect(await get('/__studio/api/models'), isNull);
      expect(await get('/__studio/graph.json'), isNull);
    });

    test('serves neither Studio\'s document under its file name nor its '
        'deferred parts', () async {
      // The same two rules the signed-out mount keeps once the setup is done:
      // Studio's document is reached only as the setup page, whose headers
      // it is served with, and Studio's deferred sections need the grant
      // nobody has yet.
      File('${server.root}/main.dart.js_1.part.js')
          .writeAsStringSync('// Studio section');
      expect(await get('/__studio/index.html'), isNull);
      expect(await get('/__studio/main.dart.js_1.part.js'), isNull);
      expect(await get('/__studio/missing.js'), isNull);
    });

    test('drives the application\'s own auth endpoints, at the mount, with '
        'the CSRF header required', () async {
      final DVSessions sessions = DVSessions();
      DVSessionAuthentication.install(sessions: sessions);
      addTearDown(DVSessionAuthentication.uninstall);
      final LocalAuthProvider accounts = LocalAuthProvider();
      final AuthUser account =
          (await accounts.signUp('owner@oakline.test', owner.password))!;
      DVAuthEndpoints.install(
          credentials:
              DVCredentialGuard(provider: accounts, refusalFloor: .zero),
          secondFactors: DVSecondFactors(
            store: DVDatabaseSecondFactorStore(MemoryDVDatabaseAdapter()),
            cipher: DVFieldCipher.secure(
              DVFieldKeyring(<DVFieldKey>[
                DVFieldKey(
                    'k1', Uint8List.fromList(List<int>.generate(32, (int i) => i))),
              ]),
            ),
            issuer: 'Oakline',
          ));
      addTearDown(DVAuthEndpoints.uninstall);
      // A live session of the owner, and the request carrying it. The
      // generated backend runs every request through the session stage, so
      // this is what the mount sees; a test that called the mount on its own
      // would hand the password endpoint no principal and be told 401 by the
      // endpoint rather than by the mount.
      final DVIssuedSession issued = await sessions.create(account.id);
      final DVSessionPrincipal principal =
          DVSessionPrincipal(session: issued.session, user: account);
      Future<(int, String)> post(
        String path,
        Map<String, Object?> body, {
        bool csrf = true,
        bool signedIn = true,
      }) async =>
          _read(await DVSessionPrincipal.actingAs(
            principal,
            () => server.respond(Request(
              method: 'POST',
              url: Uri.parse('http://localhost:8080$path'),
              headers: Headers(<String, String>{
                'content-type': 'application/json',
                if (csrf) 'x-dartvel-csrf-token': 'c' * 32,
                if (signedIn) 'authorization': 'Bearer ${issued.token}',
              }),
              bodyStream:
                  Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
            )),
          ));

      final Map<String, Object?> printed = <String, Object?>{
        'email': 'owner@oakline.test',
        'password': owner.password,
      };

      expect(
          (await post('/__studio/api/auth/sign-in', printed, csrf: false)).$1,
          403,
          reason: 'a cross-site form cannot set the header');

      final (int, String) signedOut =
          await post('/__studio/api/auth/sign-in', printed, signedIn: false);
      expect(signedOut.$1, 200, reason: signedOut.$2);

      // The other three the screen drives, in the order it drives them.
      final (int, String) changed = await post(
          '/__studio/api/auth/account/password',
          <String, Object?>{
            'currentPassword': owner.password,
            'newPassword': 'a-password-they-chose-themselves',
          },
        );
      expect(changed.$1, 200, reason: changed.$2);
      expect(await DVFirstRunOwner.setupPending(database: database), isTrue,
          reason: 'a password with no second factor is half a setup');

      final (int, String) started =
          await post('/__studio/api/auth/factors/totp', <String, Object?>{});
      expect(started.$1, 200, reason: started.$2);
      expect(started.$2, contains('secret'),
          reason: 'the screen has a key to show, so it has to be in the answer');

      // The fourth is reached as well. The mount's own answers to a path under
      // its API are a refusal for a missing CSRF header, a redirect, or
      // nothing at all, and none of them carries an endpoint's error code.
      final (int, String) refused = await post(
          '/__studio/api/auth/factors/totp/confirm',
          <String, Object?>{'code': '000000'});
      expect(refused.$1, isNot(403));
      expect(refused.$2, contains('error'),
          reason: 'the confirm endpoint answered, not the mount');

      expect(await get('/__studio/setup'), isNotNull,
          reason: 'still the setup screen: the second factor is not on');
    });

    test('opens only when the password and the second factor are both done',
        () async {
      await DVFirstRunOwner.changed(owner.userId);
      expect(await DVFirstRunOwner.setupPending(database: database), isTrue,
          reason: 'a password with no second factor is half a setup');

      final Response? still = await get('/__studio/');
      expect(still?.status, 302);
      expect(still!.headers.get('location'), '/__studio/setup');

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
        // The application's shell, which Studio's pages are rendered from.
        webRoot: root.path,
        // Nobody is signed in, which is the state the owner is in.
        authenticated: (Request _) async => false,
        database: database,
      );
    });

    test('a browser that has not signed in is sent to the setup page',
        () async {
      final Response? response = await get(shut, '/__studio/');

      expect(response?.status, 302);
      expect(response!.headers.get('location'), '/__studio/setup');
    });

    test('that page is served to anybody, signed in or not', () async {
      // The screen is what the owner opens, and the owner has no session yet:
      // signing in is what the screen is for. Studio's own rule -- that a
      // request from somebody not allowed to open it is answered as a route
      // that does not exist -- applied here made it unreachable by the only
      // person who needs it.
      final Response? response = await get(shut, '/__studio/setup');

      expect(response?.status, 200);
      expect(utf8.decode(await response!.body!.bytes()),
          '<title>Studio</title>',
          reason: 'the shell of the Studio app, which draws the screen');
    });

    test('it does not name the owner to whoever found the mount', () async {
      // The page is open to the internet while the setup is pending. Printing
      // the address on it hands half a credential to whoever asks.
      final Response? response = await get(shut, '/__studio/setup');

      expect(utf8.decode(await response!.body!.bytes()),
          isNot(contains('owner@oakline.test')));
    });

    test('once the setup is done the mount is shut to them again', () async {
      final DVFirstRunOwner owner =
          const DVFirstRunOwner(userId: '', email: '', password: '');
      expect(owner.password, '');
      final List<Map<String, Object?>> rows = await DVRecordAdapter.over(database)
          .find(DVFirstRunOwner.table);
      await DVFirstRunOwner.recordPasswordChanged('${rows.first['user_id']}');
      await DVFirstRunOwner.recordSecondFactor('${rows.first['user_id']}');

      // Somebody not signed in is sent to Studio's own sign-in, which is
      // not the setup screen.
      final Response? stranger = await get(shut, '/__studio/');
      expect(stranger?.status, 302);
      expect(stranger!.headers.get('location'), startsWith('/__studio/login?from='));
    });
  });
}
