// Drafts, revisions and schedules in Studio as a web-server binary serves it.
//
// Autosave writes a draft. Only Publish, or a schedule arriving, changes what
// a visitor is served -- which is the line between an editor and a live
// site, and the one the editor used to cross every two seconds.
import 'package:dartvel_core/dartvel.dart'
    show
        DVContentState,
        DVContentVersion,
        DVStudioApi,
        MemoryDVDatabaseAdapter;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument _page(String route, String title) =>
    DVPageDocument(route: route, title: title);

void main() {
  late MemoryDVDatabaseAdapter database;
  late DVStudioClient client;
  late DVStudioRemoteVersions versions;

  setUp(() {
    database = MemoryDVDatabaseAdapter();
    client = DVStudioClient(
      dvStudioInProcessTransport(
        DVStudioApi(database: database, caller: (_) async => 'ada'),
      ),
    );
    versions = DVStudioRemoteVersions(client);
  });

  /// What a visitor is served: the published pages, by route.
  Future<Map<String, String?>> served() async => <String, String?>{
    for (final DVStudioPageEntry page in await client.pageEntries())
      if (page.published) page.route: page.document.title,
  };

  group('the remote versions', () {
    test('a draft is saved beside the published page, not over it', () async {
      await client.savePage(_page('/sale', 'Autumn'));
      await versions.saveDraft(_page('/sale', 'Winter'), as: 'ada');

      expect(await served(), <String, String?>{'/sale': 'Autumn'});
      final List<DVContentVersion<DVPageDocument>> all =
          await versions.versions('/sale');
      expect(
        <DVContentState>[for (final v in all) v.state],
        <DVContentState>[DVContentState.published, DVContentState.draft],
      );
      expect(all.last.document.title, 'Winter');
      expect(all.last.editors, <String>{'ada'});
    });

    test('publishing the open version serves it', () async {
      final DVContentVersion<DVPageDocument> draft =
          await versions.saveDraft(_page('/sale', 'Winter'), as: 'ada');
      await versions.publish(draft, as: 'ada');
      expect(await served(), <String, String?>{'/sale': 'Winter'});
    });

    test('a revision is restored, and the history says so', () async {
      await client.savePage(_page('/about', 'One'));
      await client.savePage(_page('/about', 'Two'));
      final DVContentVersion<DVPageDocument> first =
          (await versions.versions('/about')).first;
      expect(first.state, DVContentState.superseded);

      await versions.restore(first, as: 'ada');
      expect(await served(), <String, String?>{'/about': 'One'});
      expect(
        (await versions.history('/about'))
            .where((t) => t.version == 1 && t.to == DVContentState.published),
        hasLength(2),
      );
    });

    test('a version read before somebody else moved it is refused', () async {
      final DVContentVersion<DVPageDocument> read =
          await versions.saveDraft(_page('/about', 'A'), as: 'ada');
      await versions.saveDraft(_page('/about', 'B'), as: 'ada');
      await expectLater(
        versions.publish(read, as: 'ada'),
        throwsA(isA<DVStudioRemoteError>()
            .having((e) => e.status, 'status', 409)),
      );
      expect(await served(), isEmpty);
    });

    test('a schedule is kept by the server', () async {
      final DVContentVersion<DVPageDocument> draft =
          await versions.saveDraft(_page('/launch', 'Launch'), as: 'ada');
      final DVContentVersion<DVPageDocument> scheduled = await versions
          .schedule(draft, at: DateTime.now().add(const Duration(days: 1)),
              as: 'ada');
      expect(scheduled.state, DVContentState.scheduled);
      expect(
        (await versions.cancelSchedule(scheduled, as: 'ada')).state,
        DVContentState.draft,
      );
    });

    test('the page store opens a page at its draft', () async {
      await client.savePage(_page('/about', 'Published'));
      await versions.saveDraft(_page('/about', 'Being written'), as: 'ada');
      final DVStudioRemotePageStore store = DVStudioRemotePageStore(client);
      expect((await store.load('/about'))!.title, 'Being written');
      await store.saveDraft(_page('/about', 'Written'));
      expect(await served(), <String, String?>{'/about': 'Published'});
    });
  });

  group('autosave', () {
    testWidgets('writes a draft and never publishes', (WidgetTester tester) async {
      final List<String> drafts = <String>[];
      final List<String> published = <String>[];
      final DVStudioEditorController controller = DVStudioEditorController(
        _page('/home', 'Home'),
      )
        ..draftSaver = ((DVPageDocument d) async => drafts.add(d.title))
        ..publisher =
            ((DVPageDocument d) async => published.add(d.title));
      addTearDown(controller.dispose);

      controller.insert(DVPageNode.text('Hello'),
          parent: controller.document.root.id);
      await tester.pump(controller.autosaveInterval);
      expect(drafts, hasLength(1));
      expect(published, isEmpty);
      expect(controller.autosaveStatus, DVStudioAutosaveStatus.saved);
    });

    testWidgets('with nowhere to keep a draft, nothing is saved on its own',
        (WidgetTester tester) async {
      final List<String> published = <String>[];
      final DVStudioEditorController controller = DVStudioEditorController(
        _page('/home', 'Home'),
      )..publisher = (DVPageDocument d) async => published.add(d.title);
      addTearDown(controller.dispose);

      controller.insert(DVPageNode.text('Hello'),
          parent: controller.document.root.id);
      await tester.pump(const Duration(minutes: 1));
      expect(published, isEmpty);
      expect(controller.autosaveStatus, DVStudioAutosaveStatus.dirty);
    });

    testWidgets('a failed autosave is shown and tried again, not thrown',
        (WidgetTester tester) async {
      int attempts = 0;
      final DVStudioEditorController controller = DVStudioEditorController(
        _page('/home', 'Home'),
      )..draftSaver = (DVPageDocument d) async {
          attempts++;
          if (attempts == 1) throw StateError('offline');
        };
      addTearDown(controller.dispose);

      controller.insert(DVPageNode.text('Hello'),
          parent: controller.document.root.id);
      await tester.pump(controller.autosaveInterval);
      expect(attempts, 1);
      expect(controller.autosaveStatus, DVStudioAutosaveStatus.error);

      await tester.pump(const Duration(seconds: 30));
      expect(attempts, 2);
      expect(controller.autosaveStatus, DVStudioAutosaveStatus.saved);
    });
  });
}
