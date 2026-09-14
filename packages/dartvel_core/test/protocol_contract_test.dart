// The protocol version, its lockfile and its window.
//
// The failures worth a test here are the quiet ones. A shape digest that moves
// when fields are merely reordered burns window slots on releases that changed
// nothing. One that does not move when a type narrows ships two contracts under
// one number, which is the thing DV-PROTO-001 exists to refuse. And a window
// that takes the shorter of its two bounds strands a month-old install on a
// team that ships weekly.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

DVProtocolContract contract({
  List<DVProtocolField>? userFields,
  List<String> roles = const <String>['admin', 'member'],
}) => DVProtocolContract(
  models: <DVProtocolModel>[
    DVProtocolModel(
      'User',
      userFields ??
          const <DVProtocolField>[
            DVProtocolField('id', 'int'),
            DVProtocolField('email', 'String'),
          ],
      synced: true,
    ),
  ],
  enums: <DVProtocolEnum>[DVProtocolEnum('Role', roles)],
  functions: const <DVProtocolFunction>[
    DVProtocolFunction(
      'createUser',
      parameters: <DVProtocolField>[DVProtocolField('email', 'String')],
      returns: 'User',
    ),
  ],
);

void main() {
  group('the shape', () {
    test('is an eight-digit hex digest', () {
      expect(contract().shape, matches(RegExp(r'^[0-9a-f]{8}$')));
    });

    test('does not move when declarations are merely reordered', () {
      final DVProtocolContract reordered = contract(
        userFields: const <DVProtocolField>[
          DVProtocolField('email', 'String'),
          DVProtocolField('id', 'int'),
        ],
        roles: const <String>['member', 'admin'],
      );
      expect(reordered.shape, contract().shape);
    });

    test('moves when a type narrows', () {
      final DVProtocolContract narrowed = contract(
        userFields: const <DVProtocolField>[
          DVProtocolField('id', 'int'),
          DVProtocolField('email', 'String?'),
        ],
      );
      expect(narrowed.shape, isNot(contract().shape));
    });

    test('moves when a function gains a required argument', () {
      final DVProtocolContract base = contract();
      final DVProtocolContract changed = DVProtocolContract(
        models: base.models,
        enums: base.enums,
        functions: const <DVProtocolFunction>[
          DVProtocolFunction(
            'createUser',
            parameters: <DVProtocolField>[
              DVProtocolField('email', 'String'),
              DVProtocolField('role', 'Role'),
            ],
            returns: 'User',
          ),
        ],
      );
      expect(changed.shape, isNot(base.shape));
    });

    test('moves when a model stops syncing', () {
      final DVProtocolContract base = contract();
      final DVProtocolContract unsynced = DVProtocolContract(
        models: <DVProtocolModel>[
          DVProtocolModel('User', base.models.single.fields),
        ],
        enums: base.enums,
        functions: base.functions,
      );
      expect(unsynced.shape, isNot(base.shape));
    });

    test('survives a JSON round trip unchanged', () {
      final DVProtocolContract base = contract();
      expect(DVProtocolContract.fromJson(base.toJson()).shape, base.shape);
    });
  });

  group('the lockfile', () {
    final DateTime day = DateTime.utc(2026, 9, 12);

    test('an unlocked project is reported as unlocked, not as passing', () {
      final DVProtocolLockCheck check = const DVProtocolLock(
        <DVProtocolRelease>[],
      ).check(contract());
      expect(check.ok, isFalse);
      expect(check.code, isNull);
      expect(check.unlocked, isTrue);
    });

    test('the first bump records protocol 1', () {
      final DVProtocolLock lock = const DVProtocolLock(
        <DVProtocolRelease>[],
      ).bump(contract(), at: day);
      expect(lock.current!.protocol, 1);
      expect(lock.current!.shape, contract().shape);
      expect(lock.check(contract()).ok, isTrue);
    });

    test('a shape change without an increment fails with DV-PROTO-001', () {
      final DVProtocolLock lock = const DVProtocolLock(
        <DVProtocolRelease>[],
      ).bump(contract(), at: day);
      final DVProtocolContract narrowed = contract(
        userFields: const <DVProtocolField>[
          DVProtocolField('id', 'int'),
          DVProtocolField('email', 'String?'),
        ],
      );
      final DVProtocolLockCheck check = lock.check(narrowed);
      expect(check.ok, isFalse);
      expect(check.code, 'DV-PROTO-001');
      expect(check.message, contains(lock.current!.shape));
      expect(check.message, contains(narrowed.shape));
    });

    test('reverting to an older shape is still a change', () {
      final DVProtocolContract narrowed = contract(
        userFields: const <DVProtocolField>[
          DVProtocolField('id', 'int'),
          DVProtocolField('email', 'String?'),
        ],
      );
      final DVProtocolLock lock = const DVProtocolLock(<DVProtocolRelease>[])
          .bump(contract(), at: day)
          .bump(narrowed, at: day.add(const Duration(days: 7)));
      expect(lock.check(contract()).code, 'DV-PROTO-001');
    });

    test('bumping an unchanged shape is refused', () {
      final DVProtocolLock lock = const DVProtocolLock(
        <DVProtocolRelease>[],
      ).bump(contract(), at: day);
      expect(() => lock.bump(contract(), at: day), throwsStateError);
    });

    test('encodes and decodes, keeping the history', () {
      final DVProtocolLock lock = const DVProtocolLock(<DVProtocolRelease>[])
          .bump(contract(), at: day)
          .bump(
            contract(roles: const <String>['admin']),
            at: day.add(const Duration(days: 3)),
          );
      final DVProtocolLock decoded = DVProtocolLock.decode(lock.encode());
      expect(decoded.releases.map((DVProtocolRelease r) => r.protocol), <int>[
        1,
        2,
      ]);
      expect(decoded.current!.released, DateTime.utc(2026, 9, 15));
      expect(decoded.release(1)!.contract.shape, contract().shape);
      expect(decoded.encode(), lock.encode());
    });

    test('an entry whose shape does not match its contract is refused', () {
      final DVProtocolLock lock = const DVProtocolLock(
        <DVProtocolRelease>[],
      ).bump(contract(), at: day);
      final String tampered = lock.encode().replaceAll(
        lock.current!.shape,
        '00000000',
      );
      expect(() => DVProtocolLock.decode(tampered), throwsFormatException);
    });

    test('protocol numbers that do not ascend by one are refused', () {
      final String encoded = const DVProtocolLock(<DVProtocolRelease>[])
          .bump(contract(), at: day)
          .bump(contract(roles: const <String>['admin']), at: day)
          .encode()
          .replaceAll('"protocol": 2', '"protocol": 5');
      expect(() => DVProtocolLock.decode(encoded), throwsFormatException);
    });
  });

  group('the window', () {
    DVProtocolLock lockWith(List<DateTime> releaseDays) {
      DVProtocolLock lock = const DVProtocolLock(<DVProtocolRelease>[]);
      for (int i = 0; i < releaseDays.length; i += 1) {
        lock = lock.bump(contract(roles: <String>['r$i']), at: releaseDays[i]);
      }
      return lock;
    }

    test('defaults to three versions and 90 days', () {
      const DVProtocolWindow window = DVProtocolWindow();
      expect(window.versions, 3);
      expect(window.minimumAge, const Duration(days: 90));
      expect(window.strandThreshold, 0.005);
    });

    test('a weekly team keeps serving a month-old install', () {
      // Eight weekly protocol changes. Three versions alone would stop at
      // protocol 5, three weeks back; 90 days reaches every one of them.
      final DateTime start = DateTime.utc(2026, 7, 1);
      final DVProtocolLock lock = lockWith(<DateTime>[
        for (int w = 0; w < 8; w += 1) start.add(Duration(days: 7 * w)),
      ]);
      final Set<int> served = const DVProtocolWindow().served(
        lock,
        now: start.add(const Duration(days: 7 * 7 + 1)),
      );
      expect(served, <int>{1, 2, 3, 4, 5, 6, 7, 8});
    });

    test('a twice-yearly team keeps three versions past 90 days', () {
      final DVProtocolLock lock = lockWith(<DateTime>[
        DateTime.utc(2024, 1, 1),
        DateTime.utc(2024, 7, 1),
        DateTime.utc(2025, 1, 1),
        DateTime.utc(2025, 7, 1),
        DateTime.utc(2026, 1, 1),
      ]);
      final Set<int> served = const DVProtocolWindow().served(
        lock,
        now: DateTime.utc(2026, 9, 1),
      );
      expect(served, <int>{2, 3, 4, 5});
    });

    test('a version is aged from when it stopped being current', () {
      // Protocol 1 was released long ago but was only superseded 30 days
      // before now, so installs carrying it can be 30 days old.
      final DVProtocolLock lock = lockWith(<DateTime>[
        DateTime.utc(2025, 1, 1),
        DateTime.utc(2026, 8, 1),
        DateTime.utc(2026, 8, 10),
        DateTime.utc(2026, 8, 20),
        DateTime.utc(2026, 8, 25),
      ]);
      final Set<int> served = const DVProtocolWindow(
        versions: 1,
      ).served(lock, now: DateTime.utc(2026, 8, 31));
      expect(served, contains(1));
    });

    test('an empty lock serves nothing', () {
      expect(
        const DVProtocolWindow().served(
          const DVProtocolLock(<DVProtocolRelease>[]),
          now: DateTime.utc(2026),
        ),
        isEmpty,
      );
    });

    test('is read from the dartvel.protocol config', () {
      final DVProtocolWindow window = DVProtocolWindow.fromConfig(
        <Object?, Object?>{
          'window': 5,
          'minimumAge': '12w',
          'strandThreshold': '1.5%',
        },
      );
      expect(window.versions, 5);
      expect(window.minimumAge, const Duration(days: 84));
      expect(window.strandThreshold, closeTo(0.015, 1e-12));
    });

    test('absent config is the default', () {
      final DVProtocolWindow window = DVProtocolWindow.fromConfig(null);
      expect(window.versions, 3);
      expect(window.minimumAge, const Duration(days: 90));
    });

    test('config it cannot read is refused rather than defaulted', () {
      expect(
        () =>
            DVProtocolWindow.fromConfig(<Object?, Object?>{'minimumAge': '90'}),
        throwsFormatException,
      );
      expect(
        () => DVProtocolWindow.fromConfig(<Object?, Object?>{'window': -1}),
        throwsFormatException,
      );
      expect(
        () => DVProtocolWindow.fromConfig(<Object?, Object?>{
          'strandThreshold': 5,
        }),
        throwsFormatException,
      );
    });
  });
}
