// docs:start models-page-policy
// lib/policies/article_policy.dart
import '../dartvel_client/dartvel_client.dart';

@DVPolicy(Article)
class ArticlePolicy {
  // Who may open an article's page. Anyone else gets a 404.
  bool view(DVSessionPrincipal? user, Article article) =>
      article.published || user?.userId == article.authorId;

  // Who also sees editorNotes and authorId on the page.
  bool viewSensitive(DVSessionPrincipal? user, Article article) =>
      user?.userId == article.authorId;
}
// docs:end
