import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start forms-automatic
// A blank form, started from the model's generated default.
Widget newArticleForm() => DVForm<Article>();

// An edit form. Submitting hands you the edited model.
Widget editArticleForm(Article article) =>
    DVForm<Article>(article, (Article edited) => edited.save());

// The same form through the generated alias.
Widget editArticleFormAlias(Article article) =>
    Article.Form(article, (Article edited) => edited.save());
// docs:end

// docs:start forms-builder
Widget articleSummaryForm(Article article) => DVForm<Article>.builder(
      (DVFormControls controls) {
        final ArticleFormControls fields = controls as ArticleFormControls;
        return DVBox.list(<Widget>[
          DVText('Title: ${fields.title}'),
          if (!fields.titleIsValid) const DVText('Add a title first'),
          DVText('Publish').modifier(
            const DVModifier().semanticButton().onTap(controls.submit),
          ),
        ]);
      },
      article,
      null, // key
      (Article edited) => edited.copyWith(published: true).save(),
    );
// docs:end
