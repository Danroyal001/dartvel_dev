// GENERATED – do not edit.
// ignore_for_file: unused_element, unused_import, directives_ordering
library dartvel_client_client_schedules;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'schedules.g.dart' show dartvelClientCronEntries;

/// The function behind each client schedule.
///
/// registerAll refuses an entry with no handler rather
/// than skipping it, so a name here that does not match an
/// entry is a startup failure and not a job that quietly
/// never runs.
const Map<String, Future<void> Function()> dartvelClientCronHandlers = <String, Future<void> Function()>{};

/// Registers every client schedule and starts ticking.
///
/// Starts nothing when the application declares none: a
/// timer firing in every application that has no schedule
/// is a cost nobody asked for.
void dartvelStartClientSchedules({
  Duration every = const Duration(seconds: 20),
  bool catchUp = false,
}) {
  // The application declares no client schedule.
}
