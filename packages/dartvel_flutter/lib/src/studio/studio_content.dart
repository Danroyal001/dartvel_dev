/// Studio's page documents through the content workflow.
///
/// Studio publishes on save: the controller's save writes the page store, and
/// the router serves what the store holds. That is right for one person
/// editing their own site. With this attached, the same Publish button opens
/// or edits a draft instead, and the page store -- the only thing the router
/// serves -- is written when a version is published and cleared when a
/// published version is withdrawn. Nothing else about the editor changes: it
/// edits the same documents through the same operations.
library dartvel_flutter.studio.content;

import '../../dartvel_flutter.dart';

export 'studio_content_diff.dart';

/// A page's versions as Studio's editor works with them: drafts beside the
/// published page, review, schedules, and the revisions a publish leaves
/// behind to restore.
///
/// Two of them: [DVStudioContent], the workflow run where Studio runs, over a
/// database it holds; and `DVStudioRemoteVersions`, the same workflow on the
/// server a web-server binary runs, reached over Studio's API. The editor and
/// its review panel are written against this, so they are the same screens
/// either way.
abstract interface class DVStudioVersions {
  /// The id the workflow records for [user].
  String actorIdOf(Object? user);

  /// The workflow's clock, which a schedule picked in Studio is judged by.
  DateTime now();

  /// Whether [user] holds [action] on [document]. For showing an action as
  /// unavailable before it is tried; never the check.
  Future<bool> can(Object? user, String action, DVPageDocument document);

  /// Every route with at least one version, sorted.
  Future<List<String>> routes();

  /// Every version of [route], oldest first.
  Future<List<DVContentVersion<DVPageDocument>>> versions(String route);

  /// Every state change of every version of [route].
  Future<List<DVContentTransition>> history(String route);

  /// Saves [document] into its open version, or opens a draft.
  Future<DVContentVersion<DVPageDocument>> saveDraft(
    DVPageDocument document, {
    required Object? as,
  });

  Future<DVContentVersion<DVPageDocument>> submit(
    DVContentVersion<DVPageDocument> version, {
    required String to,
    required Object? as,
  });

  Future<DVContentVersion<DVPageDocument>> approve(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
  });

  Future<DVContentVersion<DVPageDocument>> requestChanges(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
    String? note,
  });

  Future<DVContentVersion<DVPageDocument>> schedule(
    DVContentVersion<DVPageDocument> version, {
    required DateTime at,
    required Object? as,
  });

  Future<DVContentVersion<DVPageDocument>> cancelSchedule(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
  });

  Future<DVContentVersion<DVPageDocument>> publish(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
  });

  /// Publishes a superseded [version] again.
  Future<DVContentVersion<DVPageDocument>> restore(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
  });

  /// Withdraws [version]: a published one stops being served, an open one is
  /// abandoned.
  Future<DVContentVersion<DVPageDocument>> withdraw(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
  });

  /// A signed, expiring link to [version] on the application's own routes.
  Future<Uri> previewLink(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
    Duration expiresIn,
  });

  /// Makes [controller] keep its work as drafts of these versions.
  void attach(DVStudioEditorController controller, {required Object? as});
}

/// The content workflow for Studio page documents, wired to the page store
/// and to `DV.Cache`.
class DVStudioContent implements DVStudioVersions {
  DVStudioContent({
    required String Function(Object? user) actorId,
    Future<Object?> Function(String actorId)? findActor,
    List<int>? previewKey,
    DVDatabaseAdapter? database,
    DVAuthAuthorization authorization = const DVAuthAuthorization(),
    Future<void> Function(String recipient, DVNotificationMessage message)?
    notify,
    bool requireApproval = true,
    Duration missedAfter = const Duration(minutes: 5),
    DateTime Function()? clock,
    DVPageStore store = const DVPageStore(),
    Uri Function(String route, String token)? previewUrl,
  })  : _authorization = authorization,
        _actorId = actorId,
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _previewUrl = previewUrl ??
            ((String route, String token) => Uri(
                  path: route,
                  queryParameters: <String, String>{'preview': token},
                )),
        workflow = DVContentWorkflow<DVPageDocument>(
         kind: kind,
         encode: (DVPageDocument document) => document.toJson(),
         decode: DVPageDocument.fromJson,
         documentId: (DVPageDocument document) => document.route,
         actorId: actorId,
         findActor: findActor,
         previewKey: previewKey,
         database: database,
         authorization: authorization,
         notify: notify,
         requireApproval: requireApproval,
         missedAfter: missedAfter,
         clock: clock,
         revalidateTag: (String tag) => DV.Cache.delete(DVCacheTag(tag)),
         // After commit: the router serves the store, so a version reaches
         // readers only once its publish has committed.
         onPublished: (DVContentVersion<DVPageDocument> version) =>
             store.save(version.document),
         onWithdrawn: (DVContentVersion<DVPageDocument> version) =>
             store.delete(version.documentId),
       );

  /// The document kind page versions are stored under.
  static const String kind = 'page';

  /// Policies register against `DVPageDocument` for the [DVContentAction]s.
  final DVContentWorkflow<DVPageDocument> workflow;

