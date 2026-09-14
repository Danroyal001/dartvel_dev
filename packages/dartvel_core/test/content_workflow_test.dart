// Content workflow: draft, review, scheduled and published states on stored
// documents, against the adapters Dartvel runs on without a network.
//
// Every failure worth a test here is a quiet one. An approval granted on one
// revision that publishes the next ships text nobody reviewed, and looks like
// a normal publish. A reviewer approving their own draft looks like a review.
// A scheduled publish that fires twice, fires after it was cancelled, or fires
// after the content was withdrawn puts the wrong thing live with nobody at the
// keyboard. A draft that reaches a public reader or a cache tag is published,
// whatever the state column says. A publish that commits and never
// invalidates its cache tags serves the old page until the cache expires. A
// reviewer demoted mid-review who can still approve has kept a role they lost.
// Each has a test below that fails if the guard is removed.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

typedef _Adapter = (String name, DVDatabaseAdapter Function() create);

final List<_Adapter> _adapters = <_Adapter>[
  ('memory', MemoryDVDatabaseAdapter.new),
  ('sqlite', SqliteDVDatabaseAdapter.memory),
];

class _User {
  const _User(this.id);
  final String id;
}

/// A stored document: a route and its fields.
class _Page {
  _Page(this.route, Map<String, Object?> fields)
    : fields = Map<String, Object?>.unmodifiable(fields);
  final String route;
  final Map<String, Object?> fields;
}

const _User ada = _User('ada');
const _User grace = _User('grace');
const _User linus = _User('linus');

/// Which user holds which policy action. The registered policies read it on
/// every call, so a grant revoked mid-test is revoked for the next check.
final Map<String, Set<String>> _grants = <String, Set<String>>{};

void _allow(String user, Iterable<String> actions) =>
    (_grants[user] ??= <String>{}).addAll(actions);

void _registerPolicies() {
  const DVAuthAuthorization authorization = DVAuthAuthorization();
  for (final String action in DVContentAction.all) {
    authorization.register<_User, _Page>(
      action,
      (_User user, _Page page) => _grants[user.id]?.contains(action) ?? false,
    );
  }
}

class _Harness {
  _Harness(this.database);

  final DVDatabaseAdapter database;

  late final DVContentWorkflow<_Page> workflow = DVContentWorkflow<_Page>(
    kind: 'page',
    database: database,
    encode: (_Page page) => <String, Object?>{
      'route': page.route,
      ...page.fields,
    },
    decode: (Map<String, Object?> json) => _Page(
      json['route']! as String,
      Map<String, Object?>.of(json)..remove('route'),
    ),
    documentId: (_Page page) => page.route,
    actorId: (Object? user) => (user! as _User).id,
    findActor: (String id) async => _User(id),
    previewKey: utf8.encode('content-preview-key-for-tests-only'),
    cacheTags: (DVContentVersion<_Page> version) => <String>[
      'pages',
      'route:${version.documentId}',
    ],
    revalidateTag: (String tag) async {
      revalidated.add(tag);
    },
    notify: (String recipient, DVNotificationMessage message) async {
      notified.add((recipient, message));
    },
    onPublished: (DVContentVersion<_Page> version) async {
      published.add(version.id);
    },
    clock: () => _now,
    missedAfter: const Duration(minutes: 5),
  );

  final List<String> revalidated = <String>[];
  final List<(String, DVNotificationMessage)> notified =
      <(String, DVNotificationMessage)>[];
  final List<String> published = <String>[];

  /// A document approved by grace and ready to publish or schedule.
  Future<DVContentVersion<_Page>> approved(
    String route, {
    String title = 'Hello',
  }) async {
    final DVContentVersion<_Page> draft = await workflow.draft(
      _Page(route, <String, Object?>{'title': title}),
      as: ada,
    );
    final DVContentVersion<_Page> review = await workflow.submit(
      draft,
      to: 'grace',
      as: ada,
    );
    return workflow.approve(review, as: grace);
  }
}

DateTime _now = DateTime.utc(2026, 9, 14, 8);

Matcher _code(String code) => predicate<Object>(
  (Object error) => error is DVContentError && error.code == code,
  'a DVContentError with $code',
);

