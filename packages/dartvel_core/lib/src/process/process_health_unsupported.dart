/// [DVProcessHealth] where there are no server sockets.
library;

import 'process_configuration.dart';
import 'process_health.dart';

Future<DVProcessHealth> dvServeProcessHealth({
  required String host,
  required int port,
  required DVProcessRole role,
}) async =>
    throw UnsupportedError(
      'A health endpoint needs dart:io server sockets, which this target does '
      'not have. It is served by a backend worker or cron process.',
    );
