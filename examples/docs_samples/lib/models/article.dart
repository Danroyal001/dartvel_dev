// docs:start models-article
// lib/models/article.dart
import 'package:dartvel_core/dartvel.dart';

@DVModel(
  generatePublicPages: true,
  semantic: true,
  history: DVHistory(keep: Duration(days: 365)),
  softDelete: true,
  subject: DVSubject.field('authorId'),
  retain: DVRetention.indefinite,
)
class _Article {
  final String slug;

  @DVModel.pageTitle()
  final String title;

  @DVModel.mainContent()
  final String body;

  @DVModel.searchableField()
  final String tags;

  final bool published;

  final String authorId;

  @DVModel.sensitiveField()
  final String editorNotes;

  const _Article({
    required this.slug,
    required this.title,
    required this.body,
    required this.tags,
    required this.published,
    required this.authorId,
    required this.editorNotes,
  });
}
// docs:end
