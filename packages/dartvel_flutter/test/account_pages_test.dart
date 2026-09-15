// The prebuilt account pages: DV.Auth.SecurityPage, SessionsPage, SignUpPage,
// ProfilePage and DeletePage.
//
// Each drives the generated endpoints through DV.Auth against a recording
// backend. The silent failures here:
//  * the QR code encoding something other than the secret the server
//    returned -- read back with the independent reader, not compared as text;
//  * recovery codes still on screen, or readable from the page, after the
//    person dismisses them;
//  * a factor removed without a code being asked for;
//  * a sign-up refusal that tells "that address has an account" apart from
//    any other failure, or echoes the address or the server's words;
//  * the profile showing a new address before it is verified;
//  * deletion sent without the typed confirmation or the password;
//  * any page overflowing at a common window size.
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/qr_reader.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const String _rotated = 'dvs_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB';
const String _secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

Map<String, Object?> _session(String id,
        {String? device, bool current = true, String lastSeen = '2026-09-15T12:30:00.000Z'}) =>
    <String, Object?>{
      'id': id,
      'userId': 'local_1',
      'tenant': 'default',
      'createdAt': '2026-09-15T12:00:00.000Z',
      'lastSeenAt': lastSeen,
      if (device != null) 'device': device,
      'claims': <String, Object?>{},
      'mfaSatisfiedAt': null,
      'isCurrent': current,
    };

DVHttpResponse _json(int status, Object body) =>
    DVHttpResponse(statusCode: status, body: jsonEncode(body));

typedef _Route = DVHttpResponse Function(DVHttpRequest request);

class _Backend {
  final Map<String, _Route> routes = <String, _Route>{};
  final List<DVHttpRequest> requests = <DVHttpRequest>[];

  Future<DVHttpResponse> send(DVHttpRequest request) async {
    requests.add(request);
    final String path = request.url.path.replaceFirst('/api', '');
    final _Route? route = routes['${request.method} $path'];
    if (route == null) return _json(404, <String, Object?>{'error': 'not_found'});
    return route(request);
  }

  List<String> get paths => <String>[
        for (final DVHttpRequest r in requests)
          '${r.method} ${r.url.path.replaceFirst('/api', '')}',
      ];

  Map<String, Object?> bodyOf(String route) {
    final DVHttpRequest request = requests.lastWhere((DVHttpRequest r) =>
        '${r.method} ${r.url.path.replaceFirst('/api', '')}' == route);
    return jsonDecode(utf8.decode(request.body)) as Map<String, Object?>;
  }
}

const List<Size> _sizes = <Size>[Size(800, 600), Size(1440, 900)];

