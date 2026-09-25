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

/// The content workflow for Studio page documents, wired to the page store
/// and to `DV.Cache`.
class DVStudioContent {
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
         revalidateTag: (String tag) => DV.Cache.delete(tag: tag),
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

  /// The id the workflow records for [user].
  String actorIdOf(Object? user) => _actorId(user);

  /// The workflow's clock, so a schedule picked in Studio is judged against
  /// the same "now" the workflow refuses a past slot by.
  DateTime now() => _clock();

  /// Whether [user] holds [action] on [document], asked of the same policies
  /// the workflow checks.
  ///
  /// For showing an action as unavailable before it is tried. It is never the
  /// check: the workflow asks again at the transition, so a role removed after
  /// Studio asked is still refused.
  Future<bool> can(Object? user, String action, DVPageDocument document) =>
      _authorization.can<Object?, DVPageDocument>(user, action, document);

  /// Every route with at least one page version, sorted.
  ///
  /// The page store holds only what is published, so a page that has only
  /// ever been a draft is not in it -- and is still a page somebody is
  /// writing.
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
  void attach(DVStudioEditorController controller, {required Object? as}) {
    controller.publisher = (DVPageDocument document) =>
        saveDraft(document, as: as);
  }

  /// Saves [document] into its open version, or opens a draft beside the
  /// published one when there is none.
  ///
  /// A document under review is refused (`DVContentFrozen`) rather than
  /// saved somewhere else: an edit that silently went nowhere looks saved.
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
