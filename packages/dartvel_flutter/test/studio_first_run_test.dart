// The first-run setup is a page of the Studio app, at <mount>/setup, not a
// page of the server's.
//
// The application printed an owner's address and password on its first run.
// Until that owner has replaced the password and turned on a second factor
// the mount answers nothing but that page, so the page has to render before
// anybody has signed in and before the project itself may be touched. It is
// the Studio app drawing that page, driving the application's own four auth
// endpoints at the mount, and it names nobody: the address and the password
// are asked for, not printed, because the page is open to the internet by
// definition.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The address and password the application printed, and the second factor
/// it will accept. A stand-in for the credential guard, not a second copy of
/// one: what it refuses is what the page has to answer.
const String _printed = 'the-password-it-printed-1';
const String _chosen = 'the-password-they-chose-1';
const String _secret = 'JBSWYC3DPEHPK3PXP';

class _Server {
  _Server({
    this.secondFactor = false,
    this.enrolment = 200,
    this.changed = 200,
    this.changedMessage,
  });

  /// The account already has an authenticator, which a pending setup says it
  /// cannot have.
  final bool secondFactor;

  /// The status `api/auth/factors/totp` answers: a provider that is not
  /// configured, a second factor already on, a network that went away.
  final int enrolment;

  /// The status `api/auth/account/password` answers.
  final int changed;
  final String? changedMessage;

  /// The password has been replaced, so the printed one no longer stands.
  bool standingChosen = false;

  final List<String> calls = <String>[];
  final List<String> reads = <String>[];

  Future<DVStudioReply> call(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    final Map<String, Object?> json =
        body is Map ? body.cast<String, Object?>() : const <String, Object?>{};
    switch ('$method $path') {
      case 'POST api/auth/sign-in':
        // Which password stands: the printed one until it is changed, and the
        // chosen one after, because that is what the credential guard answers.
        final String standing =
            json['password'] == _printed && !standingChosen ? _printed : _chosen;
        if (json['email'] != 'owner@example.com' || json['password'] != standing) {
          return const DVStudioReply(400, <String, Object?>{
            'error': 'invalid_credentials',
          });
        }
        return DVStudioReply(200,
            <String, Object?>{'mfaRequired': secondFactor});
      case 'POST api/auth/account/password':
        if (changed == 200) standingChosen = true;
        if (changed != 200) {
          return DVStudioReply(changed, <String, Object?>{
            if (changedMessage != null) 'message': changedMessage!,
            'error': 'password_refused',
          });
        }
        return const DVStudioReply(200, <String, Object?>{});
      case 'POST api/auth/factors/totp':
        if (enrolment != 200) {
          return DVStudioReply(enrolment, <String, Object?>{
            'error': 'totp_unavailable',
            'message': 'No authenticator is configured on this application.',
          });
        }
        return const DVStudioReply(200, <String, Object?>{
          'secret': _secret,
          'uri': 'otpauth://totp/shop:owner@example.com?secret=$_secret',
        });
      case 'POST api/auth/factors/totp/confirm':
        return json['code'] == '123456'
            ? const DVStudioReply(200, <String, Object?>{})
            : const DVStudioReply(400, <String, Object?>{'error': 'invalid_code'});
    }
    reads.add('$method $path');
    return const DVStudioReply(404, <String, Object?>{});
  }
}

