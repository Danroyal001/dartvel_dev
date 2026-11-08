// The prebuilt account pages read their words from framework strings.
//
// Error, Empty, and Loading States: the account pages passed English through
// their own helpers -- headings, button labels, refusals -- so an application
// localised into French still said "Sign out" and "Change password". The
// failure is silent: English is a plausible rendering in every locale. These
// tests load a catalogue that renders every account key as its own name and
// check that no English is left, and that the sign-up page still puts each
// refusal under the field it is about once the words are not English (it used
// to decide by looking for "e-mail" in the message).
import 'dart:convert';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/widgets/password_reveal.dart'
    show DVServerFieldState, dvServerField;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _token = 'dvs_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

/// English the account pages showed as literals before they read framework
/// strings. None may appear once every account key has a translation.
const List<String> _english = <String>[
  'Welcome',
  'A place for what matters to you.',
  'Security',
  'Devices',
  'Profile',
  'Delete your account',
  'Set up an authenticator app',
  'Change password',
  'Sign out',
  'Sign out everywhere else',
  'Unknown device',
  'Change email',
  'Delete my account',
  'Create account',
  'Create an account',
  'Already have an account? Sign in',
];

Map<String, Object?> _session(String id, {String? device, bool current = true}) =>
    <String, Object?>{
      'id': id,
      'userId': 'local_1',
      'tenant': 'default',
      'createdAt': '2026-09-15T12:00:00.000Z',
      'lastSeenAt': '2026-09-15T12:30:00.000Z',
      if (device != null) 'device': device,
      'claims': <String, Object?>{},
      'mfaSatisfiedAt': null,
      'isCurrent': current,
    };

DVHttpResponse _json(int status, Object body) =>
    DVHttpResponse(statusCode: status, body: jsonEncode(body));

/// Every account key rendered as «its name», so a word that is not wrapped in
/// guillemets did not come from the catalogue.
DVTranslationCatalog _named() => DVTranslationCatalog(
      locale: LocaleTag.frFR,
      messages: <DVTranslationKey, String>{
        for (final String key in DVFrameworkStrings.defaults.keys)
          if (key.startsWith('dv.account.') || key.startsWith('dv.auth.'))
            DVTranslationKey(key): '«$key»',
      },
    );

List<String> _shownText(WidgetTester tester) => <String>[
      for (final Text text in tester.widgetList<Text>(find.byType(Text)))
        text.data ?? text.textSpan?.toPlainText() ?? '',
      for (final RichText text in tester.widgetList<RichText>(find.byType(RichText)))
        text.text.toPlainText(),
    ];

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pumpAndSettle();
  }
}

