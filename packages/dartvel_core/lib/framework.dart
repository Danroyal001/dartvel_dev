/// What the framework and its generated code are written against.
///
/// An application does not import this. A model's capabilities are members
/// of the model -- `Article.search`, `Article.semanticSearch`,
/// `Article.syncPolicy`, `Article.changes` -- and the machinery underneath
/// them is the framework's own. It lives here so the generator can write
/// against it and the framework's tests can reset it, and out of
/// `package:dartvel_core/dartvel.dart`, which is what an application sees.
///
/// Naming one of these in application code means the surface is missing
/// something, so the fix is to add the member to the model rather than to
/// import this.
library;

export 'src/search/semantic_search.dart' show DVSemanticIndex;
export 'src/sync/model_sync.dart' show DVModelSync, DVModelSyncTransport;
export 'src/sync/presence.dart' show DVPresenceTransport;
