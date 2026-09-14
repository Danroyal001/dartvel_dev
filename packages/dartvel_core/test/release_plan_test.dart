// Deploy configuration and the strategy a release actually runs under.
//
// The config is read strictly because a typo that silently became a default is
// a rollout nobody chose: `stratgy: canary` read as recreate replaces every
// instance at once while the pubspec says five per cent. And the strategy is
// the adapter's answer: a canary planned for a platform that cannot weight
// traffic is a DNS split that looks like a canary and is not one.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Adapter implements DVReleaseAdapter {
  _Adapter({required this.canWeightTraffic, this.name = 'fake'});

  @override
  final String name;

  @override
  final bool canWeightTraffic;

  @override
  Future<void> route({
    required String candidate,
    required String? previous,
    required int percent,
  }) async {}

  @override
  Future<int?> weightOf(String release) async => null;
}

void main() {
  group('reading dartvel.deploy', () {
    test('the section example reads as written', () {
      final DVDeployConfig config = DVDeployConfig.fromConfig(<String, Object?>{
        'strategy': 'canary',
        'canary': <String, Object?>{
          'steps': <int>[5, 25, 50, 100],
          'hold': '10m',
        },
        'gate': <String, Object?>{
          'errorRate': '1%',
          'stages': <String, Object?>{'commit': '0.1%', 'authorization': '2%'},
          'latencyP95': '+20%',
        },
      });
      expect(config.strategy, DVDeployStrategy.canary);
      expect(config.canary.steps, <int>[5, 25, 50, 100]);
      expect(config.canary.hold, const Duration(minutes: 10));
      expect(config.gate.errorRate, closeTo(0.01, 1e-12));
      expect(config.gate.stages[DVRequestStage.commit], closeTo(0.001, 1e-12));
      expect(
        config.gate.stages[DVRequestStage.authorization],
        closeTo(0.02, 1e-12),
      );
      expect(config.gate.latencyP95Increase, closeTo(0.20, 1e-12));
    });

    test('blue-green is spelled as the pubspec spells it', () {
      expect(
        DVDeployConfig.fromConfig(<String, Object?>{
          'strategy': 'blue-green',
        }).strategy,
        DVDeployStrategy.blueGreen,
      );
    });

    test('a gate is never absent: no gate section is the default thresholds, '
        'not none', () {
      // A gate with no thresholds passes every release, which is the same as
      // no gate and reads as one.
      final DVDeployConfig config = DVDeployConfig.fromConfig(null);
      expect(config.gate.errorRate, isNotNull);
      expect(config.gate.latencyP95Increase, isNotNull);
      expect(config.gate.stages, isNotEmpty);
    });

    test('an unknown strategy is refused', () {
      expect(
        () => DVDeployConfig.fromConfig(<String, Object?>{'strategy': 'dns'}),
        throwsFormatException,
      );
    });

    test('a misspelled key is refused rather than ignored', () {
      for (final Map<String, Object?> config in <Map<String, Object?>>[
        <String, Object?>{'stratgy': 'canary'},
        <String, Object?>{
          'canary': <String, Object?>{'step': <int>[5, 100]},
        },
        <String, Object?>{
          'gate': <String, Object?>{'errorrate': '1%'},
        },
        <String, Object?>{
          'gate': <String, Object?>{
            'stages': <String, Object?>{'comit': '0.1%'},
          },
        },
      ]) {
        expect(
          () => DVDeployConfig.fromConfig(config),
          throwsFormatException,
          reason: '$config',
        );
      }
    });

    test('canary steps must climb to 100', () {
      for (final List<Object?> steps in <List<Object?>>[
        <Object?>[],
        <Object?>[5, 25, 50], // never completes
        <Object?>[25, 5, 100], // goes backwards
        <Object?>[5, 5, 100], // holds twice at one weight
        <Object?>[0, 100],
        <Object?>[5, 150],
        <Object?>['5', 100],
      ]) {
        expect(
          () => DVDeployConfig.fromConfig(<String, Object?>{
            'canary': <String, Object?>{'steps': steps},
          }),
          throwsFormatException,
          reason: '$steps',
        );
      }
    });

    test('a hold must be a positive duration', () {
      for (final Object? hold in <Object?>['0m', '10', 'ten minutes', -1]) {
        expect(
          () => DVDeployConfig.fromConfig(<String, Object?>{
            'canary': <String, Object?>{'hold': hold},
          }),
          throwsFormatException,
          reason: '$hold',
        );
      }
      expect(
        DVDeployConfig.fromConfig(<String, Object?>{
          'canary': <String, Object?>{'hold': '90s'},
        }).canary.hold,
        const Duration(seconds: 90),
      );
    });

    test('thresholds must be percentages', () {
      for (final Map<String, Object?> gate in <Map<String, Object?>>[
        <String, Object?>{'errorRate': '1'},
        <String, Object?>{'errorRate': '-1%'},
        <String, Object?>{'errorRate': '101%'},
        <String, Object?>{'latencyP95': 'fast'},
      ]) {
        expect(
          () => DVDeployConfig.fromConfig(<String, Object?>{'gate': gate}),
          throwsFormatException,
          reason: '$gate',
        );
      }
    });

    test('every numbered lifecycle stage has its specification number', () {
      expect(DVRequestStage.values, hasLength(21));
      expect(DVRequestStage.authorization.number, 12);
      expect(DVRequestStage.commit.number, 17);
      for (int i = 0; i < DVRequestStage.values.length; i++) {
        expect(DVRequestStage.values[i].number, i + 1);
      }
    });
  });

  group('planning a release', () {
    const DVDeployConfig canary = DVDeployConfig(
      strategy: DVDeployStrategy.canary,
      canary: DVCanaryConfig(steps: <int>[5, 25, 50, 100], hold: Duration(minutes: 10)),
    );

    test('a canary on an adapter that can weight runs the declared steps', () {
      final List<String> codes = <String>[];
      final DVReleasePlan plan = DVReleasePlanner.plan(
        canary,
        _Adapter(canWeightTraffic: true, name: 'cloud-run'),
        onDiagnostic: (String code, _) => codes.add(code),
      );
      expect(plan.strategy, DVDeployStrategy.canary);
      expect(plan.steps, <int>[5, 25, 50, 100]);
      expect(plan.hold, const Duration(minutes: 10));
      expect(plan.degraded, isFalse);
      expect(codes, isEmpty);
    });

    test('a canary on an adapter that cannot weight degrades to blue-green, '
        'says so, and keeps the hold', () {
      final List<String> codes = <String>[];
      final DVReleasePlan plan = DVReleasePlanner.plan(
        canary,
        _Adapter(canWeightTraffic: false, name: 'bare-metal'),
        onDiagnostic: (String code, _) => codes.add(code),
      );
      expect(plan.requested, DVDeployStrategy.canary);
      expect(plan.strategy, DVDeployStrategy.blueGreen);
      // Not five per cent of anything: the platform cannot send five per cent.
      expect(plan.steps, <int>[100]);
      expect(plan.hold, const Duration(minutes: 10));
      expect(plan.degraded, isTrue);
      expect(codes, <String>['DV-RELEASE-002']);
      expect(plan.findings.single.code, 'DV-RELEASE-002');
      expect(plan.findings.single.level, 'warning');
      expect(plan.describe(), contains('blue-green'));
      expect(plan.describe(), contains('bare-metal'));
      expect(plan.describe(), contains('DV-RELEASE-002'));
    });

    test('blue-green and recreate switch all traffic in one step', () {
      for (final DVDeployStrategy strategy in <DVDeployStrategy>[
        DVDeployStrategy.blueGreen,
        DVDeployStrategy.recreate,
      ]) {
        final DVReleasePlan plan = DVReleasePlanner.plan(
          DVDeployConfig(strategy: strategy),
          _Adapter(canWeightTraffic: true),
          onDiagnostic: (_, _) {},
        );
        expect(plan.steps, <int>[100], reason: strategy.name);
        expect(plan.degraded, isFalse);
      }
    });

    test('a plan cannot be built with steps that do not reach 100', () {
      expect(
        () => const DVCanaryConfig(
          steps: <int>[5, 50],
          hold: Duration(minutes: 1),
        ).validate(),
        throwsArgumentError,
      );
    });
  });
}
