// Studio's pages through the content workflow.
//
// Studio publishes on save, which is right for one person editing their own
// site and wrong the moment there is a colleague. With the workflow attached
// the Publish button opens or edits a draft, and only a published version is
// written to the page store the router serves. The quiet failures: a save
// that reaches the store anyway, a save during review that is dropped instead
// of refused, a publish that leaves the old page in the cache, a withdrawal
// that leaves the override serving, and a bundle that forgets who approved
// what it carries.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _User {
  const _User(this.id);
  final String id;
}

const _User ada = _User('ada');
const _User grace = _User('grace');

final Map<String, Set<String>> _grants = <String, Set<String>>{};

void main() {
  late SqliteDVDatabaseAdapter database;
  late DVStudioContent content;

  setUpAll(() {
    for (final String action in DVContentAction.all) {
      DV.Auth.authorization.register<_User, DVPageDocument>(
        action,
        (_User user, DVPageDocument document) =>
            _grants[user.id]?.contains(action) ?? false,
      );
    }
  });

  setUp(() async {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    _grants
      ..clear()
      ..['ada'] = <String>{DVContentAction.edit}
      ..['grace'] = <String>{DVContentAction.review, DVContentAction.publish};
    content = DVStudioContent(
      actorId: (Object? user) => (user! as _User).id,
      notify: (String recipient, DVNotificationMessage message) async {},
    );
    await content.workflow.ensureSchema();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  Future<DVContentVersion<DVPageDocument>> publishedPage(
    String route,
    String title,
  ) async {
    final DVStudioEditorController c = DVStudioEditorController(
      DVPageDocument(route: route, title: title),
    );
    content.attach(c, as: ada);
    await c.save();
    final DVContentVersion<DVPageDocument> draft =
        (await content.workflow.versions(route)).last;
    final DVContentVersion<DVPageDocument> review = await content.workflow
        .submit(draft, to: 'grace', as: ada);
    final DVContentVersion<DVPageDocument> approved = await content.workflow
        .approve(review, as: grace);
    return content.workflow.publish(approved, as: grace);
  }

  test('with the workflow attached, Studio save opens a draft and publishes '
      'nothing', () async {
    final DVStudioEditorController c = DVStudioEditorController(
      DVPageDocument(route: '/p', title: 'one'),
    );
    content.attach(c, as: ada);

    await c.save();
    c.document.title = 'two';
    await c.save();

    DVPageStore.resetCache();
    expect(await const DVPageStore().load('/p'), isNull);
    final List<DVContentVersion<DVPageDocument>> versions = await content
        .workflow
        .versions('/p');
    expect(versions.single.state, DVContentState.draft);
    expect(versions.single.document.title, 'two');
    expect(versions.single.revision, 2);
  });

  test(
    'a save while the page is under review is refused, not dropped',
    () async {
      final DVStudioEditorController c = DVStudioEditorController(
        DVPageDocument(route: '/p', title: 'one'),
      );
      content.attach(c, as: ada);
      await c.save();
      await content.workflow.submit(
        (await content.workflow.versions('/p')).single,
        to: 'grace',
        as: ada,
      );

      c.document.title = 'two';
      await expectLater(c.save(), throwsA(isA<DVContentFrozen>()));
      expect(
        (await content.workflow.versions('/p')).single.document.title,
        'one',
      );
    },
  );

  test('a save by someone without the edit action is refused', () async {
    final DVStudioEditorController c = DVStudioEditorController(
      DVPageDocument(route: '/p', title: 'one'),
    );
    content.attach(c, as: const _User('stranger'));
    await expectLater(c.save(), throwsA(isA<DVContentRefused>()));
  });

  test('publishing writes the page store and revalidates the cache entries '
      'tagged for the page', () async {
    await DV.Cache.set('rendered:/p', 'old page',
        tags: <String>[content.workflow.documentTag('/p')]);

    await publishedPage('/p', 'live');

    expect(DVPageStore.cached('/p')!.title, 'live');
    DVPageStore.resetCache();
    expect((await const DVPageStore().load('/p'))!.title, 'live');
    expect(await DV.Cache.get<String>('rendered:/p'), isNull);
  });

  test('editing after publish leaves the live page in the store until the '
      'next version is published', () async {
    await publishedPage('/p', 'live');
    final DVStudioEditorController c = DVStudioEditorController(
      (await const DVPageStore().load('/p'))!,
    );
    content.attach(c, as: ada);
    c.document.title = 'next';
    await c.save();

    DVPageStore.resetCache();
    expect((await const DVPageStore().load('/p'))!.title, 'live');
    expect(
      (await content.workflow.versions('/p')).last.state,
      DVContentState.draft,
    );
  });

  test('withdrawing the published version removes the override, so the '
      'compiled page serves again', () async {
    final DVContentVersion<DVPageDocument> live = await publishedPage(
      '/p',
      'live',
    );
    await content.workflow.withdraw(live, as: grace);
    expect(DVPageStore.cached('/p'), isNull);
    DVPageStore.resetCache();
    expect(await const DVPageStore().load('/p'), isNull);
  });

  test(
    'a bundle carries which version was approved, by whom and when',
    () async {
      final DVContentVersion<DVPageDocument> live = await publishedPage(
        '/p',
        'live',
      );
      await content.workflow.draft(
        DVPageDocument(route: '/q', title: 'unpublished'),
        as: ada,
      );

      final DVPageBundle bundle = await content.bundle(version: '2.0.0');
      final DVPageBundle decoded = DVPageBundle.decode(bundle.encode());

      expect(decoded.pages.map((DVPageDocument p) => p.route), <String>['/p']);
      final DVContentApproval approval = decoded.approvals['/p']!;
      expect(approval.approvedBy, 'grace');
      expect(approval.revision, live.revision);
      expect(approval.digest, live.digest);
    },
  );

  test('a bundle written before approvals existed still decodes', () {
    final DVPageBundle bundle = DVPageBundle.decode(
      '{"version": "1.0.0", "pages": []}',
    );
    expect(bundle.approvals, isEmpty);
  });
}
