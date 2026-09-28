// GENERATED CODE - DO NOT MODIFY BY HAND

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';

/// The name mail about a person's account is sent under.
const String dartvelAccountAppName = 'dartvel_dev';

/// How long a deleted account waits before it is erased --
/// `dartvel.auth.deletionGraceDays`. Signing in within it cancels the
/// deletion. Zero erases at once.
const Duration dartvelAccountDeletionGrace = Duration(days: 0);

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
      subject: 'Confirm your new e-mail address for $dartvelAccountAppName',
      text: 'Enter this code in $dartvelAccountAppName to confirm this address '
          'for your account:\n\n'
          '${verification.code}\n\n'
          'It works once, for ${verification.validFor.inMinutes} minutes. If '
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
/// process that ticks the schedules.
///
/// Started with no window as well. A deletion a person asked for under a
/// window the project has since removed is still scheduled, for the erasesAt
/// they were given, and a sweep that only ran while a window was declared
/// would keep their account for ever. With nothing scheduled a tick finds
/// nothing and does nothing.
Timer dartvelStartAccountDeletionSweep({required Duration every}) =>
    Timer.periodic(every, (Timer _) {
      unawaited(DVAuthEndpoints.eraseDueDeletions());
    });