void main() {
  setUpAll(_registerPolicies);

  setUp(() {
    _now = DateTime.utc(2026, 9, 14, 8);
    _grants
      ..clear()
      ..['ada'] = <String>{DVContentAction.edit, DVContentAction.schedule}
      ..['grace'] = <String>{DVContentAction.review, DVContentAction.publish}
      ..['linus'] = <String>{DVContentAction.edit};
  });

  for (final _Adapter adapter in _adapters) {
    group('${adapter.$1}:', () {
      late _Harness h;
      late DVContentWorkflow<_Page> wf;

      setUp(() async {
        h = _Harness(adapter.$2());
        wf = h.workflow;
        await wf.ensureSchema();
      });

      group('states', () {
        test(
          'a draft is never served, prerendered or listed as public',
          () async {
            final DVContentVersion<_Page> draft = await wf.draft(
              _Page('/about', <String, Object?>{'title': 'Draft'}),
              as: ada,
            );
            expect(draft.state, DVContentState.draft);
            expect(await wf.resolve('/about'), isNull);
            expect(await wf.publicVersions(), isEmpty);
            expect(h.revalidated, isEmpty);
          },
        );

        test(
          'the full path moves draft to review to approved to published',
          () async {
            final DVContentVersion<_Page> approved = await h.approved('/about');
            expect(approved.state, DVContentState.approved);
            expect(approved.approval!.approvedBy, 'grace');
            expect(approved.approval!.revision, approved.revision);

            final DVContentVersion<_Page> live = await wf.publish(
              approved,
              as: grace,
            );
            expect(live.state, DVContentState.published);
            expect(live.publishedBy, 'grace');
            final DVContentServed<_Page>? served = await wf.resolve('/about');
            expect(served!.document.fields['title'], 'Hello');
            expect(served.isPreview, isFalse);
            expect(served.noindex, isFalse);
            expect(served.cacheable, isTrue);
            expect((await wf.publicVersions()).map((v) => v.id), <String>[
              live.id,
            ]);
          },
        );

        test('a published document is never edited in place; a new draft sits '
            'beside it while live keeps serving', () async {
          final DVContentVersion<_Page> live = await wf.publish(
            await h.approved('/about'),
            as: grace,
          );
          await expectLater(
            wf.edit(
              live,
              _Page('/about', <String, Object?>{'title': 'x'}),
              as: ada,
            ),
            throwsA(isA<DVContentInvalidTransition>()),
          );

          final DVContentVersion<_Page> next = await wf.draft(
            _Page('/about', <String, Object?>{'title': 'Next'}),
            as: ada,
          );
          expect(next.number, live.number + 1);
          expect(
            (await wf.resolve('/about'))!.document.fields['title'],
            'Hello',
          );
        });

        test('only one open draft per document', () async {
          await wf.draft(_Page('/about', const <String, Object?>{}), as: ada);
          await expectLater(
            wf.draft(_Page('/about', const <String, Object?>{}), as: linus),
            throwsA(isA<DVContentOpenDraft>()),
          );
        });

        test('a document under review is frozen against edits', () async {
          final DVContentVersion<_Page> draft = await wf.draft(
            _Page('/about', <String, Object?>{'title': 'A'}),
            as: ada,
          );
          final DVContentVersion<_Page> review = await wf.submit(
            draft,
            to: 'grace',
            as: ada,
          );
          await expectLater(
            wf.edit(
              review,
              _Page('/about', <String, Object?>{'title': 'B'}),
              as: ada,
            ),
            throwsA(isA<DVContentFrozen>()),
          );
          // Frozen against a stale snapshot too: the draft as it was read
          // before submission must not slip an edit past the review.
          await expectLater(
            wf.edit(
              draft,
              _Page('/about', <String, Object?>{'title': 'B'}),
              as: ada,
            ),
            throwsA(anyOf(isA<DVContentFrozen>(), isA<DVConflictError>())),
          );
          expect((await wf.version(review.id))!.document.fields['title'], 'A');
        });

        test('requesting changes returns the document to draft', () async {
          final DVContentVersion<_Page> review = await wf.submit(
            await wf.draft(
              _Page('/about', <String, Object?>{'title': 'A'}),
              as: ada,
            ),
            to: 'grace',
            as: ada,
          );
          final DVContentVersion<_Page> back = await wf.requestChanges(
            review,
            as: grace,
            note: 'too long',
          );
          expect(back.state, DVContentState.draft);
          final DVContentVersion<_Page> edited = await wf.edit(
            back,
            _Page('/about', <String, Object?>{'title': 'B'}),
            as: ada,
          );
          expect(edited.revision, back.revision + 1);
        });

        test('history says who moved each version and when', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          _now = _now.add(const Duration(hours: 1));
          await wf.publish(approved, as: grace);
          final List<DVContentTransition> history = await wf.history('/about');
          expect(history.map((t) => '${t.to.name}:${t.actor}'), <String>[
            'draft:ada',
            'review:ada',
            'approved:grace',
            'published:grace',
          ]);
          expect(history.every((t) => t.version == 1), isTrue);
        });

        test('diff against published names the fields that changed', () async {
          final DVContentVersion<_Page> live = await wf.publish(
            await h.approved('/about', title: 'Old'),
            as: grace,
          );
          final DVContentVersion<_Page> next = await wf.draft(
            _Page('/about', <String, Object?>{
              ...live.document.fields,
              'title': 'New',
            }),
            as: ada,
          );
          final Map<String, DVFieldChange> diff = await wf.diff(next);
          expect(diff.keys, <String>['title']);
          expect(diff['title']!.from, 'Old');
          expect(diff['title']!.to, 'New');
        });
      });

      group('revision-pinned approval', () {
        test(
          'an approval of revision N does not publish revision N+1',
          () async {
            final DVContentVersion<_Page> approved = await h.approved('/about');
            final DVContentVersion<_Page> edited = await wf.edit(
              approved,
              _Page('/about', <String, Object?>{'title': 'Sneaky'}),
              as: ada,
            );
            expect(edited.revision, approved.revision + 1);
            expect(edited.changedSinceApproval, isTrue);

            await expectLater(
              wf.publish(edited, as: grace),
              throwsA(_code('DV-CONTENT-002')),
            );
            expect(await wf.resolve('/about'), isNull);
          },
        );

        test('publishing a stale snapshot of an approved version is refused '
            'rather than publishing what the row now holds', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          await wf.edit(
            approved,
            _Page('/about', <String, Object?>{'title': 'Sneaky'}),
            as: ada,
          );
          await expectLater(
            wf.publish(approved, as: grace),
            throwsA(anyOf(_code('DV-CONTENT-002'), isA<DVConflictError>())),
          );
          expect(await wf.resolve('/about'), isNull);
        });

        test('an approval given against a stale read is refused', () async {
          final DVContentVersion<_Page> draft = await wf.draft(
            _Page('/about', <String, Object?>{'title': 'A'}),
            as: ada,
          );
          final DVContentVersion<_Page> review = await wf.submit(
            draft,
            to: 'grace',
            as: ada,
          );
          final DVContentVersion<_Page> back = await wf.requestChanges(
            review,
            as: grace,
          );
          final DVContentVersion<_Page> edited = await wf.edit(
            back,
            _Page('/about', <String, Object?>{'title': 'B'}),
            as: ada,
          );
          await wf.submit(edited, to: 'grace', as: ada);
          // grace still holds the first review's snapshot of revision 1.
          await expectLater(
            wf.approve(review, as: grace),
            throwsA(isA<DVConflictError>()),
          );
        });

        test(
          'the approval travels as a record: who, when, which revision',
          () async {
            final DVContentVersion<_Page> approved = await h.approved('/about');
            final Map<String, Object?> json = approved.approval!.toJson();
            final DVContentApproval back = DVContentApproval.fromJson(json);
            expect(back.approvedBy, 'grace');
            expect(back.approvedAt, _now);
            expect(back.revision, approved.revision);
            expect(back.digest, approved.digest);
            expect(back.matches(approved), isTrue);
          },
        );
      });

      group('policy actions', () {
        test('a publish without the publish action is refused in the backend '
            'with DV-CONTENT-003', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          await expectLater(
            wf.publish(approved, as: ada),
            throwsA(_code('DV-CONTENT-003')),
          );
          expect(
            (await wf.version(approved.id))!.state,
            DVContentState.approved,
          );
          expect(h.revalidated, isEmpty);
        });

        test(
          'a schedule without the schedule action is DV-CONTENT-003',
          () async {
            final DVContentVersion<_Page> approved = await h.approved('/about');
            await expectLater(
              wf.schedule(
                approved,
                at: _now.add(const Duration(hours: 1)),
                as: grace,
              ),
              throwsA(_code('DV-CONTENT-003')),
            );
          },
        );

        test('an unregistered action fails closed', () async {
          _grants.clear();
          await expectLater(
            wf.draft(_Page('/about', const <String, Object?>{}), as: ada),
            throwsA(isA<DVContentRefused>()),
          );
        });

        test('a reviewer cannot approve their own draft by default', () async {
          _allow('ada', <String>[DVContentAction.review]);
          final DVContentVersion<_Page> review = await wf.submit(
            await wf.draft(_Page('/about', const <String, Object?>{}), as: ada),
            to: 'ada',
            as: ada,
          );
          await expectLater(
            wf.approve(review, as: ada),
            throwsA(
              isA<DVContentRefused>().having(
                (DVContentRefused e) => e.action,
                'action',
                DVContentAction.reviewOwn,
              ),
            ),
          );
        });

        test(
          'having edited a draft someone else started is still one\'s own',
          () async {
            _allow('grace', <String>[DVContentAction.edit]);
            final DVContentVersion<_Page> draft = await wf.draft(
              _Page('/about', <String, Object?>{'title': 'A'}),
              as: ada,
            );
            final DVContentVersion<_Page> edited = await wf.edit(
              draft,
              _Page('/about', <String, Object?>{'title': 'B'}),
              as: grace,
            );
            final DVContentVersion<_Page> review = await wf.submit(
              edited,
              to: 'grace',
              as: ada,
            );
            await expectLater(
              wf.approve(review, as: grace),
              throwsA(isA<DVContentRefused>()),
            );
          },
        );

        test('the policy can allow self-approval with reviewOwn', () async {
          _allow('ada', <String>[
            DVContentAction.review,
            DVContentAction.reviewOwn,
          ]);
          final DVContentVersion<_Page> review = await wf.submit(
            await wf.draft(_Page('/about', const <String, Object?>{}), as: ada),
            to: 'ada',
            as: ada,
          );
          expect(
            (await wf.approve(review, as: ada)).state,
            DVContentState.approved,
          );
        });

        test(
          'a role changed mid-review takes effect at the next transition',
          () async {
            final DVOrganizations orgs = DVOrganizations(
              database: adapter.$2(),
              clock: () => _now,
            );
            await orgs.ensureSchema();
            final DVOrganization org = await orgs.create(
              name: 'Acme',
              tenant: 't-acme',
              ownerId: 'owner',
            );
            await orgs.addMember(
              org.id,
              'grace',
              role: DVOrgRole.admin,
              actor: 'owner',
            );

            // Grants come from the organization, read at every check.
            _grants.remove('grace');
            const DVAuthAuthorization().register<_User, _Page>(
              DVContentAction.review,
              (_User user, _Page page) =>
                  orgs.hasRole(org.id, user.id, DVOrgRole.admin),
            );
            addTearDown(_registerPolicies);

            final DVContentVersion<_Page> review = await wf.submit(
              await wf.draft(
                _Page('/about', const <String, Object?>{}),
                as: ada,
              ),
              to: 'grace',
              as: ada,
            );
            await orgs.changeRole(
              org.id,
              'grace',
              DVOrgRole.member,
              actor: 'owner',
            );
            await expectLater(
              wf.approve(review, as: grace),
              throwsA(isA<DVContentRefused>()),
            );
          },
        );
      });

      group('publish side effects', () {
        test(
          'cache tags are revalidated and publish hooks run after commit',
          () async {
            final DVContentVersion<_Page> live = await wf.publish(
              await h.approved('/about'),
              as: grace,
            );
            expect(
              h.revalidated,
              containsAll(<String>[
                'dv-content:page:/about',
                'pages',
                'route:/about',
              ]),
            );
            expect(h.published, <String>[live.id]);
          },
        );

        test('a publish rolled back with its transaction invalidates nothing '
            'and leaves nothing live', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          await expectLater(
            DVTransactionRunner()((DVContext context) async {
              await wf.publish(approved, as: grace);
              expect(
                h.revalidated,
                isEmpty,
                reason: 'invalidated before the transaction committed',
              );
              throw StateError('a later step failed');
            }),
            throwsStateError,
          );
          expect(h.revalidated, isEmpty);
          expect(h.published, isEmpty);
          expect(await wf.resolve('/about'), isNull);
          expect(
            (await wf.version(approved.id))!.state,
            DVContentState.approved,
          );
        });

        test('publishing a new version supersedes the old one, and restoring '
            'the old one keeps its approval', () async {
          final DVContentVersion<_Page> first = await wf.publish(
            await h.approved('/about', title: 'One'),
            as: grace,
          );
          final DVContentVersion<_Page> second = await wf.publish(
            await h.approved('/about', title: 'Two'),
            as: grace,
          );
          expect(
            (await wf.version(first.id))!.state,
            DVContentState.superseded,
          );
          expect((await wf.resolve('/about'))!.version.id, second.id);

          h.revalidated.clear();
          final DVContentVersion<_Page> restored = await wf.restore(
            (await wf.version(first.id))!,
            as: grace,
          );
          expect(restored.state, DVContentState.published);
          expect(restored.approval!.approvedBy, 'grace');
          expect(
            (await wf.version(second.id))!.state,
            DVContentState.superseded,
          );
          expect((await wf.resolve('/about'))!.document.fields['title'], 'One');
          expect(h.revalidated, contains('dv-content:page:/about'));
        });

        test('withdrawing a published version stops serving it and '
            'invalidates its tags', () async {
          final DVContentVersion<_Page> live = await wf.publish(
            await h.approved('/about'),
            as: grace,
          );
          h.revalidated.clear();
          await wf.withdraw(live, as: grace);
          expect(await wf.resolve('/about'), isNull);
          expect(h.revalidated, contains('dv-content:page:/about'));
        });

        test('a review request notifies the reviewer after commit', () async {
          final DVContentVersion<_Page> draft = await wf.draft(
            _Page('/about', const <String, Object?>{}),
            as: ada,
          );
          await wf.submit(draft, to: 'grace', as: ada);
          expect(h.notified.single.$1, 'grace');
          expect(h.notified.single.$2.data['version'], draft.id);
        });

        test('a notification that fails does not undo the submission, and '
            'says so', () async {
          final DVContentWorkflow<_Page> failing = DVContentWorkflow<_Page>(
            kind: 'page',
            database: wf.database,
            encode: (_Page page) => <String, Object?>{
              'route': page.route,
              ...page.fields,
            },
            decode: (Map<String, Object?> json) =>
                _Page(json['route']! as String, const <String, Object?>{}),
            documentId: (_Page page) => page.route,
            actorId: (Object? user) => (user! as _User).id,
            notify: (String to, DVNotificationMessage m) async =>
                throw StateError('no provider'),
            clock: () => _now,
          );
          final DVContentVersion<_Page> review = await failing.submit(
            await failing.draft(
              _Page('/x', const <String, Object?>{}),
              as: ada,
            ),
            to: 'grace',
            as: ada,
          );
          expect(review.state, DVContentState.review);
          expect(
            failing.reports.single.kind,
            DVContentReportKind.notificationFailed,
          );
        });
      });

      group('scheduled publish', () {
        late DVInMemoryQueueAdapter queue;

        setUp(() {
          queue = const DVTestHarness().fakeQueue();
          wf.registerJobs(const DVQueues());
        });

        Future<void> sweepAndWork() async {
          await wf.dispatchDue();
          await const DVQueues().work(maxJobs: 20);
        }

        test('publishes once at its slot, through a job', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          final DateTime at = _now.add(const Duration(hours: 1));
          final DVContentVersion<_Page> scheduled = await wf.schedule(
            approved,
            at: at,
            as: ada,
          );
          expect(scheduled.state, DVContentState.scheduled);

          await sweepAndWork();
          expect(await wf.resolve('/about'), isNull, reason: 'not yet due');

          _now = at.add(const Duration(seconds: 30));
          await sweepAndWork();
          expect((await wf.resolve('/about'))!.version.publishedBy, 'ada');
          expect(h.published, <String>[approved.id]);
          expect(await queue.deadLetters('default'), isEmpty);
        });

        test('two sweeps and a redelivered job publish exactly once', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          final DateTime at = _now.add(const Duration(minutes: 1));
          await wf.schedule(approved, at: at, as: ada);
          _now = at;
          final List<DVContentScheduledJob> dispatched = await wf.dispatchDue();
          expect(await wf.dispatchDue(), isEmpty);
          final List<DVJobEnvelope<DVJobPayload>> jobs = await queue.pending(
            'default',
          );
          expect(jobs, hasLength(1));

          // The same job delivered twice, as an at-least-once queue may.
          final DVContentScheduledJob job = dispatched.single;
          await wf.runScheduled(job);
          await wf.runScheduled(job);
          await const DVQueues().work(maxJobs: 5);
          expect(h.published, <String>[approved.id]);
          expect(
            h.revalidated.where((String t) => t == 'dv-content:page:/about'),
            hasLength(1),
          );
        });

        test('a cancelled schedule does not fire, even when its job was '
            'already dispatched', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          final DateTime at = _now.add(const Duration(minutes: 1));
          final DVContentVersion<_Page> scheduled = await wf.schedule(
            approved,
            at: at,
            as: ada,
          );
          _now = at;
          final DVContentScheduledJob job = (await wf.dispatchDue()).single;
          await wf.cancelSchedule((await wf.version(scheduled.id))!, as: ada);
          expect(await wf.runScheduled(job), DVContentScheduleOutcome.stale);
          await const DVQueues().work(maxJobs: 5);
          expect(await queue.pending('default'), isEmpty);
          expect(await queue.deadLetters('default'), isEmpty);
          expect(await wf.resolve('/about'), isNull);
          expect(
            (await wf.version(scheduled.id))!.state,
            DVContentState.approved,
          );
        });

        test('a rescheduled version fires only at its new slot', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          final DateTime first = _now.add(const Duration(minutes: 1));
          await wf.schedule(approved, at: first, as: ada);
          _now = first;
          final DVContentScheduledJob job = (await wf.dispatchDue()).single;
          final DVContentVersion<_Page> cancelled = await wf.cancelSchedule(
            (await wf.version(approved.id))!,
            as: ada,
          );
          await wf.schedule(
            cancelled,
            at: first.add(const Duration(days: 1)),
            as: ada,
          );
          expect(await wf.runScheduled(job), DVContentScheduleOutcome.stale);
          await const DVQueues().work(maxJobs: 5);
          expect(
            await wf.resolve('/about'),
            isNull,
            reason: 'the first slot\'s job ran against the second schedule',
          );
        });

        test('withdrawn content is not published by its schedule', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          final DateTime at = _now.add(const Duration(minutes: 1));
          await wf.schedule(approved, at: at, as: ada);
          _now = at;
          final DVContentScheduledJob job = (await wf.dispatchDue()).single;
          await wf.withdraw((await wf.version(approved.id))!, as: grace);
          expect(await wf.runScheduled(job), DVContentScheduleOutcome.stale);
          await const DVQueues().work(maxJobs: 5);
          expect(await queue.pending('default'), isEmpty);
          expect(await queue.deadLetters('default'), isEmpty);
          expect(await wf.resolve('/about'), isNull);
          expect(
            (await wf.version(approved.id))!.state,
            DVContentState.withdrawn,
          );
        });

        test('changed after approval: the scheduled publish refuses with '
            'DV-CONTENT-002 and publishes neither text', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          final DateTime at = _now.add(const Duration(minutes: 1));
          final DVContentVersion<_Page> scheduled = await wf.schedule(
            approved,
            at: at,
            as: ada,
          );
          await wf.edit(
            scheduled,
            _Page('/about', <String, Object?>{'title': 'Late edit'}),
            as: ada,
          );
          _now = at;
          await sweepAndWork();
          expect(await wf.resolve('/about'), isNull);
          expect(
            wf.reports.map((DVContentReport r) => r.code),
            contains('DV-CONTENT-002'),
          );
          expect(h.published, isEmpty);
        });

        test('a slot passed while no sweep ran is reported as DV-CONTENT-005 '
            'and not published late', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          final DateTime at = _now.add(const Duration(minutes: 1));
          await wf.schedule(approved, at: at, as: ada);
          _now = at.add(const Duration(hours: 4));
          await sweepAndWork();
          expect(await wf.resolve('/about'), isNull);
          expect(
            wf.reports.map((DVContentReport r) => r.code),
            contains('DV-CONTENT-005'),
          );
          expect(
            (await wf.version(approved.id))!.state,
            DVContentState.approved,
          );
        });

        test('a job dispatched on time but run after the worker was down is '
            'DV-CONTENT-005', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          final DateTime at = _now.add(const Duration(minutes: 1));
          await wf.schedule(approved, at: at, as: ada);
          _now = at;
          await wf.dispatchDue();
          _now = at.add(const Duration(hours: 4));
          await const DVQueues().work(maxJobs: 5);
          expect(await wf.resolve('/about'), isNull);
          expect(
            wf.reports.map((DVContentReport r) => r.code),
            contains('DV-CONTENT-005'),
          );
        });

        test('a dispatched job lost from a drained queue is still reported '
            'as DV-CONTENT-005', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          final DateTime at = _now.add(const Duration(minutes: 1));
          await wf.schedule(approved, at: at, as: ada);
          _now = at;
          await wf.dispatchDue();
          await const DVQueues().flush();
          _now = at.add(const Duration(hours: 1));
          await wf.dispatchDue();
          expect(
            wf.reports.map((DVContentReport r) => r.code),
            contains('DV-CONTENT-005'),
          );
          expect(
            (await wf.version(approved.id))!.state,
            DVContentState.approved,
          );
        });

        test('a scheduler who lost the schedule action before the slot is '
            'refused at the slot with DV-CONTENT-003', () async {
          final DVContentVersion<_Page> approved = await h.approved('/about');
          final DateTime at = _now.add(const Duration(minutes: 1));
          await wf.schedule(approved, at: at, as: ada);
          _grants['ada']!.remove(DVContentAction.schedule);
          _now = at;
          await sweepAndWork();
          expect(await wf.resolve('/about'), isNull);
          expect(
            wf.reports.map((DVContentReport r) => r.code),
            contains('DV-CONTENT-003'),
          );
        });

        test(
          'scheduling needs a way to find the actor again at the slot',
          () async {
            final DVContentWorkflow<_Page> blind = DVContentWorkflow<_Page>(
              kind: 'blind',
              database: wf.database,
              encode: (_Page page) => <String, Object?>{
                'route': page.route,
                ...page.fields,
              },
              decode: (Map<String, Object?> json) =>
                  _Page(json['route']! as String, const <String, Object?>{}),
              documentId: (_Page page) => page.route,
              actorId: (Object? user) => (user! as _User).id,
              clock: () => _now,
            );
            final DVContentVersion<_Page> review = await blind.submit(
              await blind.draft(
                _Page('/b', const <String, Object?>{}),
                as: ada,
              ),
              to: 'grace',
              as: ada,
            );
            final DVContentVersion<_Page> approved = await blind.approve(
              review,
              as: grace,
            );
            await expectLater(
              blind.schedule(
                approved,
                at: _now.add(const Duration(hours: 1)),
                as: ada,
              ),
              throwsStateError,
            );
          },
        );

        test('a scheduled withdrawal takes published content down once, at '
            'its slot', () async {
          final DVContentVersion<_Page> live = await wf.publish(
            await h.approved('/about'),
            as: grace,
          );
          final DateTime at = _now.add(const Duration(hours: 2));
          await wf.scheduleWithdraw(live, at: at, as: ada);
          await sweepAndWork();
          expect(await wf.resolve('/about'), isNotNull);
          _now = at;
          await sweepAndWork();
          await sweepAndWork();
          expect(await wf.resolve('/about'), isNull);
          expect((await wf.version(live.id))!.state, DVContentState.withdrawn);
        });

        test('a scheduled withdrawal of a version that was superseded does '
            'not take down its successor', () async {
          final DVContentVersion<_Page> first = await wf.publish(
            await h.approved('/about', title: 'One'),
            as: grace,
          );
          final DateTime at = _now.add(const Duration(hours: 2));
          await wf.scheduleWithdraw(first, at: at, as: ada);
          await wf.publish(await h.approved('/about', title: 'Two'), as: grace);
          _now = at;
          await sweepAndWork();
          expect((await wf.resolve('/about'))!.document.fields['title'], 'Two');
        });
      });

      group('preview', () {
        test(
          'a signed link serves the named version, noindex and uncacheable',
          () async {
            await wf.publish(
              await h.approved('/about', title: 'Live'),
              as: grace,
            );
            final DVContentVersion<_Page> draft = await wf.draft(
              _Page('/about', <String, Object?>{'title': 'Draft'}),
              as: ada,
            );
            final String token = await wf.previewToken(
              draft,
              as: ada,
              expiresIn: const Duration(minutes: 30),
            );

            final DVContentServed<_Page> served = (await wf.resolve(
              '/about',
              preview: token,
            ))!;
            expect(served.document.fields['title'], 'Draft');
            expect(served.isPreview, isTrue);
            expect(served.noindex, isTrue);
            expect(served.cacheable, isFalse);
            expect(served.cacheTags, isEmpty);
            expect(wf.reports, isEmpty);
            expect(
              (await wf.publicVersions()).single.document.fields['title'],
              'Live',
            );
          },
        );

        test('an expired link serves the published version and reports '
            'DV-CONTENT-001', () async {
          await wf.publish(
            await h.approved('/about', title: 'Live'),
            as: grace,
          );
          final DVContentVersion<_Page> draft = await wf.draft(
            _Page('/about', <String, Object?>{'title': 'Draft'}),
            as: ada,
          );
          final String token = await wf.previewToken(
            draft,
            as: ada,
            expiresIn: const Duration(minutes: 30),
          );
          _now = _now.add(const Duration(minutes: 31));
          final DVContentServed<_Page> served = (await wf.resolve(
            '/about',
            preview: token,
          ))!;
          expect(served.document.fields['title'], 'Live');
          expect(served.isPreview, isFalse);
          expect(wf.reports.single.code, 'DV-CONTENT-001');
        });

        test('an altered link, or one for another document, serves published '
            'and reports DV-CONTENT-001', () async {
          await wf.publish(
            await h.approved('/about', title: 'Live'),
            as: grace,
          );
          final DVContentVersion<_Page> draft = await wf.draft(
            _Page('/about', <String, Object?>{'title': 'Draft'}),
            as: ada,
          );
          final DVContentVersion<_Page> other = await wf.draft(
            _Page('/secret', <String, Object?>{'title': 'Secret'}),
            as: ada,
          );
          final String token = await wf.previewToken(
            draft,
            as: ada,
            expiresIn: const Duration(minutes: 30),
          );
          final String foreign = await wf.previewToken(
            other,
            as: ada,
            expiresIn: const Duration(minutes: 30),
          );

          // Extend the expiry of a link that has run out, keep the signature:
          // only the signature stands between this and the draft.
          final List<String> parts = token.split('.');
          final Map<String, Object?> payload =
              (jsonDecode(
                        utf8.decode(
                          base64Url.decode(base64Url.normalize(parts[0])),
                        ),
                      )
                      as Map)
                  .cast<String, Object?>();
          payload['e'] =
              (payload['e']! as int) + const Duration(days: 365).inMilliseconds;
          final String altered =
              '${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}.${parts[1]}';

          for (final String bad in <String>[foreign, 'garbage', '']) {
            final DVContentServed<_Page>? served = await wf.resolve(
              '/about',
              preview: bad,
            );
            expect(served!.document.fields['title'], 'Live', reason: bad);
            expect(served.isPreview, isFalse);
          }
          _now = _now.add(const Duration(minutes: 31));
          final DVContentServed<_Page>? served = await wf.resolve(
            '/about',
            preview: altered,
          );
          expect(served!.document.fields['title'], 'Live');
          expect(served.isPreview, isFalse);
          expect(
            wf.reports.map((DVContentReport r) => r.code).toSet(),
            <String>{'DV-CONTENT-001'},
          );
          expect(wf.reports, hasLength(4));
        });

        test('issuing a preview link needs edit or review', () async {
          final DVContentVersion<_Page> draft = await wf.draft(
            _Page('/about', const <String, Object?>{}),
            as: ada,
          );
          await expectLater(
            wf.previewToken(draft, as: const _User('stranger')),
            throwsA(isA<DVContentRefused>()),
          );
        });
      });

      group('machine translation', () {
        test('an untouched machine-translated string reaching published is '
            'DV-CONTENT-004, not a refusal', () async {
          final DVContentVersion<_Page> draft = await wf.draft(
            _Page('/fr', <String, Object?>{
              'hello': 'Bonjour',
              'bye': 'Au revoir',
            }),
            as: ada,
            machineTranslated: <String>{'hello', 'bye'},
          );
          final DVContentVersion<_Page> edited = await wf.edit(
            draft,
            _Page('/fr', <String, Object?>{
              'hello': 'Salut',
              'bye': 'Au revoir',
            }),
            as: ada,
          );
          expect(edited.machineTranslated, <String>{'bye'});
          final DVContentVersion<_Page> review = await wf.submit(
            edited,
            to: 'grace',
            as: ada,
          );
          final DVContentVersion<_Page> live = await wf.publish(
            await wf.approve(review, as: grace),
            as: grace,
          );
          expect(live.state, DVContentState.published);
          final DVContentReport report = wf.reports.single;
          expect(report.code, 'DV-CONTENT-004');
          expect(report.keys, <String>{'bye'});
        });

        test('a string a human confirmed unchanged is not reported', () async {
          final DVContentVersion<_Page> draft = await wf.draft(
            _Page('/fr', <String, Object?>{'hello': 'Bonjour'}),
            as: ada,
            machineTranslated: <String>{'hello'},
          );
          final DVContentVersion<_Page> confirmed = await wf
              .confirmTranslations(draft, <String>{'hello'}, as: ada);
          expect(confirmed.machineTranslated, isEmpty);
          final DVContentVersion<_Page> review = await wf.submit(
            confirmed,
            to: 'grace',
            as: ada,
          );
          await wf.publish(await wf.approve(review, as: grace), as: grace);
          expect(wf.reports, isEmpty);
        });
      });
    });
  }

  test('a scheduled publish survives a restart: the job is persisted on a '
      'database queue and run by a new process', () async {
    final DVDatabaseAdapter database = SqliteDVDatabaseAdapter.memory();
    const DVTestHarness().fakeQueue();
    final _Harness before = _Harness(database);
    await before.workflow.ensureSchema();
    const DVQueues().useAdapter(DVDatabaseQueueAdapter(database));
    before.workflow.registerJobs(const DVQueues());
    final DVContentVersion<_Page> approved = await before.approved('/launch');
    final DateTime at = _now.add(const Duration(minutes: 1));
    await before.workflow.schedule(approved, at: at, as: ada);
    _now = at;
    expect(await before.workflow.dispatchDue(), hasLength(1));

    // A new process: a new workflow and a new queue adapter over the same
    // database, with nothing held in memory from the first.
    const DVTestHarness().fakeQueue();
    final _Harness after = _Harness(database);
    const DVQueues().useAdapter(DVDatabaseQueueAdapter(database));
    after.workflow.registerJobs(const DVQueues());
    expect(await const DVQueues().work(maxJobs: 5), 1);
    expect((await after.workflow.resolve('/launch'))!.version.id, approved.id);
    expect(after.published, <String>[approved.id]);
    const DVTestHarness().fakeQueue();
  });

  test('the codes this emits are registered at the specified levels', () {
    final Map<String, String> levels = <String, String>{
      for (final DVDiagnostic d in DVDiagnostics.all) d.code: d.level,
    };
    expect(levels['DV-CONTENT-001'], 'warning');
    expect(levels['DV-CONTENT-002'], 'warning');
    expect(levels['DV-CONTENT-003'], 'error');
    expect(levels['DV-CONTENT-004'], 'warning');
    expect(levels['DV-CONTENT-005'], 'warning');
  });
}
