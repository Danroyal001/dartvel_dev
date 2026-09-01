// `dartvel inspect windows` — the static windowing picture.
//
// Windowing is configured almost entirely by defaults: an application that
// writes nothing under `dartvel.windowing` still gets singleInstance on
// desktop, lastWindow exit, restore on launch and a persisted workspace. So
// the question "what windowing policy is actually in effect here" cannot be
// answered by reading pubspec.yaml -- the answer is mostly not in it, and the
// half that is written looks the same as the half that is not.
//
// Which is why every value reports where it came from.
import 'package:dartvel_cli/src/graph/windowing_config.dart';
import 'package:test/test.dart';

void main() {
  group('reading the configuration', () {
    test('an empty project gets the specified defaults', () {
      final DVWindowingConfig config = DVWindowingConfig.parse(null);

      expect(config.enabled, isTrue);
      expect(config.singleInstance, isTrue);
      expect(config.exit, 'lastWindow');
      expect(config.restoreOnLaunch, isTrue);
      expect(config.workspacePersist, isTrue);
      expect(config.workspaceTearOut, 'auto');
    });

    test('and every one of them is marked as a default', () {
      // The whole point. A reader cannot otherwise tell a deliberate
      // `singleInstance: true` from one nobody has thought about.
      final DVWindowingConfig config = DVWindowingConfig.parse(null);

      expect(config.sources.values, everyElement('default'));
      expect(config.sources.keys, contains('singleInstance'));
    });

    test('a written value overrides the default and says so', () {
      final DVWindowingConfig config = DVWindowingConfig.parse(<String, Object?>{
        'windowing': <String, Object?>{'singleInstance': false},
      });

      expect(config.singleInstance, isFalse);
      expect(config.sources['singleInstance'], 'pubspec.yaml');
      expect(config.sources['exit'], 'default',
          reason: 'only the written one changes source');
    });

    test('nested workspace values are read', () {
      final DVWindowingConfig config = DVWindowingConfig.parse(<String, Object?>{
        'windowing': <String, Object?>{
          'workspace': <String, Object?>{
            'persist': false,
            'tearOut': 'disabled',
          },
        },
      });

      expect(config.workspacePersist, isFalse);
      expect(config.workspaceTearOut, 'disabled');
      expect(config.sources['workspace.persist'], 'pubspec.yaml');
    });

    test('windowing: false disables the lot', () {
      final DVWindowingConfig config = DVWindowingConfig.parse(<String, Object?>{
        'windowing': <String, Object?>{'enabled': false},
      });

      expect(config.enabled, isFalse);
    });
  });

  group('values it will not accept', () {
    test('an unknown exit policy is reported rather than passed through', () {
      // It would otherwise reach the runtime as a string nothing matches, and
      // the window would just never close the way the developer asked.
      final DVWindowingConfig config = DVWindowingConfig.parse(<String, Object?>{
        'windowing': <String, Object?>{'exit': 'whenever'},
      });

      expect(config.problems, isNotEmpty);
      expect(config.problems.first, contains('exit'));
      expect(config.problems.first, contains('whenever'));
      expect(config.exit, 'lastWindow', reason: 'falls back to the default');
    });

    test('an unknown tearOut mode is reported', () {
      final DVWindowingConfig config = DVWindowingConfig.parse(<String, Object?>{
        'windowing': <String, Object?>{
          'workspace': <String, Object?>{'tearOut': 'sometimes'},
        },
      });

      expect(config.problems, isNotEmpty);
      expect(config.workspaceTearOut, 'auto');
    });

    test('a string where a boolean belongs is reported, not coerced', () {
      // `singleInstance: "false"` is a yaml quoting mistake, and coercing it
      // either way silently does the opposite of what was written.
      final DVWindowingConfig config = DVWindowingConfig.parse(<String, Object?>{
        'windowing': <String, Object?>{'singleInstance': 'false'},
      });

      expect(config.problems, isNotEmpty);
      expect(config.problems.first, contains('singleInstance'));
      expect(config.singleInstance, isTrue, reason: 'the default stands');
    });

    test('a valid configuration has no problems', () {
      expect(
        DVWindowingConfig.parse(<String, Object?>{
          'windowing': <String, Object?>{
            'enabled': true,
            'singleInstance': false,
            'exit': 'mainWindow',
            'restoreOnLaunch': false,
            'workspace': <String, Object?>{'persist': true, 'tearOut': 'auto'},
          },
        }).problems,
        isEmpty,
      );
    });

    test('a windowing section that is not a map does not throw', () {
      expect(
          DVWindowingConfig.parse(<String, Object?>{'windowing': 'yes'})
              .problems,
          isNotEmpty);
      expect(DVWindowingConfig.parse('nonsense').enabled, isTrue);
    });
  });

  _profiles();

  group('as JSON', () {
    test('it carries the value and its source together', () {
      final Map<String, Object?> json =
          DVWindowingConfig.parse(null).toJson();

      expect(json['enabled'], isTrue);
      expect((json['sources']! as Map)['enabled'], 'default');
    });

    test('problems travel with it', () {
      final Map<String, Object?> json = DVWindowingConfig.parse(
        <String, Object?>{
          'windowing': <String, Object?>{'exit': 'whenever'},
        },
      ).toJson();

      expect(json['problems'], isA<List<Object?>>());
      expect((json['problems']! as List).single, contains('whenever'));
    });
  });
}

