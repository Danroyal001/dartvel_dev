import 'dart:io';

import 'package:path/path.dart' as p;

/// The signed-in person's account, as the generated application serves it:
/// `account.g.dart`, which the generated server installs from.
///
/// It imports only dartvel_core, because the generated server imports it and
/// a Flutter import would compile Flutter into a process with no dart:ui.
class AccountGenerator {
  const AccountGenerator._();

  /// Every prebuilt account page, in the order navigation lists them, with
  /// the path it is served at unless `dartvel.auth.pages` says otherwise.
  static const List<AccountPageRoute> defaults = <AccountPageRoute>[
    AccountPageRoute('profile', 'ProfilePage', '/account/profile', requiresSession: true),
    AccountPageRoute('security', 'SecurityPage', '/account/security', requiresSession: true),
    AccountPageRoute('sessions', 'SessionsPage', '/account/sessions', requiresSession: true),
    AccountPageRoute('delete', 'DeletePage', '/account/delete', requiresSession: true),
    AccountPageRoute('signUp', 'SignUpPage', '/sign-up', requiresSession: false),
  ];

  /// Paths the generated router or runtime already means something else by:
  /// the second-factor challenge, the OAuth consent page and sign-in, where a
  /// page behind sign-in would redirect to itself.
  static const List<String> reserved = <String>[
    '/second-factor',
    '/oauth/consent',
    '/login',
  ];

  /// The erasure deadline a deletion window has to fit inside: Data
  /// Compliance's thirty days, measured from when the person asked.
  static const int erasureDeadlineDays = 30;

  /// How long `dartvel.auth.deletionGraceDays` in [dv] says a deleted account
  /// waits before it is erased. Nothing declared is no window.
  ///
  /// Throws [StateError] naming the key for anything but a whole number of
  /// days from 0 to 29. A window reaching the erasure's thirty-day deadline
  /// would put every account erasure past it (DV-PRIVACY-004) by
  /// construction.
  static Duration readDeletionGrace(Map<Object?, Object?> dv) {
    final Object? auth = dv['auth'];
    if (auth is! Map || !auth.containsKey('deletionGraceDays')) {
      return Duration.zero;
    }
    final Object? days = auth['deletionGraceDays'];
    if (days is! int || days < 0) {
      throw StateError('dartvel.auth.deletionGraceDays must be a whole number '
          'of days, 0 or more, not "$days".');
    }
    if (days >= erasureDeadlineDays) {
      throw StateError('dartvel.auth.deletionGraceDays is $days, and an '
          'account erasure has a $erasureDeadlineDays-day deadline from when '
          'the person asked (DV-PRIVACY-004): a window that long puts every '
          'erasure past it. Use ${erasureDeadlineDays - 1} or fewer.');
    }
    return Duration(days: days);
  }

  /// The account pages `dartvel.auth.pages` in [dv] asks to be served.
  ///
  /// Nothing declared serves every page at its default path. `pages: false`
  /// serves none; a page set to `false` is left out; a page set to a path is
  /// served there. Throws [StateError] naming the key for anything else --
  /// a misspelt page, a path that is not one, a parameter, two pages at one
  /// path, a path the router already uses -- because each would otherwise be
  /// skipped into a route the application believes it configured.
  static List<AccountPageRoute> readPages(Map<Object?, Object?> dv) {
    final Object? auth = dv['auth'];
    if (auth != null && auth is! Map) {
      throw StateError('dartvel.auth must be a map, not "$auth".');
    }
    final Object? declared = auth is Map ? auth['pages'] : null;
    if (declared == null) return defaults;
    if (declared == false) return const <AccountPageRoute>[];
    if (declared is! Map) {
      throw StateError('dartvel.auth.pages must be false or a map of account '
          'pages to paths (${defaults.map((AccountPageRoute r) => r.key).join(', ')}), '
          'not "$declared".');
    }
    final Set<String> known = <String>{
      for (final AccountPageRoute r in defaults) r.key,
    };
    for (final Object? key in declared.keys) {
      if (!known.contains(key)) {
        throw StateError('dartvel.auth.pages.$key is not an account page. '
            'The pages are ${known.join(', ')}.');
      }
    }
    final List<AccountPageRoute> out = <AccountPageRoute>[];
    final Map<String, String> claimed = <String, String>{};
    for (final AccountPageRoute page in defaults) {
      if (!declared.containsKey(page.key)) {
        out.add(page);
        claimed[page.path] = page.key;
        continue;
      }
      final Object? value = declared[page.key];
      if (value == false) continue;
      final String key = 'dartvel.auth.pages.${page.key}';
      if (value is! String) {
        throw StateError('$key must be a path such as ${page.path}, or false '
            'to leave the page out, not "$value".');
      }
      final String path = value.trim();
      if (!RegExp(r'^/[A-Za-z0-9._~/-]*$').hasMatch(path) || path.contains('//')) {
        throw StateError('$key must be a path starting with / and made of '
            'letters, digits, ".", "_", "~", "-" and "/", not "$value". A '
            'route parameter or a query has no meaning for an account page.');
      }
      if (reserved.contains(path)) {
        throw StateError('$key is $path, which the generated application '
            'already serves something else at.');
      }
      final String? other = claimed[path];
      if (other != null) {
        throw StateError('dartvel.auth.pages.$other and $key are both $path; '
            'one route cannot serve two pages.');
      }
      claimed[path] = page.key;
      out.add(AccountPageRoute(page.key, page.widget, path,
          requiresSession: page.requiresSession));
    }
    // A default path another page was moved onto is two pages at one path
    // too, and is only visible once every page is placed.
    final Map<String, String> seen = <String, String>{};
    for (final AccountPageRoute page in out) {
      final String? other = seen[page.path];
      if (other != null) {
        throw StateError('dartvel.auth.pages.$other and '
            'dartvel.auth.pages.${page.key} are both ${page.path}; one route '
            'cannot serve two pages.');
      }
      seen[page.path] = page.key;
    }
    return out;
  }

