// Studio's sign-in is a page of the Studio app, not a page of the server's.
//
// Opened at <mount>/login, DVStudioApp draws the sign-in: the application's
// own accounts, answered at the mount, the second factor when the account
// has one, and then Studio itself -- loaded from the server, because the
// page it goes to is the server's to decide on the Studio.access grant.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Server {
  _Server({this.mfa = false, this.granted = true});

  final bool mfa;
  bool granted;
  final List<String> calls = <String>[];

  Future<DVStudioReply> call(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    final Map<String, Object?> json =
        body is Map ? body.cast<String, Object?>() : const <String, Object?>{};
    switch ('$method $path') {
      case 'POST api/auth/sign-in':
        if (json['email'] != 'ops@example.com' ||
            json['password'] != 'a-long-enough-password-1') {
          return const DVStudioReply(400, <String, Object?>{
            'error': 'invalid_credentials',
            'message': 'That email and password do not match.',
          });
        }
        return DVStudioReply(200, <String, Object?>{'mfaRequired': mfa});
      case 'POST api/auth/second-factor':
        return json['code'] == '123456'
            ? const DVStudioReply(200, <String, Object?>{})
            : const DVStudioReply(400, <String, Object?>{'error': 'invalid_code'});
      case 'GET api/access':
        return DVStudioReply(200, <String, Object?>{'granted': granted});
    }
    return const DVStudioReply(404, <String, Object?>{});
  }
}

Future<List<String>> _open(WidgetTester tester, _Server server,
    {String url = 'https://shop.example/__studio/login?from=/__studio/data',
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

Future<void> _signIn(WidgetTester tester, String password) async {
  await tester.enterText(
      find.byKey(const ValueKey<String>('dv-studio-sign-in-email')),
      'ops@example.com');
  await tester.enterText(
      find.byKey(const ValueKey<String>('dv-studio-sign-in-password')), password);
  await tester.tap(find.byKey(const ValueKey<String>('dv-studio-sign-in-submit')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Tab reaches sign in and Enter activates it', (tester) async {
    final server = _Server();
    final opened = await _open(tester, server);
    await tester.enterText(find.byKey(const ValueKey('dv-studio-sign-in-email')),
        'ops@example.com');
    await tester.enterText(find.byKey(const ValueKey('dv-studio-sign-in-password')),
        'a-long-enough-password-1');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, ['/__studio/data']);
  });

  testWidgets('password submit action signs in', (tester) async {
    final server = _Server();
    final opened = await _open(tester, server);
    await tester.enterText(find.byKey(const ValueKey('dv-studio-sign-in-email')),
        'ops@example.com');
    await tester.enterText(find.byKey(const ValueKey('dv-studio-sign-in-password')),
        'a-long-enough-password-1');
    await tester.testTextInput.receiveAction(.done);
    await tester.pumpAndSettle();
    expect(opened, ['/__studio/data']);
  });

  testWidgets('at <mount>/login the app draws its sign-in, not the dashboard',
      (WidgetTester tester) async {
    await _open(tester, _Server());
    expect(find.text('Sign in to Studio'), findsOneWidget);
    expect(find.byType(DVStudioScreen), findsNothing);
  });

  testWidgets('signing in opens where it was going, from the server',
      (WidgetTester tester) async {
    final _Server server = _Server();
    final List<String> opened = await _open(tester, server);
    await _signIn(tester, 'a-long-enough-password-1');
    expect(server.calls, <String>['POST api/auth/sign-in', 'GET api/access']);
    expect(opened, <String>['/__studio/data']);
  });

  testWidgets('a wrong password says so and opens nothing',
      (WidgetTester tester) async {
    final List<String> opened = await _open(tester, _Server());
    await _signIn(tester, 'wrong-password-here');
    expect(find.text('That email and password do not match an account.'),
        findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('an account with a second factor is asked for its code',
      (WidgetTester tester) async {
    final _Server server = _Server(mfa: true);
    final List<String> opened = await _open(tester, server);
    await _signIn(tester, 'a-long-enough-password-1');
    expect(opened, isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey<String>('dv-studio-sign-in-code')), '123456');
    await tester.tap(find.byKey(const ValueKey<String>('dv-studio-sign-in-submit')));
    await tester.pumpAndSettle();
    expect(server.calls.last, 'GET api/access');
    expect(opened, <String>['/__studio/data']);
  });

  testWidgets('signed in without a grant, it says the account may not open '
      'Studio', (WidgetTester tester) async {
    final List<String> opened = await _open(tester, _Server(granted: false));
    await _signIn(tester, 'a-long-enough-password-1');
    expect(find.text('This account may not open Studio.'), findsOneWidget);
    expect(opened, isEmpty);
  });

  testWidgets('a from outside the mount goes to Studio\'s front page instead',
      (WidgetTester tester) async {
    for (final String from in <String>[
      'https://evil.example/x',
      '//evil.example',
      '/account',
      '/__studio/login',
    ]) {
      final List<String> opened = await _open(tester, _Server(),
          url: 'https://shop.example/__studio/login?from=${Uri.encodeQueryComponent(from)}');
      await _signIn(tester, 'a-long-enough-password-1');
      expect(opened, <String>['/__studio/'], reason: from);
    }
  });

  testWidgets('it follows a moved mount', (WidgetTester tester) async {
    final List<String> opened = await _open(tester, _Server(),
        url: 'https://shop.example/ops/desk/login?from=/ops/desk/data');
    await _signIn(tester, 'a-long-enough-password-1');
    expect(opened, <String>['/ops/desk/data']);
  });

  testWidgets('it fits a phone', (WidgetTester tester) async {
    await _open(tester, _Server(), size: const Size(390, 844));
    expect(find.text('Sign in to Studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the app with no session never builds a section',
      (WidgetTester tester) async {
    for (final String url in <String>[
      'https://shop.example/__studio/index.html',
      'https://shop.example/__studio/index.html#/data',
      'https://shop.example/__studio/anything',
      'https://shop.example/__studio/',
    ]) {
      final _Server server = _Server(granted: false);
      await _open(tester, server, url: url);
      expect(find.byType(DVStudioScreen), findsNothing, reason: url);
      expect(find.byKey(const ValueKey<String>('dv-studio-pages')), findsNothing,
          reason: url);
      expect(find.text('Sign in to Studio'), findsOneWidget, reason: url);
    }
  });

  test('a sign-in returns only inside the mount, or inside another mount '
      'Studio guards and names', () {
    const List<String> also = <String>['/docs'];
    expect(dvStudioSignInTarget('/__studio', '/docs/models', also: also),
        '/docs/models');
    expect(dvStudioSignInTarget('/__studio', '/docs', also: also), '/docs');
    for (final String from in <String>[
      '/docsx',
      '/account',
      '//evil.example/docs',
      '/docs/..\\evil',
    ]) {
      expect(dvStudioSignInTarget('/__studio', from, also: also), '/__studio/',
          reason: from);
    }
    // Nothing is named unless somebody names it.
    expect(dvStudioSignInTarget('/__studio', '/docs/models'), '/__studio/');
  });
}
