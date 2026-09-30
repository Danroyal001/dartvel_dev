import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start forms-automatic
// On the model, a form that creates one.
Widget newArticleForm() => Article.Form();

// On an article, a form that edits that article.
Widget editArticleForm(Article article) => article.Form();

// Neither takes a callback. Saving is what the form does: save() checks the
// model's @DVModel.validate rules and the version of the record the form
// opened before anything is written.
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