  final DVAuthAuthorization _authorization;
  final String Function(Object? user) _actorId;
  final DateTime Function() _clock;
  final Uri Function(String route, String token) _previewUrl;

  @override
  String actorIdOf(Object? user) => _actorId(user);

  /// The workflow's clock, so a schedule picked in Studio is judged against
  /// the same "now" the workflow refuses a past slot by.
  @override
  DateTime now() => _clock();

  /// Whether [user] holds [action] on [document], asked of the same policies
  /// the workflow checks.
  ///
  /// For showing an action as unavailable before it is tried. It is never the
  /// check: the workflow asks again at the transition, so a role removed after
  /// Studio asked is still refused.
  @override
  Future<bool> can(Object? user, String action, DVPageDocument document) =>
      _authorization.can<Object?, DVPageDocument>(user, action, document);

  /// Every route with at least one page version, sorted.
  ///
  /// The page store holds only what is published, so a page that has only
  /// ever been a draft is not in it -- and is still a page somebody is
  /// writing.
  @override
  Future<List<String>> routes() async {
    await workflow.ensureSchema();
    final List<Map<String, Object?>> rows = await workflow.database.query(
      'SELECT DISTINCT document_id FROM ${DVContentWorkflow.table} '
      'WHERE kind = ?',
      <Object?>[kind],
    );
    return <String>{
      for (final Map<String, Object?> row in rows) '${row['document_id']}',
    }.toList()
      ..sort();
  }

  /// A signed, expiring link to [version] on the application's own routes.
  ///
  /// `previewUrl` shapes it; the default is the route with the token as its
  /// `preview` query parameter, which [DVContentWorkflow.resolve] takes.
  @override
  Future<Uri> previewLink(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
    Duration expiresIn = const Duration(hours: 1),
  }) async {
    final String token = await workflow.previewToken(
      version,
      as: as,
      expiresIn: expiresIn,
    );
    return _previewUrl(version.documentId, token);
  }

  /// Makes [controller]'s save open or edit a draft as [as], rather than
  /// publishing.
  @override
  void attach(DVStudioEditorController controller, {required Object? as}) {
    controller
      ..publisher = ((DVPageDocument document) => saveDraft(document, as: as))
      ..draftSaver = ((DVPageDocument document) => saveDraft(document, as: as));
  }

  /// Saves [document] into its open version, or opens a draft beside the
  /// published one when there is none.
  ///
  /// A document under review is refused (`DVContentFrozen`) rather than
  /// saved somewhere else: an edit that silently went nowhere looks saved.
  @override
  Future<DVContentVersion<DVPageDocument>> saveDraft(
    DVPageDocument document, {
    required Object? as,
  }) async {
    for (final DVContentVersion<DVPageDocument> version
        in await workflow.versions(document.route)) {
      switch (version.state) {
        case DVContentState.draft:
        case DVContentState.review:
        case DVContentState.approved:
        case DVContentState.scheduled:
          return workflow.edit(version, document, as: as);
        case DVContentState.published:
        case DVContentState.superseded:
        case DVContentState.withdrawn:
          continue;
      }
    }
    return workflow.draft(document, as: as);
  }

  @override
  Future<List<DVContentVersion<DVPageDocument>>> versions(String route) =>
      workflow.versions(route);

  @override
  Future<List<DVContentTransition>> history(String route) =>
      workflow.history(route);

  @override
  Future<DVContentVersion<DVPageDocument>> submit(
    DVContentVersion<DVPageDocument> version, {
    required String to,
    required Object? as,
  }) => workflow.submit(version, to: to, as: as);

  @override
  Future<DVContentVersion<DVPageDocument>> approve(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
  }) => workflow.approve(version, as: as);

  @override
  Future<DVContentVersion<DVPageDocument>> requestChanges(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
    String? note,
  }) => workflow.requestChanges(version, as: as, note: note);

  @override
  Future<DVContentVersion<DVPageDocument>> schedule(
    DVContentVersion<DVPageDocument> version, {
    required DateTime at,
    required Object? as,
  }) => workflow.schedule(version, at: at, as: as);

  @override
  Future<DVContentVersion<DVPageDocument>> cancelSchedule(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
  }) => workflow.cancelSchedule(version, as: as);

  @override
  Future<DVContentVersion<DVPageDocument>> publish(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
  }) => workflow.publish(version, as: as);

  @override
  Future<DVContentVersion<DVPageDocument>> restore(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
  }) => workflow.restore(version, as: as);

  @override
  Future<DVContentVersion<DVPageDocument>> withdraw(
    DVContentVersion<DVPageDocument> version, {
    required Object? as,
  }) => workflow.withdraw(version, as: as);

  /// A bundle of every published page, with the approval each was published
  /// under.
  Future<DVPageBundle> bundle({required String version}) async {
    final List<DVContentVersion<DVPageDocument>> published = await workflow
        .publicVersions();
    return DVPageBundle(
      version: version,
      pages: <DVPageDocument>[
        for (final DVContentVersion<DVPageDocument> page in published)
          page.document,
      ],
      approvals: <String, DVContentApproval>{
        for (final DVContentVersion<DVPageDocument> page in published)
          if (page.approval != null) page.documentId: page.approval!,
      },
    );
  }
}
