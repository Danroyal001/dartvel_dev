import 'dart:io';

import 'package:path/path.dart' as p;

/// The signed-in person's account, as the generated application serves it:
/// `account.g.dart`, which the generated server installs from.
///
/// It imports only dartvel_core, because the generated server imports it and
/// a Flutter import would compile Flutter into a process with no dart:ui.
class AccountGenerator {
  const AccountGenerator._();

  /// Writes `lib/dartvel_client/account.g.dart` for the application called
  /// [appName] -- the name a person sees in the subject of mail it sends.
  static void generate({required String root, required String appName}) {
    final Directory out = Directory(p.join(root, 'lib', 'dartvel_client'))
      ..createSync(recursive: true);
    File(p.join(out.path, 'account.g.dart'))
        .writeAsStringSync(render(appName: appName));
  }

  /// The source of `account.g.dart`.
  static String render({required String appName}) {
    final String name = _literal(appName);
    return '''
// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:dartvel_core/dartvel.dart';

/// The name mail about a person's account is sent under.
const String dartvelAccountAppName = $name;

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

/// Installs what the generated server gives the account endpoints.
void configureDartvelBackendAccounts() {
  DVAuthEndpoints.useGeneratedEmailVerificationMail(dartvelEmailVerificationMail);
}
''';
  }

  static String _literal(String value) =>
      "'${value.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$').replaceAll('\n', r'\n')}'";
}
