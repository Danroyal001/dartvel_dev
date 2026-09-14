// Studio's editor with the content workflow attached, driven the way an author
// and a reviewer drive it.
//
// The runtime already refuses the wrong transition; what this holds the UI to
// is not hiding that. The quiet failures: a Publish button on content that
// changed since it was approved, which then fails with nothing on screen; an
// action the policy refuses offered as if it would work; a refusal or a stale
// snapshot swallowed so the page looks published and is not; a draft-only
// page missing from the page list because the store only holds published
// pages; and a Studio without the workflow that changed anyway.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _User {
  const _User(this.id);
  final String id;
}

const _User ada = _User('ada');
const _User grace = _User('grace');

final Map<String, Set<String>> _grants = <String, Set<String>>{};

final DateTime _now = DateTime.utc(2026, 9, 14, 8);

DVPageDocument documentFor(String route, String text, {num fontSize = 24}) {
  final DVPageDocument document = DVPageDocument(route: route, title: route);
  DVPageDocumentEditor(document).insert(
    DVPageNode(
      id: 'heading',
      type: 'text',
      properties: <String, Object?>{'text': text, 'fontSize': fontSize},
    ),
    parent: document.root.id,
  );
  return document;
}

const ValueKey<String> primary = ValueKey<String>('dv-studio-content-primary');

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

  DVStudioContent makeContent({bool previewKey = true}) => DVStudioContent(
    actorId: (Object? user) => (user! as _User).id,
    findActor: (String id) async => _User(id),
    previewKey: previewKey ? List<int>.generate(32, (int i) => i) : null,
    notify: (String recipient, DVNotificationMessage message) async {},
    clock: () => _now,
  );

  setUp(() async {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    _grants
      ..clear()
      ..['ada'] = <String>{DVContentAction.edit}
      ..['grace'] = <String>{
        DVContentAction.review,
        DVContentAction.publish,
        DVContentAction.schedule,
      };
    content = makeContent();
    await content.workflow.ensureSchema();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  DVContentWorkflow<DVPageDocument> wf() => content.workflow;

  Future<DVContentVersion<DVPageDocument>> latest(String route) async =>
      (await wf().versions(route)).last;

  Future<DVContentVersion<DVPageDocument>> draft(
    String route, [
    String text = 'Plans',
  ]) => wf().draft(documentFor(route, text), as: ada);

  Future<DVContentVersion<DVPageDocument>> inReview(
    String route, [
    String text = 'Plans',
  ]) async => wf().submit(await draft(route, text), to: 'grace', as: ada);

  Future<DVContentVersion<DVPageDocument>> approved(
    String route, [
    String text = 'Plans',
  ]) async => wf().approve(await inReview(route, text), as: grace);

  Future<DVContentVersion<DVPageDocument>> published(
    String route, [
    String text = 'Plans',
  ]) async => wf().publish(await approved(route, text), as: grace);

  Future<void> pumpStudio(
    WidgetTester tester, {
    required Object? actor,
    DVStudioContent? using,
    Size size = const Size(1440, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: DVStudioScreen(content: using ?? content, actor: actor),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPage(WidgetTester tester, String route) async {
    await tester.tap(find.byKey(ValueKey<String>('dv-studio-route-$route')));
    await tester.pumpAndSettle();
  }

  Finder inKey(String key, Finder matching) => find.descendant(
    of: find.byKey(ValueKey<String>(key)),
    matching: matching,
  );

  GestureDetector control(WidgetTester tester, String key) =>
      tester.widget<GestureDetector>(find.byKey(ValueKey<String>(key)));

  String tooltipOf(WidgetTester tester, Key key) => tester
      .widget<Tooltip>(
        find
            .ancestor(of: find.byKey(key), matching: find.byType(Tooltip))
            .first,
      )
      .message!;

  String primaryLabel(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(of: find.byKey(primary), matching: find.byType(Text)),
      )
      .map((Text t) => t.data ?? '')
      .join();

  Future<void> typeInto(WidgetTester tester, String key, String text) async {
    await tester.enterText(inKey(key, find.byType(EditableText)), text);
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
  }

  group('without the workflow', () {
    testWidgets('the editor keeps Publish and shows no workflow state', (
      WidgetTester tester,
    ) async {
      await const DVPageStore().save(documentFor('/pricing', 'Plans'));
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: Material(child: DVStudioScreen())),
      );
      await tester.pumpAndSettle();
      await openPage(tester, '/pricing');

      expect(
        find.byKey(const ValueKey<String>('dv-studio-publish')),
        findsOneWidget,
      );
      expect(find.byKey(primary), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('dv-studio-content-state')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('dv-studio-history')),
        findsNothing,
      );
    });
  });

  group('the page overview', () {
    testWidgets('a page edited after its approval is badged as changed, not '
        'as approved', (WidgetTester tester) async {
      final DVContentVersion<DVPageDocument> ok = await approved('/p');
      await wf().edit(ok, documentFor('/p', 'Changed after'), as: ada);

      await pumpStudio(tester, actor: grace);

      expect(
        inKey('dv-studio-route-state-/p', find.text('Approved')),
        findsNothing,
        reason: 'an approval that no longer covers the content is not one',
      );
      expect(
        inKey('dv-studio-route-state-/p', find.text('Changed')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-card-state-/p', find.text('Changed')),
        findsOneWidget,
      );
    });

    testWidgets('shows each page\'s state, lists draft-only pages, and counts '
        'what needs review', (WidgetTester tester) async {
      await published('/pricing');
      await wf().draft(documentFor('/pricing', 'New plans'), as: ada);
      await inReview('/about');
      await draft('/new');

      await pumpStudio(tester, actor: ada);

      expect(
        find.byKey(const ValueKey<String>('dv-studio-route-/new')),
        findsOneWidget,
        reason:
            'a page with only a draft is not in the store, and is still '
            'a page',
      );
      expect(
        inKey('dv-studio-route-state-/about', find.text('In review')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-route-state-/pricing', find.text('Draft')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-card-state-/about', find.text('In review')),
        findsOneWidget,
      );
      expect(inKey('dv-studio-needs-review', find.text('1')), findsOneWidget);
    });

    testWidgets('opening a draft-only page edits the draft', (
      WidgetTester tester,
    ) async {
      await draft('/new', 'Draft words');
      await pumpStudio(tester, actor: ada);
      await openPage(tester, '/new');

      expect(find.text('Draft words'), findsOneWidget);
      expect(
        inKey('dv-studio-content-state', find.text('Draft')),
        findsOneWidget,
      );
    });
  });

  group('the toolbar', () {
    testWidgets('an author submits a draft for review through the review '
        'panel', (WidgetTester tester) async {
      await draft('/p');
      await pumpStudio(tester, actor: ada);
      await openPage(tester, '/p');

      expect(primaryLabel(tester), 'Submit for review…');
      await tester.tap(find.byKey(primary));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('dv-studio-review-panel')),
        findsOneWidget,
      );

      await typeInto(tester, 'dv-studio-review-reviewer', 'grace');
      await tapKey(tester, 'dv-studio-review-submit');

      final DVContentVersion<DVPageDocument> v = await latest('/p');
      expect(v.state, DVContentState.review);
      expect(v.reviewer, 'grace');
      expect(
        inKey('dv-studio-content-state', find.text('In review')),
        findsOneWidget,
      );
    });

    testWidgets('submitting saves unsaved edits first, so the reviewer sees '
        'what the author sees', (WidgetTester tester) async {
      await draft('/p', 'Plans');
      await pumpStudio(tester, actor: ada);
      await openPage(tester, '/p');

      await tester.tap(find.text('Plans'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText).last, 'Better plans');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(primary));
      await tester.pumpAndSettle();
      await typeInto(tester, 'dv-studio-review-reviewer', 'grace');
      await tapKey(tester, 'dv-studio-review-submit');

      final DVContentVersion<DVPageDocument> v = await latest('/p');
      expect(v.state, DVContentState.review);
      expect(v.revision, 2);
    });

    testWidgets('a reviewer approves, and the approval record names who, when '
        'and which revision', (WidgetTester tester) async {
      await inReview('/p');
      await pumpStudio(tester, actor: grace);
      await openPage(tester, '/p');

      expect(primaryLabel(tester), 'Approve');
      await tester.tap(find.byKey(primary));
      await tester.pumpAndSettle();

      expect((await latest('/p')).state, DVContentState.approved);
      expect(
        inKey('dv-studio-content-state', find.text('Approved')),
        findsOneWidget,
      );
      await tapKey(tester, 'dv-studio-review');
      expect(
        inKey('dv-studio-review-approval', find.textContaining('grace')),
        findsWidgets,
      );
      expect(
        inKey('dv-studio-review-approval', find.textContaining('revision 1')),
        findsOneWidget,
      );
      expect(
        inKey('dv-studio-review-approval', find.textContaining('14 Sep 2026')),
        findsOneWidget,
      );
    });

    testWidgets('approve is disabled, with the reason, when the policy refuses '
        'it', (WidgetTester tester) async {
      await inReview('/p');
      await pumpStudio(tester, actor: ada);
      await openPage(tester, '/p');

      expect(primaryLabel(tester), 'Approve');
      expect(control(tester, primary.value).onTap, isNull);
      expect(
        tooltipOf(tester, primary),
        contains('lacks the "review" policy action'),
      );
    });

    testWidgets('an editor with review still cannot approve their own work '
        'without reviewOwn', (WidgetTester tester) async {
      _grants['ada']!.add(DVContentAction.review);
      await inReview('/p');
      await pumpStudio(tester, actor: ada);
      await openPage(tester, '/p');

      expect(control(tester, primary.value).onTap, isNull);
      expect(tooltipOf(tester, primary), contains('reviewOwn'));
    });

    testWidgets('requesting changes sends it back to draft with the reason, '
        'and the author sees the reason', (WidgetTester tester) async {
      await inReview('/p');
      await pumpStudio(tester, actor: grace);
      await openPage(tester, '/p');
      await tapKey(tester, 'dv-studio-review');

      await typeInto(tester, 'dv-studio-review-note', 'Fix the price');
      await tapKey(tester, 'dv-studio-review-request-changes');

      final DVContentVersion<DVPageDocument> v = await latest('/p');
      expect(v.state, DVContentState.draft);
      expect(v.note, 'Fix the price');

      await pumpStudio(tester, actor: ada);
      await openPage(tester, '/p');
      await tapKey(tester, 'dv-studio-review');
      expect(find.textContaining('Fix the price'), findsOneWidget);
    });

    testWidgets('content changed since approval shows the warning instead of a '
        'publish button', (WidgetTester tester) async {
      final DVContentVersion<DVPageDocument> ok = await approved('/p');
      await wf().edit(ok, documentFor('/p', 'Changed after'), as: ada);

      await pumpStudio(tester, actor: grace);
      await openPage(tester, '/p');

      expect(
        find.byKey(const ValueKey<String>('dv-studio-content-changed')),
        findsOneWidget,
      );
      // The pill says so too: "Approved" over content the approval does not
      // cover is the same quiet failure as a Publish button.
      expect(
        inKey('dv-studio-content-state', find.textContaining('Approved')),
        findsNothing,
      );
      expect(
        inKey('dv-studio-content-state', find.textContaining('Changed')),
        findsOneWidget,
      );
      expect(primaryLabel(tester), isNot(contains('Publish')));
      await tapKey(tester, 'dv-studio-review');
      expect(
        find.byKey(const ValueKey<String>('dv-studio-content-changed')),
        findsWidgets,
      );
      expect(
        inKey('dv-studio-review-panel', find.textContaining('DV-CONTENT-002')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('dv-studio-review-publish')),
        findsNothing,
      );
    });

    testWidgets('a publish the policy refuses after the page loaded is shown '
        'inline, not swallowed', (WidgetTester tester) async {
      await approved('/p');
      await pumpStudio(tester, actor: grace);
      await openPage(tester, '/p');
      expect(primaryLabel(tester), 'Publish');

      _grants['grace']!.remove(DVContentAction.publish);
      await tester.tap(find.byKey(primary));
      await tester.pumpAndSettle();

      expect(
        inKey('dv-studio-content-error', find.textContaining('DV-CONTENT-003')),
        findsOneWidget,
      );
      expect((await latest('/p')).state, DVContentState.approved);
      expect(await const DVPageStore().load('/p'), isNull);
    });

    testWidgets(
      'acting on a stale snapshot says the page moved and reloads it',
      (WidgetTester tester) async {
        await inReview('/p');
        await pumpStudio(tester, actor: grace);
        await openPage(tester, '/p');

        // Somebody else sends it back while this screen still shows review.
        await wf().requestChanges(await latest('/p'), as: grace, note: 'x');
        await tester.tap(find.byKey(primary));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey<String>('dv-studio-content-error')),
          findsOneWidget,
        );
        expect(
          inKey('dv-studio-content-error', find.textContaining('changed')),
          findsWidgets,
        );
        expect(
          inKey('dv-studio-content-state', find.text('Draft')),
          findsOneWidget,
        );
        expect((await latest('/p')).state, DVContentState.draft);
      },
    );

    testWidgets('publishing an approved version writes the store and shows '
        'Published', (WidgetTester tester) async {
      await approved('/p');
      await pumpStudio(tester, actor: grace);
      await openPage(tester, '/p');

      await tester.tap(find.byKey(primary));
      await tester.pumpAndSettle();

      expect((await latest('/p')).state, DVContentState.published);
      expect((await const DVPageStore().load('/p'))!.title, '/p');
      expect(
        inKey('dv-studio-content-state', find.text('Published')),
        findsOneWidget,
      );
    });

    testWidgets(
      'discarding a draft withdraws it through the workflow and keeps '
      'the published page',
      (WidgetTester tester) async {
        await published('/p');
        await wf().draft(documentFor('/p', 'Next'), as: ada);
        await pumpStudio(tester, actor: ada);
        await openPage(tester, '/p');

        await tapKey(tester, 'dv-studio-revert');

        expect((await latest('/p')).state, DVContentState.withdrawn);
        DVPageStore.resetCache();
        expect(await const DVPageStore().load('/p'), isNotNull);
      },
    );
  });

  group('scheduling', () {
    testWidgets(
      'a slot picked in the dialog schedules the version and shows on '
      'the pill; removing it returns to approved',
      (WidgetTester tester) async {
        await approved('/p');
        await pumpStudio(tester, actor: grace);
        await openPage(tester, '/p');

        await tapKey(tester, 'dv-studio-schedule');
        expect(
          find.byKey(const ValueKey<String>('dv-studio-schedule-dialog')),
          findsOneWidget,
        );
        await tapKey(tester, 'dv-studio-schedule-day-2026-09-20');
        await typeInto(tester, 'dv-studio-schedule-time', '14:30');
        await tapKey(tester, 'dv-studio-schedule-confirm');

        final DVContentVersion<DVPageDocument> v = await latest('/p');
        expect(v.state, DVContentState.scheduled);
        final DateTime at = v.scheduledAt!.toLocal();
        expect(
          <int>[at.year, at.month, at.day, at.hour, at.minute],
          <int>[2026, 9, 20, 14, 30],
        );
        expect(
          find.byKey(const ValueKey<String>('dv-studio-schedule-dialog')),
          findsNothing,
        );
        expect(
          inKey(
            'dv-studio-content-state',
            find.textContaining('20 Sep, 14:30'),
          ),
          findsOneWidget,
        );

        await tapKey(tester, 'dv-studio-schedule');
        await tapKey(tester, 'dv-studio-schedule-remove');
        expect((await latest('/p')).state, DVContentState.approved);
      },
    );

    testWidgets('rescheduling moves the slot', (WidgetTester tester) async {
      await approved('/p');
      await wf().schedule(
        await latest('/p'),
        at: DateTime(2026, 9, 20, 14, 30),
        as: grace,
      );
      await pumpStudio(tester, actor: grace);
      await openPage(tester, '/p');

      await tapKey(tester, 'dv-studio-schedule');
      await tapKey(tester, 'dv-studio-schedule-day-2026-09-21');
      await tapKey(tester, 'dv-studio-schedule-confirm');

      final DVContentVersion<DVPageDocument> v = await latest('/p');
      expect(v.state, DVContentState.scheduled);
      expect(v.scheduledAt!.toLocal().day, 21);
    });

    testWidgets('a slot in the past cannot be confirmed', (
      WidgetTester tester,
    ) async {
      await approved('/p');
      await pumpStudio(tester, actor: grace);
      await openPage(tester, '/p');

      await tapKey(tester, 'dv-studio-schedule');
      await tapKey(tester, 'dv-studio-schedule-day-2026-09-14');
      await typeInto(tester, 'dv-studio-schedule-time', '00:15');

      expect(control(tester, 'dv-studio-schedule-confirm').onTap, isNull);
      expect(
        inKey('dv-studio-schedule-dialog', find.textContaining('past')),
        findsOneWidget,
      );
    });
  });

  group('history', () {
    testWidgets(
      'lists versions with state and author, and shows what a version '
      'changes against published in words',
      (WidgetTester tester) async {
        await published('/p', 'Plans');
        final DVPageDocument next = documentFor('/p', 'Plans', fontSize: 32);
        DVPageDocumentEditor(next).insert(
          DVPageNode(
            id: 'cta',
            type: 'text',
            properties: <String, Object?>{'text': 'Buy now'},
          ),
          parent: next.root.id,
        );
        await wf().draft(next, as: ada);

        await pumpStudio(tester, actor: grace);
        await openPage(tester, '/p');
        await tapKey(tester, 'dv-studio-history');

        expect(
          find.byKey(const ValueKey<String>('dv-studio-history-panel')),
          findsOneWidget,
        );
        expect(
          inKey('dv-studio-history-version-1', find.text('Published')),
          findsOneWidget,
        );
        expect(
          inKey('dv-studio-history-version-2', find.text('Draft')),
          findsOneWidget,
        );
        expect(
          inKey('dv-studio-history-version-2', find.textContaining('ada')),
          findsWidgets,
        );

        await tapKey(tester, 'dv-studio-history-version-2');
        final Finder diff = find.byKey(
          const ValueKey<String>('dv-studio-diff'),
        );
        expect(
          find.descendant(of: diff, matching: find.text('fontSize')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: diff, matching: find.text('24')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: diff, matching: find.text('32')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: diff, matching: find.textContaining('Buy now')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: diff, matching: find.textContaining('Added')),
          findsWidgets,
        );
        expect(
          find.descendant(of: diff, matching: find.textContaining('"root"')),
          findsNothing,
          reason: 'readable, not raw JSON',
        );
      },
    );

    testWidgets('a superseded version can be restored', (
      WidgetTester tester,
    ) async {
      await published('/p', 'First');
      final DVContentVersion<DVPageDocument> second = await wf().approve(
        await wf().submit(
          await wf().draft(documentFor('/p', 'Second'), as: ada),
          to: 'grace',
          as: ada,
        ),
        as: grace,
      );
      await wf().publish(second, as: grace);

      await pumpStudio(tester, actor: grace);
      await openPage(tester, '/p');
      await tapKey(tester, 'dv-studio-history');
      await tapKey(tester, 'dv-studio-history-version-2');
      expect(
        find.byKey(const ValueKey<String>('dv-studio-history-restore')),
        findsNothing,
        reason: 'only a superseded version is restored',
      );

      await tapKey(tester, 'dv-studio-history-version-1');
      await tapKey(tester, 'dv-studio-history-restore');

      final List<DVContentVersion<DVPageDocument>> versions = await wf()
          .versions('/p');
      expect(versions.first.state, DVContentState.published);
      expect(versions.last.state, DVContentState.superseded);
      DVPageStore.resetCache();
      expect(
        (await const DVPageStore().load(
          '/p',
        ))!.root.children.single.properties['text'],
        'First',
      );
    });
  });

  group('preview', () {
    testWidgets('creates a signed link with its expiry and copies it', (
      WidgetTester tester,
    ) async {
      final List<String> copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add(
              (call.arguments as Map<Object?, Object?>)['text']! as String,
            );
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await draft('/p');
      await pumpStudio(tester, actor: ada);
      await openPage(tester, '/p');
      await tapKey(tester, 'dv-studio-review');
      await tapKey(tester, 'dv-studio-preview-create');

      final String link = tester
          .widget<Text>(inKey('dv-studio-preview-link', find.byType(Text)))
          .data!;
      expect(link, startsWith('/p?preview='));
      final String token = Uri.parse(link).queryParameters['preview']!;
      final DVContentServed<DVPageDocument>? served = await wf().resolve(
        '/p',
        preview: token,
      );
      expect(served!.isPreview, isTrue);
      expect(
        inKey('dv-studio-review-panel', find.textContaining('Expires')),
        findsOneWidget,
      );

      await tapKey(tester, 'dv-studio-preview-copy');
      expect(copied, <String>[link]);
    });

    testWidgets('without a preview key the refusal is shown', (
      WidgetTester tester,
    ) async {
      final DVStudioContent keyless = makeContent(previewKey: false);
      await keyless.workflow.draft(documentFor('/p', 'Plans'), as: ada);
      await pumpStudio(tester, actor: ada, using: keyless);
      await openPage(tester, '/p');
      await tapKey(tester, 'dv-studio-review');
      await tapKey(tester, 'dv-studio-preview-create');

      expect(
        inKey('dv-studio-content-error', find.textContaining('previewKey')),
        findsOneWidget,
      );
    });
  });

  group('fits', () {
    for (final Size size in const <Size>[
      Size(800, 600),
      Size(1024, 700),
      Size(1920, 1080),
    ]) {
      testWidgets('the review panel, schedule dialog and history at '
          '${size.width.toInt()}x${size.height.toInt()}', (
        WidgetTester tester,
      ) async {
        await published('/pricing');
        await approved('/about');
        await pumpStudio(tester, actor: grace, size: size);
        expect(tester.takeException(), isNull);

        await openPage(tester, '/about');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'dv-studio-review');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'dv-studio-schedule');
        expect(tester.takeException(), isNull);
        await tapKey(tester, 'dv-studio-schedule-cancel');
        await tapKey(tester, 'dv-studio-history');
        await tapKey(tester, 'dv-studio-history-version-1');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
