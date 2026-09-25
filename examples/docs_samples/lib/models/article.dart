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
class const _Article({
  required final String slug,
  @DVModel.pageTitle() required final String title,
  @DVModel.mainContent() required final String body,
  @DVModel.searchableField() required final String tags,
  required final bool published,
  required final String authorId,
  @DVModel.sensitiveField() required final String editorNotes,
});
// docs:end
