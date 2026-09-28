// GENERATED – do not edit.
// ignore_for_file: unused_element, directives_ordering
library dartvel_client_schedules;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart';

const List<DVCronEntry> dartvelCronEntries = <DVCronEntry>[
];

final List<DVCronEntry> dartvelBackendCronEntries = List<DVCronEntry>.unmodifiable(
  dartvelCronEntries.where((entry) => entry.target == DVCronTarget.backend),
);

final List<DVCronEntry> dartvelClientCronEntries = List<DVCronEntry>.unmodifiable(
  dartvelCronEntries.where((entry) => entry.target == DVCronTarget.client),
);

/// The function behind each backend schedule.
///
/// registerAll refuses an entry with no handler rather than
/// skipping it, so a name here that does not match an entry
/// is a startup failure and not a job that quietly never
/// runs.
const Map<String, Future<void> Function()> dartvelBackendCronHandlers = <String, Future<void> Function()>{};

/// Registers every backend schedule and starts ticking.
///
/// Returns null when the application declares no backend
/// schedule: a timer firing in every application that has
/// none is a cost nobody asked for.
///
/// The tick interval is shorter than a minute because the
/// finest cron granularity is a minute, and a tick landing
/// a little after the boundary is what keeps a minute
/// schedule from skipping one. Ticking often is safe: a
/// task is keyed to the occurrence it last ran for.
///
/// [lease] is claimed for each occurrence before it runs, so
/// several processes sharing its store run it once between
/// them. [clock] is the time the schedules are read against.
Timer? dartvelStartBackendSchedules({
  Duration every = const Duration(seconds: 20),
  bool catchUp = false,
  DateTime Function()? clock,
  DVScheduleLease? lease,
}) {
  // The application declares no backend schedule.
  return null;
}
