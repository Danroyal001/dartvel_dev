// What a windowed client may be served, and what it may not.
//
// The section's line is that a degraded response must still be true in the
// old client's vocabulary. The failures that matter are the ones that look
// like success: an adapter that quietly drops a field the old client requires,
// an enum member mapped to a guess because nobody declared a fallback, or a
// lossy change served to old clients because nothing asked whether an adapter
// had been written for it.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVProtocolModel address = DVProtocolModel('Address', <DVProtocolField>[
  DVProtocolField('city', 'String'),
]);

DVProtocolContract base({
  List<DVProtocolField> userFields = const <DVProtocolField>[
    DVProtocolField('id', 'int'),
    DVProtocolField('email', 'String'),
    DVProtocolField('role', 'Role'),
    DVProtocolField('addresses', 'List<Address>'),
  ],
  DVProtocolEnum role = const DVProtocolEnum('Role', <String>[
    'admin',
    'member',
  ]),
  List<DVProtocolField> createParams = const <DVProtocolField>[
    DVProtocolField('email', 'String'),
  ],
  String returns = 'User',
  bool synced = true,
  List<DVProtocolModel> extraModels = const <DVProtocolModel>[],
  List<DVProtocolFunction> extraFunctions = const <DVProtocolFunction>[],
}) => DVProtocolContract(
  models: <DVProtocolModel>[
    DVProtocolModel('User', userFields, synced: synced),
    address,
    ...extraModels,
  ],
  enums: <DVProtocolEnum>[role],
  functions: <DVProtocolFunction>[
    DVProtocolFunction(
      'createUser',
      parameters: createParams,
      returns: returns,
    ),
    ...extraFunctions,
  ],
);

DVProtocolChange only(DVProtocolContract old, DVProtocolContract current) {
  final List<DVProtocolChange> changes = DVProtocolDiff.between(old, current);
  expect(changes, hasLength(1), reason: '$changes');
  return changes.single;
}

DVProtocolLock lockOf(List<DVProtocolContract> contracts) {
  DVProtocolLock lock = const DVProtocolLock(<DVProtocolRelease>[]);
  DateTime day = DateTime.utc(2026, 9, 1);
  for (final DVProtocolContract c in contracts) {
    lock = lock.bump(c, at: day);
    day = day.add(const Duration(days: 1));
  }
  return lock;
}

final DateTime now = DateTime.utc(2026, 9, 14);

