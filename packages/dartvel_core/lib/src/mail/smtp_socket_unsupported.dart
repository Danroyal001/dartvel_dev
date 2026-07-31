/// Web stand-in for the socket-backed SMTP connection.
///
/// SMTP needs raw TCP, which browsers do not expose. Rather than degrade to a
/// no-op that reports success, connecting fails and names the alternative.
library dartvel_core.mail.smtp_socket_unsupported;

import 'smtp_client.dart';

Future<DVSmtpConnection> dvConnectSmtp(
  String host,
  int port, {
  required bool secure,
}) async =>
    throw UnsupportedError(
      'SmtpMailProvider needs raw TCP sockets and is unavailable on this '
      'target. Use one of the HTTP mail providers (Resend, SendGrid, '
      'Postmark, Mailgun, SES) for web builds.',
    );
