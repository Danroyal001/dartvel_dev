/// The mail the account endpoints send: the code that proves a new address
/// receives mail.
library dartvel_core.auth.account_mail;

import '../../dartvel.dart' show DVMailAddress, DVMailMessage;

/// What a verification mail is built from.
class DVEmailVerification {
  const DVEmailVerification({
    required this.from,
    required this.to,
    required this.code,
    required this.validFor,
  });

  /// The configured sender, `DV.Notifications.useMailSender`.
  final DVMailAddress from;

  /// The address being verified -- the new one, never the account's current
  /// address.
  final String to;

  /// The one-time code. Goes in the mail and nowhere else.
  final String code;

  /// How long the code works.
  final Duration validFor;

  @override
  String toString() => 'DVEmailVerification(to: $to)';
}

/// Builds the verification mail.
typedef DVEmailVerificationMail = DVMailMessage Function(
    DVEmailVerification verification);