// Device profile display names.
//
// The specification puts them in a device profile -- `displays: { Customer:
// { index: 1 } }` -- because a profile author knows the machine's screen
// layout before it boots, and `DVDisplayHint.byName('Customer')` is how a
// kiosk addresses one. A name that reaches the runtime as nothing is the
// failure worth reporting here: the hint then matches no display, and the
// kiosk window opens wherever the OS puts it.
void _profiles() {
  group('display names from a device profile', () {
    Map<String, Object?> profile(Object? displays) => <String, Object?>{
          'deviceProfiles': <String, Object?>{
            'lobby': <String, Object?>{'displays': displays},
          },
        };

    test('no profiles means no names, and no complaint', () {
      final DVWindowingConfig config = DVWindowingConfig.parse(null);
      expect(config.displayNames, isEmpty);
      expect(config.problems, isEmpty);
    });

    test('a name is read against its index', () {
      final DVWindowingConfig config = DVWindowingConfig.parse(profile(
        <String, Object?>{
          'Customer': <String, Object?>{'index': 1},
        },
      ));

      expect(config.displayNames['lobby'], <String, int>{'Customer': 1});
    });

    test('several profiles keep their own names', () {
      final DVWindowingConfig config =
          DVWindowingConfig.parse(<String, Object?>{
        'deviceProfiles': <String, Object?>{
          'lobby': <String, Object?>{
            'displays': <String, Object?>{
              'Signage': <String, Object?>{'index': 0},
            },
          },
          'till': <String, Object?>{
            'displays': <String, Object?>{
              'Customer': <String, Object?>{'index': 1},
            },
          },
        },
      });

      expect(config.displayNames.keys, containsAll(<String>['lobby', 'till']));
      expect(config.displayNames['till'], <String, int>{'Customer': 1});
    });

    test('an entry with no index is reported, not defaulted to zero', () {
      // Zero is the operator's screen on most machines, so guessing it is the
      // one wrong answer that looks plausible.
      final DVWindowingConfig config = DVWindowingConfig.parse(profile(
        <String, Object?>{'Customer': <String, Object?>{}},
      ));

      expect(config.problems, isNotEmpty);
      expect(config.problems.first, contains('Customer'));
      expect(config.displayNames['lobby'] ?? const <String, int>{}, isEmpty);
    });

    test('a negative or non-integer index is reported', () {
      expect(
        DVWindowingConfig.parse(profile(<String, Object?>{
          'Customer': <String, Object?>{'index': -1},
        })).problems,
        isNotEmpty,
      );
      expect(
        DVWindowingConfig.parse(profile(<String, Object?>{
          'Customer': <String, Object?>{'index': 'second'},
        })).problems,
        isNotEmpty,
      );
    });

    test('two names on one index is reported', () {
      // Both would be legal on their own, and the runtime has to pick one, so
      // the choice should be made in the profile rather than by iteration
      // order.
      final DVWindowingConfig config = DVWindowingConfig.parse(profile(
        <String, Object?>{
          'Customer': <String, Object?>{'index': 1},
          'Signage': <String, Object?>{'index': 1},
        },
      ));

      expect(config.problems, isNotEmpty);
      expect(config.problems.first, contains('1'));
    });

    test('a malformed profile does not throw', () {
      expect(() => DVWindowingConfig.parse(profile('nonsense')),
          returnsNormally);
      expect(
          () => DVWindowingConfig.parse(<String, Object?>{
                'deviceProfiles': 'nonsense',
              }),
          returnsNormally);
    });

    test('the names travel in the JSON', () {
      final Map<String, Object?> json = DVWindowingConfig.parse(profile(
        <String, Object?>{
          'Customer': <String, Object?>{'index': 1},
        },
      )).toJson();

      expect((json['displayNames']! as Map)['lobby'],
          <String, Object?>{'Customer': 1});
    });
  });
}