  /// Writes `lib/dartvel_client/account.g.dart` for the application called
  /// [appName] -- the name a person sees in the subject of mail it sends --
  /// with the deletion window [deletionGrace].
  static void generate({
    required String root,
    required String appName,
    Duration deletionGrace = Duration.zero,
  }) {
    final Directory out = Directory(p.join(root, 'lib', 'dartvel_client'))
      ..createSync(recursive: true);
    File(p.join(out.path, 'account.g.dart')).writeAsStringSync(
        render(appName: appName, deletionGrace: deletionGrace));
  }

  /// The source of `account.g.dart`.
  static String render({
    required String appName,
    Duration deletionGrace = Duration.zero,
  }) {
    final String name = _literal(appName);
    return '''
// GENERATED CODE - DO NOT MODIFY BY HAND

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';

/// The name mail about a person's account is sent under.
const String dartvelAccountAppName = $name;

/// How long a deleted account waits before it is erased --
/// `dartvel.auth.deletionGraceDays`. Signing in within it cancels the
/// deletion. Zero erases at once.
const Duration dartvelAccountDeletionGrace = Duration(days: ${deletionGrace.inDays});

/// The mail that carries the code confirming a new e-mail address, as the
/// generated server sends it through `DV.Notifications.mail`.
///
/// Sent only to the address being confirmed. The code is in the body and
/// nowhere else -- not the subject, which mail clients show in notifications
/// and lists. Replace it with
/// `DVAuthEndpoints.install(emailVerificationMail: ...)`.
DVMailMessage dartvelEmailVerificationMail(DVEmailVerification verification) =>
    DVMailMessage(
      from: verification.from,
      to: <DVMailAddress>[DVMailAddress(verification.to)],
      subject: 'Confirm your new e-mail address for \$dartvelAccountAppName',
      text: 'Enter this code in \$dartvelAccountAppName to confirm this address '
          'for your account:\\n\\n'
          '\${verification.code}\\n\\n'
          'It works once, for \${verification.validFor.inMinutes} minutes. If '
          'you did not ask to change your address, ignore this message: '
          'nothing changes until the code is entered.',
    );

/// Installs what the generated server gives the account endpoints: the
/// verification mail, the deletion window, and the job that erases an
/// account once its window closes.
void configureDartvelBackendAccounts() {
  DVAuthEndpoints.useGeneratedEmailVerificationMail(dartvelEmailVerificationMail);
  DVAuthEndpoints.useDeletionGracePeriod(dartvelAccountDeletionGrace);
  // Only with a window: a worker with no job of the application's own to
  // run still refuses to start.
  if (dartvelAccountDeletionGrace > Duration.zero) {
    DVAuthEndpoints.registerAccountErasureJob();
  }
}

/// Erases the accounts whose deletion window has closed, every [every], in a
/// process that ticks the schedules. Null when there is no window, since a
/// deletion then erases at once.
Timer? dartvelStartAccountDeletionSweep({required Duration every}) =>
    dartvelAccountDeletionGrace == Duration.zero
        ? null
        : Timer.periodic(every, (Timer _) {
            unawaited(DVAuthEndpoints.eraseDueDeletions());
          });
''';
  }

  static String _literal(String value) =>
      "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n')}'";
}

/// Where one prebuilt account page is served.
class AccountPageRoute {
  const AccountPageRoute(this.key, this.widget, this.path,
      {required this.requiresSession});

  /// The page's name under `dartvel.auth.pages`, and its `DVAccountPage`.
  final String key;

  /// The `DV.Auth` member that builds it.
  final String widget;

  final String path;

  /// Whether the route is behind `DVAccountPages.requireSession`.
  final bool requiresSession;
}