void main() {
  group('classifying a change', () {
    test('an identical contract has no changes', () {
      expect(DVProtocolDiff.between(base(), base()), isEmpty);
    });

    test('a new optional field is hidden from the old client', () {
      final DVProtocolChange change = only(
        base(),
        base(
          userFields: <DVProtocolField>[
            ...base().model('User')!.fields,
            const DVProtocolField('nickname', 'String?'),
          ],
        ),
      );
      expect(change.kind, DVProtocolChangeKind.fieldAdded);
      expect(change.subject, 'User.nickname');
      expect(change.safety, DVProtocolChangeSafety.hidden);
    });

    test('a new required field with no default is lossy', () {
      // The old client's forms cannot send it, so a record it creates cannot
      // be built -- the model analogue of adding a required argument.
      final DVProtocolChange change = only(
        base(),
        base(
          userFields: <DVProtocolField>[
            ...base().model('User')!.fields,
            const DVProtocolField('tenant', 'String'),
          ],
        ),
      );
      expect(change.safety, DVProtocolChangeSafety.lossy);
    });

    test('dropping a field the old shape has is lossy', () {
      final DVProtocolChange change = only(
        base(),
        base(
          userFields: const <DVProtocolField>[
            DVProtocolField('id', 'int'),
            DVProtocolField('role', 'Role'),
            DVProtocolField('addresses', 'List<Address>'),
          ],
        ),
      );
      expect(change.kind, DVProtocolChangeKind.fieldRemoved);
      expect(change.subject, 'User.email');
      expect(change.safety, DVProtocolChangeSafety.lossy);
    });

    test('a rename with an alias is hidden; without one it is lossy', () {
      final DVProtocolChange aliased = only(
        base(),
        base(
          userFields: const <DVProtocolField>[
            DVProtocolField('id', 'int'),
            DVProtocolField('mail', 'String', renamedFrom: 'email'),
            DVProtocolField('role', 'Role'),
            DVProtocolField('addresses', 'List<Address>'),
          ],
        ),
      );
      expect(aliased.kind, DVProtocolChangeKind.fieldRenamed);
      expect(aliased.subject, 'User.mail');
      expect(aliased.safety, DVProtocolChangeSafety.hidden);

      final List<DVProtocolChange> bare = DVProtocolDiff.between(
        base(),
        base(
          userFields: const <DVProtocolField>[
            DVProtocolField('id', 'int'),
            DVProtocolField('mail', 'String'),
            DVProtocolField('role', 'Role'),
            DVProtocolField('addresses', 'List<Address>'),
          ],
        ),
      );
      expect(
        bare.map((DVProtocolChange c) => c.safety),
        contains(DVProtocolChangeSafety.lossy),
      );
    });

    test('narrowing a type is lossy, and so is widening it', () {
      for (final String type in <String>['String?', 'Object']) {
        final DVProtocolChange change = only(
          base(),
          base(
            userFields: <DVProtocolField>[
              const DVProtocolField('id', 'int'),
              DVProtocolField('email', type),
              const DVProtocolField('role', 'Role'),
              const DVProtocolField('addresses', 'List<Address>'),
            ],
          ),
        );
        expect(change.kind, DVProtocolChangeKind.fieldTypeChanged);
        expect(change.safety, DVProtocolChangeSafety.lossy, reason: type);
      }
    });

    test(
      'a new enum member maps to a declared fallback the old client knows',
      () {
        final DVProtocolChange change = only(
          base(),
          base(
            role: const DVProtocolEnum('Role', <String>[
              'admin',
              'member',
              'guest',
            ], fallback: 'member'),
          ),
        );
        expect(change.kind, DVProtocolChangeKind.enumMemberAdded);
        expect(change.subject, 'Role.guest');
        expect(change.safety, DVProtocolChangeSafety.hidden);
      },
    );

    test(
      'a new enum member with no fallback is upgradeRequired, not a guess',
      () {
        final List<DVProtocolChange> changes = DVProtocolDiff.between(
          base(),
          base(
            role: const DVProtocolEnum('Role', <String>[
              'admin',
              'member',
              'guest',
            ]),
          ),
        );
        expect(changes.single.safety, DVProtocolChangeSafety.upgradeRequired);
      },
    );

    test('a fallback the old client has never heard of is no fallback', () {
      final List<DVProtocolChange> changes = DVProtocolDiff.between(
        base(),
        base(
          role: const DVProtocolEnum('Role', <String>[
            'admin',
            'member',
            'guest',
            'visitor',
          ], fallback: 'visitor'),
        ),
      );
      expect(
        changes
            .where((DVProtocolChange c) => c.subject == 'Role.guest')
            .single
            .safety,
        DVProtocolChangeSafety.upgradeRequired,
      );
    });

    test('removing an enum member is lossy', () {
      final DVProtocolChange change = only(
        base(),
        base(role: const DVProtocolEnum('Role', <String>['admin'])),
      );
      expect(change.kind, DVProtocolChangeKind.enumMemberRemoved);
      expect(change.safety, DVProtocolChangeSafety.lossy);
    });

    test('what the old client never calls is hidden', () {
      final List<DVProtocolChange> changes = DVProtocolDiff.between(
        base(),
        base(
          extraModels: const <DVProtocolModel>[
            DVProtocolModel('Invoice', <DVProtocolField>[]),
          ],
          extraFunctions: const <DVProtocolFunction>[
            DVProtocolFunction('listInvoices', returns: 'List<Invoice>'),
          ],
        ),
      );
      expect(
        changes.map((DVProtocolChange c) => c.kind).toSet(),
        <DVProtocolChangeKind>{
          DVProtocolChangeKind.modelAdded,
          DVProtocolChangeKind.functionAdded,
        },
      );
      expect(
        changes.every(
          (DVProtocolChange c) => c.safety == DVProtocolChangeSafety.hidden,
        ),
        isTrue,
      );
    });

    test('removing a model or function the old client may call is lossy', () {
      final DVProtocolContract old = base(
        extraModels: const <DVProtocolModel>[
          DVProtocolModel('Invoice', <DVProtocolField>[]),
        ],
        extraFunctions: const <DVProtocolFunction>[
          DVProtocolFunction('listInvoices', returns: 'List<Invoice>'),
        ],
      );
      final List<DVProtocolChange> changes = DVProtocolDiff.between(
        old,
        base(),
      );
      expect(changes, hasLength(2));
      expect(
        changes.every(
          (DVProtocolChange c) => c.safety == DVProtocolChangeSafety.lossy,
        ),
        isTrue,
      );
    });

    test('an optional argument is hidden; a required one is lossy', () {
      final DVProtocolChange optional = only(
        base(),
        base(
          createParams: const <DVProtocolField>[
            DVProtocolField('email', 'String'),
            DVProtocolField('role', 'Role', hasDefault: true),
          ],
        ),
      );
      expect(optional.kind, DVProtocolChangeKind.parameterAdded);
      expect(optional.subject, 'createUser.role');
      expect(optional.safety, DVProtocolChangeSafety.hidden);

      final DVProtocolChange required = only(
        base(),
        base(
          createParams: const <DVProtocolField>[
            DVProtocolField('email', 'String'),
            DVProtocolField('role', 'Role'),
          ],
        ),
      );
      expect(required.safety, DVProtocolChangeSafety.lossy);
    });

    test('a changed return type is lossy', () {
      final DVProtocolChange change = only(base(), base(returns: 'User?'));
      expect(change.kind, DVProtocolChangeKind.returnTypeChanged);
      expect(change.subject, 'createUser.returns');
      expect(change.safety, DVProtocolChangeSafety.lossy);
    });

    test('a model that stops syncing is lossy; one that starts is hidden', () {
      expect(
        only(base(), base(synced: false)).safety,
        DVProtocolChangeSafety.lossy,
      );
      expect(
        only(base(synced: false), base()).safety,
        DVProtocolChangeSafety.hidden,
      );
    });
  });

  group('the plan for a window', () {
    test('hidden changes degrade; the current version is compatible', () {
      final DVProtocolPlan plan = DVProtocolPlan.build(
        lock: lockOf(<DVProtocolContract>[
          base(),
          base(
            userFields: <DVProtocolField>[
              ...base().model('User')!.fields,
              const DVProtocolField('nickname', 'String?'),
            ],
          ),
        ]),
        now: now,
      );
      expect(plan.errors, isEmpty);
      expect(plan.current, 2);
      expect(plan.resultFor(2), DVProtocolResult.compatible);
      expect(plan.resultFor(1), DVProtocolResult.degraded);
    });

    test('a version the lock never recorded is upgradeRequired', () {
      final DVProtocolPlan plan = DVProtocolPlan.build(
        lock: lockOf(<DVProtocolContract>[base()]),
        now: now,
      );
      expect(plan.resultFor(0), DVProtocolResult.upgradeRequired);
    });

    test('a client ahead of the backend has no result to give', () {
      final DVProtocolPlan plan = DVProtocolPlan.build(
        lock: lockOf(<DVProtocolContract>[base()]),
        now: now,
      );
      expect(plan.resultFor(2), isNull);
    });

    test('a version outside the window is upgradeRequired', () {
      final DVProtocolPlan plan = DVProtocolPlan.build(
        lock: lockOf(<DVProtocolContract>[
          base(),
          base(returns: 'User?'),
          base(returns: 'User?', synced: false),
        ]),
        window: const DVProtocolWindow(versions: 0, minimumAge: Duration.zero),
        now: now,
      );
      expect(plan.versions.keys, <int>[3]);
      expect(plan.resultFor(1), DVProtocolResult.upgradeRequired);
      // Outside the window nothing is served, so nothing needs an adapter.
      expect(plan.errors, isEmpty);
    });

    test('a lossy change with no declared adapter fails with DV-PROTO-004', () {
      final DVProtocolPlan plan = DVProtocolPlan.build(
        lock: lockOf(<DVProtocolContract>[base(), base(returns: 'User?')]),
        now: now,
      );
      expect(plan.errors, hasLength(1));
      expect(plan.errors.single.code, 'DV-PROTO-004');
      expect(plan.errors.single.protocol, 1);
      expect(plan.errors.single.message, contains('createUser.returns'));
      // And it is never served degraded on the strength of the build having
      // been ignored.
      expect(plan.resultFor(1), DVProtocolResult.upgradeRequired);
    });

    test('a declared adapter makes the same change servable', () {
      final DVProtocolPlan plan = DVProtocolPlan.build(
        lock: lockOf(<DVProtocolContract>[base(), base(returns: 'User?')]),
        now: now,
        adapters: <DVProtocolAdapter>[
          DVProtocolAdapter(
            from: 1,
            subject: 'createUser.returns',
            response: (Object? value) => value ?? <String, Object?>{},
          ),
        ],
      );
      expect(plan.errors, isEmpty);
      expect(plan.resultFor(1), DVProtocolResult.degraded);
    });

    test('an adapter declared for another version does not count', () {
      final DVProtocolPlan plan = DVProtocolPlan.build(
        lock: lockOf(<DVProtocolContract>[base(), base(returns: 'User?')]),
        now: now,
        adapters: <DVProtocolAdapter>[
          DVProtocolAdapter(
            from: 7,
            subject: 'createUser.returns',
            response: (Object? value) => value,
          ),
        ],
      );
      expect(plan.errors.single.code, 'DV-PROTO-004');
    });

    test(
      'an enum member with no fallback narrows the window (DV-PROTO-006)',
      () {
        final DVProtocolPlan plan = DVProtocolPlan.build(
          lock: lockOf(<DVProtocolContract>[
            base(),
            base(
              role: const DVProtocolEnum('Role', <String>[
                'admin',
                'member',
                'guest',
              ]),
            ),
          ]),
          now: now,
        );
        expect(plan.errors, isEmpty);
        expect(plan.warnings.single.code, 'DV-PROTO-006');
        expect(plan.warnings.single.message, contains('Role.guest'));
        expect(plan.resultFor(1), DVProtocolResult.upgradeRequired);
      },
    );
  });

  group('adapting for a windowed client', () {
    final DVProtocolContract current = base(
      userFields: const <DVProtocolField>[
        DVProtocolField('id', 'int'),
        DVProtocolField('mail', 'String', renamedFrom: 'email'),
        DVProtocolField('role', 'Role'),
        DVProtocolField('addresses', 'List<Address>'),
        DVProtocolField('nickname', 'String?'),
      ],
      role: const DVProtocolEnum('Role', <String>[
        'admin',
        'member',
        'guest',
      ], fallback: 'member'),
      createParams: const <DVProtocolField>[
        DVProtocolField('mail', 'String', renamedFrom: 'email'),
        DVProtocolField('invitedBy', 'int?'),
      ],
      extraModels: <DVProtocolModel>[
        const DVProtocolModel('Address', <DVProtocolField>[
          DVProtocolField('city', 'String'),
          DVProtocolField('postcode', 'String?'),
        ]),
      ],
    );

    // `extraModels` above adds a second Address; the plan is built from a
    // contract with one, so replace rather than append.
    DVProtocolContract dedupe(DVProtocolContract c) => DVProtocolContract(
      models: <DVProtocolModel>[
        c.model('User')!,
        c.models.lastWhere((DVProtocolModel m) => m.name == 'Address'),
      ],
      enums: c.enums,
      functions: c.functions,
    );

    late List<(String, String)> diagnostics;
    late DVProtocolAdapterSet adapter;

    setUp(() {
      diagnostics = <(String, String)>[];
      final DVProtocolPlan plan = DVProtocolPlan.build(
        lock: lockOf(<DVProtocolContract>[base(), dedupe(current)]),
        now: now,
        onDiagnostic: (String code, String message) =>
            diagnostics.add((code, message)),
      );
      expect(plan.errors, isEmpty, reason: '${plan.errors}');
      adapter = plan.adapterFor(1)!;
    });

    final Map<String, Object?> user = <String, Object?>{
      'id': 3,
      'mail': 'a@b.c',
      'role': 'guest',
      'nickname': 'ada',
      'addresses': <Object?>[
        <String, Object?>{'city': 'Lagos', 'postcode': '100001'},
      ],
      'createdAt': '2026-09-14',
    };

    test('a model is served in the old vocabulary', () {
      expect(adapter.model('User', user), <String, Object?>{
        'id': 3,
        'email': 'a@b.c',
        'role': 'member',
        'addresses': <Object?>[
          <String, Object?>{'city': 'Lagos'},
        ],
        // Not a contract field -- the adapter does not invent a rule for it.
        'createdAt': '2026-09-14',
      });
    });

    test('a member the old client knows is left alone', () {
      final Object? adapted = adapter.model('User', <String, Object?>{
        ...user,
        'role': 'admin',
      });
      expect((adapted! as Map<String, Object?>)['role'], 'admin');
    });

    test('a function result is adapted by its return type', () {
      expect(
        (adapter.result('createUser', user)! as Map<String, Object?>)
            .containsKey('nickname'),
        isFalse,
      );
    });

    test('arguments sent under an old name reach the new parameter', () {
      expect(
        adapter.arguments('createUser', <String, Object?>{'email': 'a@b.c'}),
        <String, Object?>{'mail': 'a@b.c'},
      );
    });

    test('degrading a response reports DV-PROTO-003', () {
      adapter.model('User', user);
      expect(
        diagnostics.map(((String, String) d) => d.$1),
        contains('DV-PROTO-003'),
      );
    });

    test('a declared adapter is applied to its subject', () {
      final DVProtocolPlan plan = DVProtocolPlan.build(
        lock: lockOf(<DVProtocolContract>[
          base(),
          base(
            userFields: const <DVProtocolField>[
              DVProtocolField('id', 'String'),
              DVProtocolField('email', 'String'),
              DVProtocolField('role', 'Role'),
              DVProtocolField('addresses', 'List<Address>'),
            ],
          ),
        ]),
        now: now,
        adapters: <DVProtocolAdapter>[
          DVProtocolAdapter(
            from: 1,
            subject: 'User.id',
            response: (Object? value) => int.parse(value! as String),
          ),
        ],
      );
      expect(plan.errors, isEmpty);
      final Object? adapted = plan.adapterFor(1)!.model(
        'User',
        <String, Object?>{
          'id': '42',
          'email': 'a@b.c',
          'role': 'admin',
          'addresses': <Object?>[],
        },
      );
      expect((adapted! as Map<String, Object?>)['id'], 42);
    });

    test('the current version needs no adapter', () {
      final DVProtocolPlan plan = DVProtocolPlan.build(
        lock: lockOf(<DVProtocolContract>[base()]),
        now: now,
      );
      expect(plan.adapterFor(1), isNull);
    });
  });
}
