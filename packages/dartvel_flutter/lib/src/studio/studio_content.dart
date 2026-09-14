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
  }) : workflow = DVContentWorkflow<DVPageDocument>(
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
         revalidateTag: (String tag) => DV.Cache.revalidateTag(tag),
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
