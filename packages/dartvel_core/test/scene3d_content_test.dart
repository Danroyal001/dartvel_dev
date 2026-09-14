// Scene documents as content: stored through the database, versioned through
// the content workflow, and delivered to installed applications as bundles.
//
// The quiet failures: a stored scene that reads back with a unit or a digit
// missing, a draft that reaches the store, a withdrawal that leaves the scene
// serving, a bundle applied twice that undoes an edit made since, and a bundle
// with one malformed scene that writes the others before failing.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _User {
  const _User(this.id);
  final String id;
}

const _User ada = _User('ada');
const _User grace = _User('grace');

final Map<String, Set<String>> _grants = <String, Set<String>>{
  'ada': <String>{DVContentAction.edit},
  'grace': <String>{DVContentAction.review, DVContentAction.publish},
};

DV3DSceneDocument _scene(String id, {double x = 0.30000000000000004}) =>
    DV3DSceneDocument(
      id: id,
      units: DVSceneUnits.centimeters,
      handedness: DVSceneHandedness.left,
      nodes: <DVSceneNodeData>[
        DVSceneNodeData.mesh(
          id: 'sign',
          primitive: const DVScenePrimitive.box(DVVec3(120, 40, 2)),
          transform: DVTransform(translation: DVVec3(x, 1e-7, -250)),
        ),
      ],
      extra: const <String, Object?>{'lod': <String, Object?>{'levels': 3}},
    );

