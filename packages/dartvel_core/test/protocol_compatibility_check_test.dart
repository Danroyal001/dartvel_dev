// The deploy gate: `dartvel compatibility-check --against production`.
//
// A gate is judged by the deploys it lets through that it should not have.
// Traffic from last month counted as this week's, a threshold compared with
// >= where the specification says "more than", an empty histogram read as
// "nobody is stranded", or an override that leaves no record of what it
// overrode -- each one passes a deploy quietly.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVProtocolContract contract(int n) => DVProtocolContract(
  enums: <DVProtocolEnum>[
    DVProtocolEnum('Step', <String>[for (int i = 0; i <= n; i += 1) 's$i']),
  ],
);

/// Protocols 1..5, released a year apart so only the count window applies.
DVProtocolLock lock([int versions = 5]) {
  DVProtocolLock lock = const DVProtocolLock(<DVProtocolRelease>[]);
  for (int i = 1; i <= versions; i += 1) {
    lock = lock.bump(contract(i), at: DateTime.utc(2020 + i));
  }
  return lock;
}

final DateTime now = DateTime.utc(2026, 9, 14, 12);
const DVProtocolWindow narrow = DVProtocolWindow(
  versions: 2,
  minimumAge: Duration.zero,
);

DVProtocolSessionSample sample(int protocol, int sessions, {int daysAgo = 1}) =>
    DVProtocolSessionSample(
      protocol: protocol,
      day: now.subtract(Duration(days: daysAgo)),
      sessions: sessions,
    );

void main() {
  late List<(String, String)> diagnostics;
  void record(String code, String message) => diagnostics.add((code, message));

  setUp(() => diagnostics = <(String, String)>[]);

  test('traffic inside the window lets the deploy through', () {
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(),
      window: narrow,
      samples: <DVProtocolSessionSample>[sample(5, 900), sample(3, 100)],
      now: now,
      onDiagnostic: record,
    );
    expect(verdict.allowed, isTrue);
    expect(verdict.stranded, isEmpty);
    expect(diagnostics, isEmpty);
  });

  test('a version outside the window above the threshold is refused', () {
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(),
      window: narrow,
      samples: <DVProtocolSessionSample>[sample(5, 990), sample(2, 10)],
      now: now,
      onDiagnostic: record,
    );
    expect(verdict.allowed, isFalse);
    expect(verdict.overridden, isFalse);
    expect(verdict.stranded, <int, double>{2: 0.01});
    expect(diagnostics.single.$1, 'DV-PROTO-005');
    expect(diagnostics.single.$2, contains('protocol 2'));
  });

  test('exactly at the threshold is not above it', () {
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(),
      window: narrow,
      samples: <DVProtocolSessionSample>[sample(5, 995), sample(2, 5)],
      now: now,
      onDiagnostic: record,
    );
    expect(verdict.allowed, isTrue);
    expect(verdict.stranded, isEmpty);
  });

  test('the threshold is the window\'s, not a constant', () {
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(),
      window: const DVProtocolWindow(
        versions: 2,
        minimumAge: Duration.zero,
        strandThreshold: 0.02,
      ),
      samples: <DVProtocolSessionSample>[sample(5, 990), sample(2, 10)],
      now: now,
      onDiagnostic: record,
    );
    expect(verdict.allowed, isTrue);
  });

  test('stranded share is summed over several versions and days', () {
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(),
      window: narrow,
      samples: <DVProtocolSessionSample>[
        sample(5, 996),
        sample(1, 2, daysAgo: 1),
        sample(1, 1, daysAgo: 3),
        sample(2, 1, daysAgo: 6),
      ],
      now: now,
      onDiagnostic: record,
    );
    // Each version alone is under 0.5%. The section's threshold is per
    // version ("a version outside the candidate's window still accounts for
    // more than"), so this passes -- and the histogram says so.
    expect(verdict.histogram, <int, int>{5: 996, 1: 3, 2: 1});
    expect(verdict.allowed, isTrue);
  });

  test('traffic older than seven days is not this week\'s traffic', () {
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(),
      window: narrow,
      samples: <DVProtocolSessionSample>[
        sample(5, 1000),
        sample(1, 500, daysAgo: 8),
      ],
      now: now,
      onDiagnostic: record,
    );
    expect(verdict.histogram, <int, int>{5: 1000});
    expect(verdict.allowed, isTrue);
  });

  test('a rollback strands the clients newer than the candidate', () {
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(4),
      window: narrow,
      samples: <DVProtocolSessionSample>[sample(4, 500), sample(5, 500)],
      now: now,
      onDiagnostic: record,
    );
    expect(verdict.allowed, isFalse);
    expect(verdict.stranded.keys, <int>[5]);
  });

  test('no histogram is no evidence, and is refused', () {
    // A monitoring feed that returned nothing must not read as a fleet with
    // nobody stranded.
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(),
      window: narrow,
      samples: <DVProtocolSessionSample>[sample(1, 400, daysAgo: 30)],
      now: now,
      onDiagnostic: record,
    );
    expect(verdict.allowed, isFalse);
    expect(verdict.refusal, contains('no client sessions'));
  });

  test('an override takes a reason and is logged with the histogram', () {
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(),
      window: narrow,
      samples: <DVProtocolSessionSample>[sample(5, 900), sample(1, 100)],
      now: now,
      overrideReason: 'security fix; protocol 1 leaks tokens',
      onDiagnostic: record,
    );
    expect(verdict.allowed, isTrue);
    expect(verdict.overridden, isTrue);
    expect(diagnostics.single.$1, 'DV-PROTO-005');
    expect(diagnostics.single.$2, contains('overridden'));
    expect(diagnostics.single.$2, contains('security fix'));
    expect(diagnostics.single.$2, contains('"1":100'));
    expect(
      verdict.toJson(),
      containsPair('histogram', <String, int>{'5': 900, '1': 100}),
    );
    expect(
      verdict.toJson()['override'],
      'security fix; protocol 1 leaks tokens',
    );
  });

  test('a blank override reason is no override', () {
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(),
      window: narrow,
      samples: <DVProtocolSessionSample>[sample(5, 900), sample(1, 100)],
      now: now,
      overrideReason: '   ',
      onDiagnostic: record,
    );
    expect(verdict.allowed, isFalse);
    expect(verdict.overridden, isFalse);
  });

  test('an override of a deploy that needed none is not recorded as one', () {
    final DVCompatibilityVerdict verdict = DVCompatibilityCheck.evaluate(
      candidate: lock(),
      window: narrow,
      samples: <DVProtocolSessionSample>[sample(5, 1000)],
      now: now,
      overrideReason: 'just in case',
      onDiagnostic: record,
    );
    expect(verdict.allowed, isTrue);
    expect(verdict.overridden, isFalse);
    expect(diagnostics, isEmpty);
  });
}
