// Startup, measured.
//
// An embedded device's startup is a number somebody has to answer for: a
// kiosk that takes eleven seconds to show its first screen is a fault, and
// "it feels slow" is not a report. The framework marks the phases it goes
// through and the profile is what they took, in the order they happened,
// from one monotonic clock -- deterministic, so two runs of the same build
// are comparable and a regression is visible rather than argued about.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// A clock the test moves by hand, so a duration is a fact rather than
/// whatever the machine was doing.
class Clock {
  int micros = 0;
  int read() => micros;
}

void main() {
  late Clock clock;
  late DVStartupProfile profile;

  setUp(() {
    clock = Clock();
    profile = DVStartupProfile(nowMicros: clock.read);
  });

  test('a phase is the time between the marks that bound it', () {
    clock.micros = 1000;
    profile.mark('engine');
    clock.micros = 4000;
    profile.mark('bindings');
    clock.micros = 9000;
    profile.mark('first frame');

    expect(profile.phases.map((DVStartupPhase p) => p.name), <String>['engine', 'bindings', 'first frame']);
    expect(profile.phases[0].elapsed, const Duration(milliseconds: 1));
    expect(profile.phases[1].elapsed, const Duration(milliseconds: 3));
    expect(profile.phases[2].elapsed, const Duration(milliseconds: 5));
  });

  test('the total is from the start to the last mark, not the sum of guesses', () {
    clock.micros = 2500;
    profile.mark('engine');
    clock.micros = 7500;
    profile.mark('first frame');

    expect(profile.total, const Duration(milliseconds: 7, microseconds: 500));
  });

  test('a phase marked twice is the second one, not two of the same name', () {
    // A hot restart runs the same marks again; two "first frame" phases in
    // one profile is a report nobody can read.
    clock.micros = 1000;
    profile.mark('first frame');
    clock.micros = 5000;
    profile.mark('first frame');

    expect(profile.phases, hasLength(1));
    expect(profile.phases.single.elapsed, const Duration(milliseconds: 5));
    expect(profile.phases.single.at, const Duration(milliseconds: 5));
  });

  test('the report is stable, so two runs are comparable', () {
    clock.micros = 1000;
    profile.mark('engine');
    clock.micros = 3000;
    profile.mark('first frame');

    final Map<String, Object?> json = profile.toJson();

    expect(json['totalMicros'], 3000);
    expect(json['phases'], <Object?>[
      <String, Object?>{'name': 'engine', 'atMicros': 1000, 'elapsedMicros': 1000},
      <String, Object?>{'name': 'first frame', 'atMicros': 3000, 'elapsedMicros': 2000},
    ]);
    // Ordered by when they happened, which is what makes two runs
    // comparable line by line.
    expect(jsonEncode(json), jsonEncode(profile.toJson()));
  });

  test('nothing marked is an empty profile, not a zero-length lie', () {
    expect(profile.phases, isEmpty);
    expect(profile.total, Duration.zero);
    expect(profile.toJson()['phases'], isEmpty);
  });

  test('a budget says which phase went over, and by how much', () {
    // The number to act on: a startup budget nobody can attribute is a
    // number people learn to ignore.
    clock.micros = 1000;
    profile.mark('engine');
    clock.micros = 9000;
    profile.mark('first frame');

    final List<DVStartupFinding> findings =
        profile.over(const Duration(milliseconds: 5), phaseBudget: const Duration(milliseconds: 4));

    expect(findings.map((DVStartupFinding f) => f.name), <String>['first frame', 'startup']);
    expect(findings.first.by, const Duration(milliseconds: 4));
    expect(findings.last.by, const Duration(milliseconds: 4));
  });

  test('inside the budget there is nothing to report', () {
    clock.micros = 1000;
    profile.mark('first frame');

    expect(profile.over(const Duration(seconds: 1)), isEmpty);
  });

  test('the framework has one profile, since startup happens once', () {
    DVStartupProfile.current.reset();
    DVStartupProfile.current.mark('engine');

    expect(DVStartupProfile.current.phases.map((DVStartupPhase p) => p.name), <String>['engine']);
  });
}