void main() {
  late _Backend backend;

  Future<void> install({bool signIn = true}) async {
    backend = _Backend();
    backend.routes['POST /auth/sign-in'] = (_) => _json(200, <String, Object?>{
          'user': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
          'mfaRequired': false,
          'session': _session('ses_here'),
          'token': _token,
        });
    final DVSessionClient client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      tokens: DVMemorySessionTokenStore(),
      web: false,
      send: backend.send,
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
    if (signIn) {
      await DV.Auth.signInWithEmailAndPassword(
          email: 'ada@example.com', password: 'correct horse');
      backend.requests.clear();
    }
  }

  Future<void> pump(WidgetTester tester, Widget page, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
    await settle(tester);
  }

  tearDown(() {
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
  });

  // --- SecurityPage ----------------------------------------------------------

  group('SecurityPage', () {
    for (final Size size in _sizes) {
      testWidgets('enrolls an authenticator from a QR code that carries the '
          'server\'s secret (${size.width.toInt()}x${size.height.toInt()})',
          (WidgetTester tester) async {
        await tester.runAsync(() => install());
        bool active = false;
        backend.routes['GET /auth/factors'] = (_) =>
            _json(200, <String, Object?>{'totp': active, 'recoveryCodes': 0});
        backend.routes['POST /auth/factors/totp'] = (_) => _json(200, <String, Object?>{
              'secret': _secret,
              'uri': 'otpauth://totp/Probe:ada%40example.com?secret=$_secret'
                  '&issuer=Probe&algorithm=SHA1&digits=6&period=30',
            });
        backend.routes['POST /auth/factors/totp/confirm'] = (_) {
          active = true;
          return _json(200, <String, Object?>{
            'session': _session('ses_rotated'),
            'token': _rotated,
          });
        };
        await pump(tester, DV.Auth.SecurityPage(), size);
        expect(find.byKey(const ValueKey<String>('dv-security-totp-off')), findsOneWidget);
        expect(find.byType(DVQrImage), findsNothing);

        await tester.tap(find.byKey(const ValueKey<String>('dv-security-enroll')));
        await settle(tester);
        final DVQrImage image = tester.widget(find.byType(DVQrImage));
        final Uri encoded = Uri.parse(readQr(image.code.modules).text);
        expect(encoded.queryParameters['secret'], _secret);
        expect(find.text(_secret), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.enterText(
            find.byKey(const ValueKey<String>('dv-security-code')), '123456');
        await tester.tap(find.byKey(const ValueKey<String>('dv-security-confirm')));
        await settle(tester);
        expect(backend.bodyOf('POST /auth/factors/totp/confirm'),
            <String, Object?>{'code': '123456'});
        expect(DV.Session.id, 'ses_rotated');
        expect(find.byKey(const ValueKey<String>('dv-security-totp-on')), findsOneWidget);
        expect(find.byType(DVQrImage), findsNothing);
        expect(find.text(_secret), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('shows recovery codes once, copies them, and keeps none after '
        'they are dismissed', (WidgetTester tester) async {
      await tester.runAsync(() => install());
      int remaining = 0;
      backend.routes['GET /auth/factors'] = (_) =>
          _json(200, <String, Object?>{'totp': true, 'recoveryCodes': remaining});
      backend.routes['POST /auth/factors/recovery-codes'] = (_) {
        remaining = 2;
        return _json(200, <String, Object?>{
          'recoveryCodes': <String>['AAAAA-BBBBB', 'CCCCC-DDDDD'],
          'session': _session('ses_rotated'),
          'token': _rotated,
        });
      };
      final List<String> copied = <String>[];
      DVNativeBridge.register('clipboard.copy', (Object? arguments) {
        copied.add((arguments! as Map<Object?, Object?>)['text']! as String);
        return true;
      });
      addTearDown(() => DVNativeBridge.unregister('clipboard.copy'));

      await pump(tester, DV.Auth.SecurityPage(), const Size(800, 600));
      await tester.tap(find.byKey(const ValueKey<String>('dv-security-recovery-generate')));
      await settle(tester);
      expect(find.text('AAAAA-BBBBB'), findsOneWidget);
      expect(find.text('CCCCC-DDDDD'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('dv-security-recovery-copy')));
      await settle(tester);
      expect(copied.single, contains('AAAAA-BBBBB'));
      expect(copied.single, contains('CCCCC-DDDDD'));

      await tester.tap(find.byKey(const ValueKey<String>('dv-security-recovery-done')));
      await settle(tester);
      expect(find.text('AAAAA-BBBBB'), findsNothing);
      expect(find.textContaining('AAAAA'), findsNothing);
      expect(find.byKey(const ValueKey<String>('dv-security-recovery-remaining')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('removing the authenticator asks for a code and sends it',
        (WidgetTester tester) async {
      await tester.runAsync(() => install());
      bool active = true;
      backend.routes['GET /auth/factors'] = (_) =>
          _json(200, <String, Object?>{'totp': active, 'recoveryCodes': 3});
      backend.routes['POST /auth/factors/remove'] = (_) {
        active = false;
        return _json(200, <String, Object?>{
          'session': _session('ses_rotated'),
          'token': _rotated,
        });
      };
      await pump(tester, DV.Auth.SecurityPage(), const Size(800, 600));
      await tester.tap(find.byKey(const ValueKey<String>('dv-security-remove')));
      await settle(tester);
      expect(backend.paths, isNot(contains('POST /auth/factors/remove')));
      expect(find.byKey(const ValueKey<String>('dv-security-error')), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-security-remove-code')), '654321');
      await tester.tap(find.byKey(const ValueKey<String>('dv-security-remove')));
      await settle(tester);
      expect(backend.bodyOf('POST /auth/factors/remove'),
          <String, Object?>{'code': '654321'});
      expect(find.byKey(const ValueKey<String>('dv-security-totp-off')), findsOneWidget);
    });
  });

  // --- SessionsPage ----------------------------------------------------------

  group('SessionsPage', () {
    for (final Size size in _sizes) {
      testWidgets('lists every device with its last use, and revokes one and '
          'the others (${size.width.toInt()}x${size.height.toInt()})',
          (WidgetTester tester) async {
        await tester.runAsync(() => install());
        List<Map<String, Object?>> live = <Map<String, Object?>>[
          _session('ses_here', device: 'Android phone'),
          _session('ses_laptop',
              current: false, device: 'macOS desktop', lastSeen: '2026-09-14T08:05:00.000Z'),
          _session('ses_old', current: false, lastSeen: '2026-09-01T10:00:00.000Z'),
        ];
        backend.routes['GET /auth/sessions'] =
            (_) => _json(200, <String, Object?>{'sessions': live});
        backend.routes['POST /auth/sessions/revoke'] = (DVHttpRequest request) {
          final String id = (jsonDecode(utf8.decode(request.body)) as Map)['id'] as String;
          live = <Map<String, Object?>>[for (final s in live) if (s['id'] != id) s];
          return const DVHttpResponse(statusCode: 204, body: '');
        };
        backend.routes['POST /auth/sessions/revoke-others'] = (_) {
          final int n = live.length - 1;
          live = <Map<String, Object?>>[for (final s in live) if (s['isCurrent'] == true) s];
          return _json(200, <String, Object?>{'revoked': n});
        };
        await pump(tester, DV.Auth.SessionsPage(), size);
        expect(find.text('Android phone'), findsOneWidget);
        expect(find.text('macOS desktop'), findsOneWidget);
        expect(find.text('Unknown device'), findsOneWidget);
        expect(find.byKey(const ValueKey<String>('dv-sessions-current-ses_here')),
            findsOneWidget);
        expect(find.textContaining('2026-09-14'), findsOneWidget);
        // This device is not revoked from here; signing out is.
        expect(find.byKey(const ValueKey<String>('dv-sessions-revoke-ses_here')),
            findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey<String>('dv-sessions-revoke-ses_laptop')));
        await settle(tester);
        expect(backend.bodyOf('POST /auth/sessions/revoke'),
            <String, Object?>{'id': 'ses_laptop'});
        expect(find.text('macOS desktop'), findsNothing);

        await tester.tap(find.byKey(const ValueKey<String>('dv-sessions-revoke-others')));
        await settle(tester);
        expect(backend.paths, contains('POST /auth/sessions/revoke-others'));
        expect(find.text('Unknown device'), findsNothing);
        expect(find.text('Android phone'), findsOneWidget);
        expect(DV.Session.id, 'ses_here');
        expect(tester.takeException(), isNull);
      });
    }
  });

  // --- SignUpPage -------------------------------------------------------------

  group('SignUpPage', () {
    Future<void> submit(WidgetTester tester, String email) async {
      await tester.enterText(find.byKey(const ValueKey<String>('dv-signup-email')), email);
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-signup-password')), 'correct horse battery');
      await tester.tap(find.byKey(const ValueKey<String>('dv-signup-submit')));
      await settle(tester);
    }

    for (final Size size in _sizes) {
      testWidgets('creates the account and signs in '
          '(${size.width.toInt()}x${size.height.toInt()})', (WidgetTester tester) async {
        await tester.runAsync(() => install(signIn: false));
        backend.routes['POST /auth/sign-up'] = (_) => _json(200, <String, Object?>{
              'user': <String, Object?>{'id': 'local_9', 'email': 'new@example.com'},
              'mfaRequired': false,
              'session': _session('ses_new'),
              'token': _token,
            });
        await pump(tester, DV.Auth.SignUpPage(), size);
        await tester.enterText(find.byKey(const ValueKey<String>('dv-signup-name')), 'Ada');
        await submit(tester, 'new@example.com');
        expect(backend.bodyOf('POST /auth/sign-up'), <String, Object?>{
          'email': 'new@example.com',
          'password': 'correct horse battery',
          'name': 'Ada',
        });
        expect(DV.Session.id, 'ses_new');
        expect(find.byKey(const ValueKey<String>('dv-signup-done')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a taken address reads exactly like any other failure, and '
        'nothing the server said or the address is shown', (WidgetTester tester) async {
      await tester.runAsync(() => install(signIn: false));
      backend.routes['POST /auth/sign-up'] = (_) => _json(409, <String, Object?>{
            'error': 'account_exists',
            'message': 'An account already exists for that e-mail address.',
          });
      await pump(tester, DV.Auth.SignUpPage(), const Size(800, 600));
      await submit(tester, 'taken@example.com');
      final String taken = tester
          .widget<DVText>(find.descendant(
              of: find.byKey(const ValueKey<String>('dv-signup-error')),
              matching: find.byType(DVText)))
          .text;

      backend.routes['POST /auth/sign-up'] =
          (_) => const DVHttpResponse(statusCode: 503, body: 'Service Unavailable');
      await submit(tester, 'other@example.com');
      final String other = tester
          .widget<DVText>(find.descendant(
              of: find.byKey(const ValueKey<String>('dv-signup-error')),
              matching: find.byType(DVText)))
          .text;

      expect(taken, other);
      expect(taken, isNot(contains('taken@example.com')));
      expect(taken.toLowerCase(), isNot(contains('already exists')));
      expect(DV.Session.current, isNull);
    });

    testWidgets('a weak password says so, because that is about the input',
        (WidgetTester tester) async {
      await tester.runAsync(() => install(signIn: false));
      backend.routes['POST /auth/sign-up'] = (_) =>
          _json(400, <String, Object?>{'error': 'weak_password', 'message': 'x'});
      await pump(tester, DV.Auth.SignUpPage(), const Size(800, 600));
      await submit(tester, 'new@example.com');
      expect(find.text('That password is too weak.'), findsOneWidget);
    });
  });

  // --- ProfilePage ------------------------------------------------------------

  group('ProfilePage', () {
    for (final Size size in _sizes) {
      testWidgets('changes the address only once the code from it is entered '
          '(${size.width.toInt()}x${size.height.toInt()})', (WidgetTester tester) async {
        await tester.runAsync(() => install());
        String email = 'ada@example.com';
        String? pending;
        backend.routes['GET /auth/account'] = (_) => _json(200, <String, Object?>{
              'account': <String, Object?>{
                'id': 'local_1',
                'email': email,
                if (pending != null) 'pendingEmail': pending,
              },
            });
        backend.routes['POST /auth/account/email'] = (DVHttpRequest request) {
          pending = (jsonDecode(utf8.decode(request.body)) as Map)['email'] as String;
          return _json(202, <String, Object?>{'pendingEmail': pending});
        };
        backend.routes['POST /auth/account/email/verify'] = (_) {
          email = pending!;
          pending = null;
          return _json(200, <String, Object?>{
            'account': <String, Object?>{'id': 'local_1', 'email': email},
            'session': _session('ses_rotated'),
            'token': _rotated,
          });
        };
        await pump(tester, DV.Auth.ProfilePage(), size);
        expect(find.text('ada@example.com'), findsOneWidget);

        await tester.enterText(
            find.byKey(const ValueKey<String>('dv-profile-new-email')), 'ada@new.example');
        await tester.tap(find.byKey(const ValueKey<String>('dv-profile-change-email')));
        await settle(tester);
        expect(backend.bodyOf('POST /auth/account/email'),
            <String, Object?>{'email': 'ada@new.example'});
        final DVText current = tester.widget<DVText>(find.descendant(
            of: find.byKey(const ValueKey<String>('dv-profile-email')),
            matching: find.byType(DVText)));
        expect(current.text, 'ada@example.com');
        expect(find.byKey(const ValueKey<String>('dv-profile-pending')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.enterText(
            find.byKey(const ValueKey<String>('dv-profile-email-code')), '123456');
        await tester.tap(find.byKey(const ValueKey<String>('dv-profile-verify-email')));
        await settle(tester);
        expect(DV.Session.id, 'ses_rotated');
        final DVText changed = tester.widget<DVText>(find.descendant(
            of: find.byKey(const ValueKey<String>('dv-profile-email')),
            matching: find.byType(DVText)));
        expect(changed.text, 'ada@new.example');
        expect(find.byKey(const ValueKey<String>('dv-profile-pending')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // --- DeletePage -------------------------------------------------------------

  group('DeletePage', () {
    for (final Size size in _sizes) {
      testWidgets('sends nothing until the confirmation is typed and the '
          'password given, then signs out '
          '(${size.width.toInt()}x${size.height.toInt()})', (WidgetTester tester) async {
        await tester.runAsync(() => install());
        backend.routes['GET /auth/factors'] =
            (_) => _json(200, <String, Object?>{'totp': false, 'recoveryCodes': 0});
        backend.routes['POST /auth/account/delete'] =
            (_) => _json(200, <String, Object?>{'deleted': true, 'erasure': null});
        await pump(tester, DV.Auth.DeletePage(), size);
        expect(find.byKey(const ValueKey<String>('dv-delete-code')), findsNothing);

        await tester.enterText(
            find.byKey(const ValueKey<String>('dv-delete-password')), 'correct horse');
        await tester.tap(find.byKey(const ValueKey<String>('dv-delete-submit')));
        await settle(tester);
        expect(backend.paths, isNot(contains('POST /auth/account/delete')));
        expect(find.byKey(const ValueKey<String>('dv-delete-error')), findsOneWidget);

        await tester.enterText(
            find.byKey(const ValueKey<String>('dv-delete-confirm-text')), 'DELETE');
        await tester.enterText(find.byKey(const ValueKey<String>('dv-delete-password')), '');
        await tester.tap(find.byKey(const ValueKey<String>('dv-delete-submit')));
        await settle(tester);
        expect(backend.paths, isNot(contains('POST /auth/account/delete')));

        await tester.enterText(
            find.byKey(const ValueKey<String>('dv-delete-password')), 'correct horse');
        await tester.tap(find.byKey(const ValueKey<String>('dv-delete-submit')));
        await settle(tester);
        expect(backend.bodyOf('POST /auth/account/delete'), <String, Object?>{
          'password': 'correct horse',
          'confirm': true,
        });
        expect(DV.Session.current, isNull);
        expect(find.byKey(const ValueKey<String>('dv-delete-done')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an account with an authenticator is asked for a code too',
        (WidgetTester tester) async {
      await tester.runAsync(() => install());
      backend.routes['GET /auth/factors'] =
          (_) => _json(200, <String, Object?>{'totp': true, 'recoveryCodes': 4});
      backend.routes['POST /auth/account/delete'] =
          (_) => _json(200, <String, Object?>{'deleted': true, 'erasure': null});
      await pump(tester, DV.Auth.DeletePage(), const Size(800, 600));
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-delete-confirm-text')), 'DELETE');
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-delete-password')), 'correct horse');
      await tester.tap(find.byKey(const ValueKey<String>('dv-delete-submit')));
      await settle(tester);
      expect(backend.paths, isNot(contains('POST /auth/account/delete')));
      await tester.enterText(find.byKey(const ValueKey<String>('dv-delete-code')), '111222');
      await tester.tap(find.byKey(const ValueKey<String>('dv-delete-submit')));
      await settle(tester);
      expect(backend.bodyOf('POST /auth/account/delete')['code'], '111222');
      expect(DV.Session.current, isNull);
    });

    testWidgets('a refused deletion keeps the person signed in',
        (WidgetTester tester) async {
      await tester.runAsync(() => install());
      backend.routes['GET /auth/factors'] =
          (_) => _json(200, <String, Object?>{'totp': false, 'recoveryCodes': 0});
      backend.routes['POST /auth/account/delete'] = (_) =>
          _json(400, <String, Object?>{'error': 'invalid_credentials', 'message': 'x'});
      await pump(tester, DV.Auth.DeletePage(), const Size(800, 600));
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-delete-confirm-text')), 'DELETE');
      await tester.enterText(
          find.byKey(const ValueKey<String>('dv-delete-password')), 'wrong');
      await tester.tap(find.byKey(const ValueKey<String>('dv-delete-submit')));
      await settle(tester);
      expect(DV.Session.id, 'ses_here');
      expect(find.byKey(const ValueKey<String>('dv-delete-error')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('dv-delete-done')), findsNothing);
    });
  });
}

/// Lets the recording backend's futures complete, then settles the frames.
Future<void> settle(WidgetTester tester) async {
  for (int i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
  }
}
