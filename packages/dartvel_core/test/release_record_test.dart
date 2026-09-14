// Releases, their provenance records, and the history rollback reads.
//
// A release history is judged by the rollback it produces. The failures worth
// testing are the quiet ones: a record read back with a field defaulted, so a
// rollback names a commit nobody built; a release deployed with no record,
// skipped over so the rollback lands one release further back than anybody
// asked; and a second rollback that returns to the release the first one
// rolled back from.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 11, 14, 2);

DVReleaseRecord record(String id, {int protocol = 3, Set<String>? functions}) =>
    DVReleaseRecord(
      id: id,
      commit: 'c0ffee$id',
      artifact: 'sha256:$id',
      protocolVersion: protocol,
      migrationPlan: null,
      releasedBy: 'daniel',
      releasedAt: t0,
      functions: functions ?? const <String>{'checkout', 'refund'},
    );

class _Diagnostics {
  final List<String> codes = <String>[];
  void call(String code, String message) => codes.add(code);
}

void main() {
  group('a provenance record', () {
    test('round-trips through JSON', () {
      final DVReleaseRecord original = record(
        'r1',
        protocol: 7,
      ).copyWith(migrationPlan: 'plan-42', schema: <String, DVReleaseMigrationPhase>{
        'orders.total': DVReleaseMigrationPhase.backfilled,
      });
      final DVReleaseRecord read = DVReleaseRecord.fromJson(original.toJson());
      expect(read.id, 'r1');
      expect(read.commit, 'c0ffeer1');
      expect(read.artifact, 'sha256:r1');
      expect(read.protocolVersion, 7);
      expect(read.migrationPlan, 'plan-42');
      expect(read.releasedBy, 'daniel');
      expect(read.releasedAt, t0);
      expect(read.functions, <String>{'checkout', 'refund'});
      expect(read.schema, <String, DVReleaseMigrationPhase>{
        'orders.total': DVReleaseMigrationPhase.backfilled,
      });
    });

    test('a field missing from the JSON is refused, not defaulted', () {
      // A defaulted commit is a rollback that names a build nobody made.
      for (final String key in <String>[
        'id',
        'commit',
        'artifact',
        'protocolVersion',
        'migrationPlan',
        'releasedBy',
        'releasedAt',
      ]) {
        final Map<String, Object?> json = record('r1').toJson()..remove(key);
        expect(
          () => DVReleaseRecord.fromJson(json),
          throwsFormatException,
          reason: key,
        );
      }
    });

    test('no migration plan is said explicitly, as null', () {
      final Map<String, Object?> json = record('r1').toJson();
      expect(json.containsKey('migrationPlan'), isTrue);
      expect(DVReleaseRecord.fromJson(json).migrationPlan, isNull);
    });

    test('a blank commit or author is not provenance', () {
      expect(
        () => DVReleaseRecord(
          id: 'r1',
          commit: ' ',
          artifact: 'a',
          protocolVersion: 1,
          migrationPlan: null,
          releasedBy: 'x',
          releasedAt: t0,
        ),
        throwsArgumentError,
      );
      expect(
        () => DVReleaseRecord(
          id: 'r1',
          commit: 'abc',
          artifact: 'a',
          protocolVersion: 1,
          migrationPlan: null,
          releasedBy: '',
          releasedAt: t0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('the release history', () {
    test('a release deployed with no record reports DV-RELEASE-006', () {
      final _Diagnostics diagnostics = _Diagnostics();
      final DVReleaseHistory history = DVReleaseHistory(
        onDiagnostic: diagnostics.call,
      );
      history.deployed('r1', provenance: null, at: t0);
      expect(diagnostics.codes, <String>['DV-RELEASE-006']);
      expect(history.current!.id, 'r1');
      expect(history.current!.provenance, isNull);
    });

    test('a record naming a different release is refused', () {
      final DVReleaseHistory history = DVReleaseHistory(
        onDiagnostic: (_, _) {},
      );
      expect(
        () => history.deployed('r2', provenance: record('r1'), at: t0),
        throwsArgumentError,
      );
    });

    test('deploys are recorded in order; one out of order is refused', () {
      final DVReleaseHistory history = DVReleaseHistory(
        onDiagnostic: (_, _) {},
      );
      history.deployed('r1', provenance: record('r1'), at: t0);
      expect(
        () => history.deployed(
          'r2',
          provenance: record('r2'),
          at: t0.subtract(const Duration(minutes: 1)),
        ),
        throwsArgumentError,
      );
    });

    test('the previous release is the one serving before the current', () {
      final DVReleaseHistory history = DVReleaseHistory(
        onDiagnostic: (_, _) {},
      )
        ..deployed('r1', provenance: record('r1'), at: t0)
        ..deployed('r2', provenance: record('r2'), at: t0.add(_hour))
        ..deployed('r3', provenance: record('r3'), at: t0.add(_hour * 2));
      expect(history.previous()!.id, 'r2');
    });

    test('after a rollback, the previous release is not the one rolled back '
        'from', () {
      // r1, r2, r3; r3 is bad and is rolled back to r2. Rolling back again
      // from r2 must reach r1 -- returning to r3 is rolling forward onto the
      // release that was just taken away.
      final DVReleaseHistory history = DVReleaseHistory(
        onDiagnostic: (_, _) {},
      )
        ..deployed('r1', provenance: record('r1'), at: t0)
        ..deployed('r2', provenance: record('r2'), at: t0.add(_hour))
        ..deployed('r3', provenance: record('r3'), at: t0.add(_hour * 2));
      history.rolledBack(to: 'r2', at: t0.add(_hour * 3));
      expect(history.current!.id, 'r2');
      expect(history.previous()!.id, 'r1');
    });

    test('the release serving at a moment is the newest deployed by then', () {
      final DVReleaseHistory history = DVReleaseHistory(
        onDiagnostic: (_, _) {},
      )
        ..deployed('r1', provenance: record('r1'), at: t0)
        ..deployed('r2', provenance: record('r2'), at: t0.add(_hour));
      expect(history.servingAt(t0.add(const Duration(minutes: 59)))!.id, 'r1');
      expect(history.servingAt(t0.add(_hour))!.id, 'r2');
      expect(history.servingAt(t0.subtract(_hour)), isNull);
    });

    test('rolling back to a release that was never deployed is refused', () {
      final DVReleaseHistory history = DVReleaseHistory(
        onDiagnostic: (_, _) {},
      )..deployed('r1', provenance: record('r1'), at: t0);
      expect(
        () => history.rolledBack(to: 'r9', at: t0.add(_hour)),
        throwsArgumentError,
      );
    });

    test('round-trips through JSON, including a release with no record', () {
      final DVReleaseHistory history = DVReleaseHistory(
        onDiagnostic: (_, _) {},
      )
        ..deployed('r1', provenance: record('r1'), at: t0)
        ..deployed('r2', provenance: null, at: t0.add(_hour))
        ..deployed('r3', provenance: record('r3'), at: t0.add(_hour * 2));
      history.rolledBack(to: 'r1', at: t0.add(_hour * 3));
      final DVReleaseHistory read = DVReleaseHistory.fromJson(
        history.toJson(),
        onDiagnostic: (_, _) {},
      );
      expect(
        read.releases.map((DVDeployedRelease r) => r.id).toList(),
        <String>['r1', 'r2', 'r3', 'r1'],
      );
      expect(read.releases[1].provenance, isNull);
      expect(read.releases[2].rolledBackFrom, isTrue);
      expect(read.current!.id, 'r1');
      expect(read.previous(), isNull);
    });
  });
}

const Duration _hour = Duration(hours: 1);