Future<List<String>> _open(WidgetTester tester, _Server server,
    {String url = 'https://shop.example/__studio/setup',
    Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final List<String> opened = <String>[];
  await tester.pumpWidget(DVStudioApp(
    client: DVStudioClient(server.call),
    title: 'Studio · shop',
    location: Uri.parse(url),
    open: opened.add,
  ));
  await tester.pumpAndSettle();
  return opened;
}

Finder _field(String key) => find.byKey(ValueKey<String>('dv-studio-setup-$key'));

Future<void> _type(WidgetTester tester, String key, String value) =>
    tester.enterText(_field(key), value);

Future<void> _submit(WidgetTester tester, String key) async {
  await tester.tap(_field(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('at <mount>/setup the app draws the setup, not the dashboard '
      'and not the sign-in', (WidgetTester tester) async {
    await _open(tester, _Server());
    expect(find.text('Finish setting up'), findsOneWidget);
    expect(find.byType(DVStudioScreen), findsNothing);
    // The sign-in, not this: it asks for an email, and there is none here.
    expect(find.text('Sign in to Studio'), findsNothing);
  });

  testWidgets('it asks for the address and the password rather than printing '
      'them', (WidgetTester tester) async {
    await _open(tester, _Server());
    expect(find.text('The address it printed'), findsOneWidget);
    expect(find.text('The password it printed'), findsOneWidget);
    expect(find.textContaining('owner@example.com'), findsNothing);
    expect(find.textContaining(_printed), findsNothing);
  });

  testWidgets('it reads nothing from the project: the page carries no data and '
      'asks the server for none', (WidgetTester tester) async {
    final _Server server = _Server();
    await _open(tester, server);
    expect(server.calls, isEmpty);
    expect(server.reads, isEmpty);
  });

  testWidgets('the whole setup: the printed password in, the new one set, the '
      'second factor on, Studio open', (WidgetTester tester) async {
    final _Server server = _Server();
    final List<String> opened = await _open(tester, server);
    await _type(tester, 'address', 'owner@example.com');
    await _type(tester, 'password', _printed);
    await _type(tester, 'new-password', _chosen);
    await _submit(tester, 'submit');
    expect(server.calls, <String>[
      'POST api/auth/sign-in',
      'POST api/auth/account/password',
      'POST api/auth/factors/totp',
    ]);
    // The secret the authenticator app needs, from the server and not from
    // anything on this page.
    expect(find.text(_secret), findsOneWidget);
    expect(opened, isEmpty);
    await _type(tester, 'code', '123456');
    await _submit(tester, 'confirm');
    expect(server.calls.last, 'POST api/auth/factors/totp/confirm');
    expect(opened, <String>['/__studio/']);
  });

  testWidgets('a wrong printed password says so, changes nothing and opens '
      'nothing', (WidgetTester tester) async {
    final _Server server = _Server();
    final List<String> opened = await _open(tester, server);
    await _type(tester, 'address', 'owner@example.com');
    await _type(tester, 'password', 'not-the-printed-one');
    await _type(tester, 'new-password', _chosen);
    await _submit(tester, 'submit');
    expect(
        find.text(
            'That is not the address and password this application printed.'),
        findsOneWidget);
    expect(server.calls, <String>['POST api/auth/sign-in']);
    expect(opened, isEmpty);
  });

  testWidgets('a refused new password says what the server said',
      (WidgetTester tester) async {
    final List<String> opened = await _open(
        tester, _Server(changed: 400, changedMessage: 'That is too short.'));
    await _type(tester, 'address', 'owner@example.com');
    await _type(tester, 'password', _printed);
    await _type(tester, 'new-password', 'abc');
    await _submit(tester, 'submit');
    expect(find.text('That is too short.'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('a wrong code says so and opens nothing',
      (WidgetTester tester) async {
    final _Server server = _Server();
    final List<String> opened = await _open(tester, server);
    await _type(tester, 'address', 'owner@example.com');
    await _type(tester, 'password', _printed);
    await _type(tester, 'new-password', _chosen);
    await _submit(tester, 'submit');
    await _type(tester, 'code', '000000');
    await _submit(tester, 'confirm');
    expect(find.text('That code did not match. Try the next one.'),
        findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('an authenticator that will not start says so, and the owner '
      'carries on with the password they just set',
      (WidgetTester tester) async {
    // The half of the setup that cannot be undone: the password is changed
    // and the factor is not, so the printed password is dead and the setup is
    // still pending. A page that only ever asked for the printed one would
    // strand the owner here.
    final _Server server = _Server(enrolment: 503);
    final List<String> opened = await _open(tester, server);
    await _type(tester, 'address', 'owner@example.com');
    await _type(tester, 'password', _printed);
    await _type(tester, 'new-password', _chosen);
    await _submit(tester, 'submit');
    expect(find.text('No authenticator is configured on this application.'),
        findsOneWidget);
    expect(find.text('The password it printed'), findsNothing);
    // The password now standing is the one they chose.
    await _type(tester, 'password', _chosen);
    await _submit(tester, 'submit');
    expect(server.calls.last, 'POST api/auth/factors/totp');
    expect(opened, isEmpty);
  });

  testWidgets('an account that already has a second factor is sent to the '
      'sign-in, not walked into a setup it cannot finish',
      (WidgetTester tester) async {
    final List<String> opened = await _open(tester, _Server(secondFactor: true));
    await _type(tester, 'address', 'owner@example.com');
    await _type(tester, 'password', _printed);
    await _type(tester, 'new-password', _chosen);
    await _submit(tester, 'submit');
    expect(find.textContaining('already'), findsOneWidget);
    expect(opened, <String>['/__studio/login']);
  });

  testWidgets('it follows a moved mount', (WidgetTester tester) async {
    final _Server server = _Server();
    final List<String> opened = await _open(tester, server,
        url: 'https://shop.example/ops/desk/setup');
    await _type(tester, 'address', 'owner@example.com');
    await _type(tester, 'password', _printed);
    await _type(tester, 'new-password', _chosen);
    await _submit(tester, 'submit');
    await _type(tester, 'code', '123456');
    await _submit(tester, 'confirm');
    // Relative to the page, which is served at the mount wherever the project
    // put it.
    expect(server.calls.first, 'POST api/auth/sign-in');
    expect(opened, <String>['/ops/desk/']);
  });

  testWidgets('it fits a phone', (WidgetTester tester) async {
    final List<String> opened = await _open(tester, _Server(),
        size: const Size(390, 844));
    await _type(tester, 'address', 'owner@example.com');
    await _type(tester, 'password', _printed);
    await _type(tester, 'new-password', _chosen);
    await _submit(tester, 'submit');
    await _type(tester, 'code', '123456');
    await _submit(tester, 'confirm');
    expect(tester.takeException(), isNull);
    expect(opened, <String>['/__studio/']);
  });
}