void main() {
  setUpAll(() {
    for (final String action in DVContentAction.all) {
      const DVAuthAuthorization().register<_User, DV3DSceneDocument>(
        action,
        (_User user, DV3DSceneDocument scene) =>
            _grants[user.id]?.contains(action) ?? false,
      );
    }
  });

  for (final (String name, DVDatabaseAdapter Function() create)
      in <(String, DVDatabaseAdapter Function())>[
    ('memory', MemoryDVDatabaseAdapter.new),
    ('sqlite', SqliteDVDatabaseAdapter.memory),
  ]) {
    group('the store on $name', () {
      late DV3DSceneStore store;
      setUp(() async {
        store = DV3DSceneStore(create());
        await store.ensureSchema();
      });

      test('a saved scene reads back byte for byte', () async {
        await store.save(_scene('lobby'));
        expect((await store.load('lobby'))!.encode(), _scene('lobby').encode());
      });

      test('saving again replaces, and deleting removes', () async {
        await store.save(_scene('lobby'));
        await store.save(_scene('lobby', x: 9));
        expect((await store.load('lobby'))!.nodes.single.transform.translation.x, 9);
        expect(await store.ids(), <String>['lobby']);
        await store.delete('lobby');
        expect(await store.load('lobby'), isNull);
      });

      test('a stored scene that no longer decodes throws, not reads as absent',
          () async {
        await store.save(_scene('lobby'));
        await store.database.execute(
          'UPDATE ${DV3DSceneStore.table} SET document = ? WHERE id = ?',
          <Object?>['{"format":1,"id":"lobby","nodes":[{"id":"x","kind":"model"}]}', 'lobby'],
        );
        await expectLater(store.load('lobby'), throwsA(isA<DV3DSceneFormatException>()));
      });

      test('every change is announced', () async {
        final List<String> changed = <String>[];
        store.changes.listen(changed.add);
        await store.save(_scene('a'));
        await store.delete('a');
        await Future<void>.delayed(Duration.zero);
        expect(changed, <String>['a', 'a']);
      });
    });
  }

  group('through the content workflow', () {
    late DV3DSceneContent content;
    setUp(() async {
      content = DV3DSceneContent(
        actorId: (Object? user) => (user! as _User).id,
        database: SqliteDVDatabaseAdapter.memory(),
        notify: (String recipient, DVNotificationMessage message) async {},
      );
      await content.ensureSchema();
    });

    Future<DVContentVersion<DV3DSceneDocument>> publish(DV3DSceneDocument scene) async {
      final DVContentVersion<DV3DSceneDocument> draft =
          await content.workflow.draft(scene, as: ada);
      final DVContentVersion<DV3DSceneDocument> review =
          await content.workflow.submit(draft, to: 'grace', as: ada);
      final DVContentVersion<DV3DSceneDocument> approved =
          await content.workflow.approve(review, as: grace);
      return content.workflow.publish(approved, as: grace);
    }

    test('scenes are their own content kind', () {
      expect(content.workflow.kind, 'scene');
    });

    test('a draft never reaches the store; a publish writes it exactly', () async {
      final DVContentVersion<DV3DSceneDocument> draft =
          await content.workflow.draft(_scene('lobby'), as: ada);
      expect(await content.store.load('lobby'), isNull);

      final DVContentVersion<DV3DSceneDocument> review =
          await content.workflow.submit(draft, to: 'grace', as: ada);
      expect(await content.store.load('lobby'), isNull);
      final DVContentVersion<DV3DSceneDocument> approved =
          await content.workflow.approve(review, as: grace);
      expect(await content.store.load('lobby'), isNull);
      final DVContentVersion<DV3DSceneDocument> published =
          await content.workflow.publish(approved, as: grace);

      expect(published.state, DVContentState.published);
      expect((await content.store.load('lobby'))!.encode(), _scene('lobby').encode());
    });

    test('withdrawing a published scene takes it out of the store', () async {
      final DVContentVersion<DV3DSceneDocument> published = await publish(_scene('lobby'));
      await content.workflow.withdraw(published, as: grace);
      expect(await content.store.load('lobby'), isNull);
    });

    test('a bundle carries every published scene and who approved it', () async {
      await publish(_scene('lobby'));
      await content.workflow.draft(_scene('draft-only'), as: ada);

      final DV3DSceneBundle bundle = await content.bundle(version: '2026.09.14');

      expect(bundle.scenes.map((DV3DSceneDocument s) => s.id), <String>['lobby']);
      expect(bundle.approvals['lobby']!.approvedBy, 'grace');
      final DV3DSceneBundle back = DV3DSceneBundle.decode(bundle.encode());
      expect(back.scenes.single.encode(), _scene('lobby').encode());
      expect(back.approvals['lobby']!.digest, bundle.approvals['lobby']!.digest);
    });
  });

  group('bundles on an installed application', () {
    late DV3DSceneStore store;
    late DV3DSceneBundleInstaller installer;
    setUp(() async {
      store = DV3DSceneStore(SqliteDVDatabaseAdapter.memory());
      installer = DV3DSceneBundleInstaller(store);
      await store.ensureSchema();
    });

    test('applying a bundle writes its scenes and records its version', () async {
      expect(await installer.apply(DV3DSceneBundle(
          version: 'v1', scenes: <DV3DSceneDocument>[_scene('lobby')])), isTrue);
      expect((await store.load('lobby'))!.encode(), _scene('lobby').encode());
      expect(await installer.appliedVersions(), <String>['v1']);
    });

    test('a bundle delivered twice does not undo an edit made since', () async {
      final DV3DSceneBundle v1 =
          DV3DSceneBundle(version: 'v1', scenes: <DV3DSceneDocument>[_scene('lobby')]);
      await installer.apply(v1);
      await store.save(_scene('lobby', x: 42));

      expect(await installer.apply(v1), isFalse);

      expect((await store.load('lobby'))!.nodes.single.transform.translation.x, 42);
    });

    test('rollback is shipping the previous bundle again, once it is forgotten',
        () async {
      await installer.apply(
          DV3DSceneBundle(version: 'v1', scenes: <DV3DSceneDocument>[_scene('lobby')]));
      await installer.apply(DV3DSceneBundle(
          version: 'v2', scenes: <DV3DSceneDocument>[_scene('lobby', x: 7)]));

      await installer.forget('v1');
      expect(await installer.apply(
          DV3DSceneBundle(version: 'v1', scenes: <DV3DSceneDocument>[_scene('lobby')])),
          isTrue);

      expect((await store.load('lobby'))!.encode(), _scene('lobby').encode());
    });

    test('a bundle removes the scenes it names', () async {
      await store.save(_scene('old'));
      await installer.apply(const DV3DSceneBundle(
          version: 'v2', removedScenes: <String>['old']));
      expect(await store.load('old'), isNull);
    });

    test('a bundle with one malformed scene is refused whole, before any write',
        () async {
      final Map<String, Object?> json = DV3DSceneBundle(
        version: 'v3',
        scenes: <DV3DSceneDocument>[_scene('good'), _scene('bad')],
      ).toJson();
      final Map<String, Object?> bad =
          ((json['scenes']! as List<Object?>)[1]! as Map<String, Object?>);
      ((bad['nodes']! as List<Object?>).first! as Map<String, Object?>)['transform'] =
          <String, Object?>{'s': <Object?>[1, 0, 1]};

      expect(
        () => DV3DSceneBundle.fromJson(json),
        throwsA(isA<DV3DSceneFormatException>().having(
            (DV3DSceneFormatException e) => e.path, 'path', startsWith('scenes[1].'))),
      );
      expect(await store.ids(), isEmpty);
    });

    test('a bundle delivered as JSON that ships one scene twice is refused on decode',
        () {
      // What arrives over the air is JSON; checking only the typed object
      // would let the second copy of a scene silently win on apply.
      final Map<String, Object?> json = DV3DSceneBundle(
        version: 'v5',
        scenes: <DV3DSceneDocument>[_scene('lobby')],
      ).toJson();
      (json['scenes']! as List<Object?>).add(_scene('lobby', x: 1).toJson());
      expect(() => DV3DSceneBundle.fromJson(json),
          throwsA(isA<DV3DSceneFormatException>()));
    });

    test('a bundle that ships and removes one scene, or ships it twice, is refused',
        () {
      expect(
        () => DV3DSceneBundle(
            version: 'v4',
            scenes: <DV3DSceneDocument>[_scene('lobby')],
            removedScenes: const <String>['lobby']).validate(),
        throwsA(isA<DV3DSceneFormatException>()),
      );
      expect(
        () => DV3DSceneBundle(
            version: 'v4',
            scenes: <DV3DSceneDocument>[_scene('lobby'), _scene('lobby', x: 1)]).validate(),
        throwsA(isA<DV3DSceneFormatException>()),
      );
      expect(() => const DV3DSceneBundle(version: '').validate(),
          throwsA(isA<DV3DSceneFormatException>()));
    });
  });
}