void main() {
  final Map<String, DVHttpResponse Function(DVHttpRequest)> routes =
      <String, DVHttpResponse Function(DVHttpRequest)>{};

  Future<void> install({bool signIn = true}) async {
    routes.clear();
    routes['POST /auth/sign-in'] = (_) => _json(200, <String, Object?>{
          'user': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
          'mfaRequired': false,
          'session': _session('ses_here'),
          'token': _token,
        });
    routes['GET /auth/factors'] =
        (_) => _json(200, <String, Object?>{'totp': false, 'recoveryCodes': 0});
    routes['GET /auth/sessions'] = (_) => _json(200, <String, Object?>{
          'sessions': <Map<String, Object?>>[
            _session('ses_here'),
            _session('ses_other', current: false),
          ],
        });
    routes['GET /auth/account'] = (_) => _json(200, <String, Object?>{
          'account': <String, Object?>{'id': 'local_1', 'email': 'ada@example.com'},
        });
    final DVSessionClient client = DVSessionClient(
      api: (String path) => Uri.parse('https://app.example.test/api$path'),
      tokens: DVMemorySessionTokenStore(),
      web: false,
      send: (DVHttpRequest request) async {
        final String path = request.url.path.replaceFirst('/api', '');
        final DVHttpResponse Function(DVHttpRequest)? route =
            routes['${request.method} $path'];
        return route == null
            ? _json(404, <String, Object?>{'error': 'not_found'})
            : route(request);
      },
    );
    DVSessionClient.install(client);
    DVAuth.installDefaultProvider(DVSessionAuthProvider(client));
    if (signIn) {
      await DV.Auth.signInWithEmailAndPassword(
          email: 'ada@example.com', password: 'correct horse');
    }
  }

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: page)));
    await _settle(tester);
  }

  setUp(() {
    DV.I18n.load(_named());
    DV.I18n.useLocale(LocaleTag.frFR);
  });

  tearDown(() {
    DV.I18n.reset();
    DVSessionClient.uninstall();
    DV.Test.resetAuthProvider();
  });

  final Map<String, Widget Function()> pages = <String, Widget Function()>{
    'SecurityPage': () => DV.Auth.SecurityPage(),
    'SessionsPage': () => DV.Auth.SessionsPage(),
    'SignUpPage': () => DV.Auth.SignUpPage(),
    'ProfilePage': () => DV.Auth.ProfilePage(),
    'DeletePage': () => DV.Auth.DeletePage(),
  };

  for (final MapEntry<String, Widget Function()> page in pages.entries) {
    testWidgets('${page.key} shows no English once every account key is '
        'translated', (WidgetTester tester) async {
      await tester.runAsync(() => install(signIn: page.key != 'SignUpPage'));
      await pump(tester, page.value());
      final List<String> shown = _shownText(tester);
      expect(shown.where((String s) => s.contains('«dv.')), isNotEmpty,
          reason: 'the page read nothing from the catalogue: $shown');
      for (final String english in _english) {
        expect(shown.where((String s) => s == english || s.contains('$english ')),
            isEmpty,
            reason: '"$english" is still a literal on ${page.key}: $shown');
      }
    });
  }

  testWidgets('an address typed into the server-rendered form is kept in any '
      'language', (WidgetTester tester) async {
    // The page matches the server's field by its label, and the label is
    // translated: looking it up by the English word lost what was typed.
    addTearDown(() => dvServerField = (String _) => null);
    dvServerField = (String label) =>
        label == '«dv.auth.email»'
            ? const DVServerFieldState(value: 'ada@example.com', revealed: false)
            : null;
    await tester.runAsync(() => install(signIn: false));
    await pump(tester, DV.Auth.SignUpPage());
    final TextField email = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('dv-signup-email')));
    expect(email.controller?.text, 'ada@example.com');
  });

  testWidgets('a refused address is reported under the address field in any '
      'language', (WidgetTester tester) async {
    await tester.runAsync(() => install(signIn: false));
    routes['POST /auth/sign-up'] =
        (_) => _json(422, <String, Object?>{'error': 'invalid_email'});
    await pump(tester, DV.Auth.SignUpPage());
    await tester.enterText(find.byKey(const ValueKey<String>('dv-signup-email')), 'ada@');
    await tester.enterText(
        find.descendant(
            of: find.byKey(const ValueKey<String>('dv-signup-password')),
            matching: find.byType(EditableText)),
        'a long enough password');
    await tester.tap(find.byKey(const ValueKey<String>('dv-signup-submit')));
    await _settle(tester);

    final TextField email = tester.widget<TextField>(
        find.byKey(const ValueKey<String>('dv-signup-email')));
    expect(email.decoration?.errorText, isNotNull,
        reason: 'the address refusal went to another field');
    expect(email.decoration!.errorText, contains('«dv.'));
    final Iterable<TextField> password = tester.widgetList<TextField>(find.descendant(
        of: find.byKey(const ValueKey<String>('dv-signup-password')),
        matching: find.byType(TextField)));
    for (final TextField field in password) {
      expect(field.decoration?.errorText, isNull,
          reason: 'an address refusal was shown under the password');
    }
  });
}
