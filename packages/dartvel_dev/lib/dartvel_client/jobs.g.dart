// GENERATED CODE - DO NOT MODIFY BY HAND
//
// The server half of the jobs: the generated backend imports
// this, and a server has no dart:ui, so nothing reachable from
// it imports Flutter. The handlers only a Flutter process can
// run are in client_jobs.g.dart.
// ignore_for_file: non_constant_identifier_names, unused_element, unused_import, unnecessary_import

import 'package:dartvel_core/dartvel.dart';

/// Queue names declared by @DVJob annotations.
class DVJobQueues {
  const DVJobQueues._();
  static const String defaultQueue = 'default';
}

/// The jobs whose handler only a Flutter process can run, and
/// why. A server registers no handler for them, and a worker
/// names them rather than dead-lettering them in silence.
const Map<String, String> dartvelClientOnlyJobHandlers = <String, String>{};

/// Registers every generated job codec, and the handlers a
/// server can run.
///
/// Called by the generated backend in every role, so a job a
/// web process dispatches can be encoded and a worker can run
/// it, and by the client through registerDartvelClientJobs.
void registerDartvelJobs() {
}
