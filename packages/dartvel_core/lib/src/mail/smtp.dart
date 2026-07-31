/// SMTP support: the protocol client plus a platform-appropriate connection.
library dartvel_core.mail.smtp;

export 'smtp_client.dart';
export 'smtp_socket_unsupported.dart'
    if (dart.library.io) 'smtp_socket_io.dart';
