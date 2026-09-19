import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';
import '../policies/order_policy.dart';

Future<String> askForCode() async => '123456';

Future<void> signIn(String email, String password) async {
  // docs:start auth-sign-in
  try {
    await DV.Auth.signInWithEmailAndPassword(email: email, password: password);
    DV.log('signed in as ${DV.Auth.currentUser?.id}');
  } on DVMfaRequired {
    // The account has a second factor. Ask for the 6-digit code.
    await DV.Auth.completeSecondFactor(code: await askForCode());
  }
  // docs:end
}

Future<void> account() async {
  // docs:start auth-sign-up-out
  await DV.Auth.signUp(email: 'ada@example.com', password: 'a long passphrase');
  final DVAuthUser? me = DV.Auth.currentUser;
  await DV.Auth.signOut();
  // docs:end
  // docs:start auth-totp
  final DVTotpEnrollment enrollment = await DV.Auth.enrollTotp();
  // Show enrollment.uri as a QR code, then confirm with a code from the app.
  await DV.Auth.confirmTotp(await askForCode());
  final DVRecoveryCodes codes = await DV.Auth.regenerateRecoveryCodes();
  // docs:end
  // docs:start auth-sessions
  final List<DVSession> sessions = await DV.Auth.sessions();
  for (final DVSession session in sessions) {
    DV.log('${session.device} last seen ${session.lastSeenAt}');
  }
  await DV.Auth.revoke(sessions.last.id); // sign one device out
  final int signedOut = await DV.Auth.revokeOthers(); // every device but this one
  // docs:end
  DV.log('$me $enrollment $codes $signedOut');
}

// docs:start auth-credentialed-origin
void allowApiOrigin() {
  // Send the session cookie to your API when it is on another origin.
  DVCredentialedOrigins.allowBackend('https://api.example.com');
}
// docs:end

Future<void> checks(Order order) async {
  // docs:start authz-check
  final bool canEdit = await DV.Auth.authorization.canAction(
    DV.Auth.currentUser,
    'Order.update',
    resource: order,
  );
  // docs:end
  // docs:start authz-register
  DV.Auth.authorization.register<DVAuthUser, Article>(
    'Article.publish',
    (DVAuthUser user, Article article) => user.email?.endsWith('@example.com') ?? false,
  );
  // docs:end
  DV.log('$canEdit');
}

/// Mailing somebody a code and checking what they type back.
Future<void> sendCode(String email) async {
  // docs:start auth-code
  // Six digits from a secure random, leading zeros kept.
  final String code = DV.Auth.code();
  // Or a longer one for something that matters more:
  final String payoutCode = DV.Auth.code(length: 8);

  await DV.Notifications.mail.send(DVMailMessage(
    from: const DVMailAddress('hello@example.com', name: 'Shop'),
    to: <DVMailAddress>[DVMailAddress(email)],
    subject: 'Your sign-in code',
    text: 'Type $code to sign in. It is good for ten minutes.',
  ));
  // docs:end
  DV.log('sent ${code.length} digits, and a $payoutCode');
}

/// Asking for the code, over the page or as a page.
Future<void> checkCode(BuildContext context) async {
  // docs:start auth-ask-for-code
  final String? typed = await DV.Auth.askForCode(
    context,
    message: 'We sent a code to ada@example.com.',
    // Answer with what to tell them when it is wrong; null accepts it.
    verify: (String code) async =>
        await confirmCode(code) ? null : 'That code is wrong.',
  );
  // docs:end
  DV.log('$typed');
}

// docs:start auth-ask-for-code-page
@DVPage(title: 'Enter your code')
@pragma('vm:entry-point')
Widget _codePage(BuildContext context) => DV.Auth.AskForCodePage(
      message: 'We sent a code to your address.',
      onCode: (String code) async =>
          await confirmCode(code) ? null : 'That code is wrong.',
    );
// docs:end

/// The backend function that checks it, whatever the project calls it.
Future<bool> confirmCode(String code) async => code.length == 6;
