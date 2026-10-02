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

// docs:start forms-keyboard
// Nothing to add. Every form Dartvel draws is already driven from the
// keyboard: Tab walks the fields in the order they are drawn, Enter in a field
// moves to the next one and submits from the last, Enter or Space on a control
// presses it, and the focus ring is drawn while it is there.
Widget newArticleFormFromTheKeyboard() => Article.Form();

// A form laid out by hand gets the same thing, because DVForm wraps whatever
// it builds in the scope the generated fields register with.
Widget articleForm(Article article) => DVForm<Article>.builder(
      (DVFormControls controls) {
        final ArticleFormControls fields = controls as ArticleFormControls;
        return DVBox.list(<Widget>[
          // A refusal naming TITLE is shown under this field, announced with
          // it, and given the focus, so Enter in a form the model refused
          // lands where the fix is.
          DVText(fields.title).modifier(const DVModifier().input(label: 'TITLE')),
          DVText(fields.body).modifier(
            const DVModifier().input(label: 'BODY', multiline: true),
          ),
          const DVText('Publish').modifier(
            DVModifier().semanticButton().onTap(controls.submit),
          ),
        ]);
      },
      article,
      null, // key
      (Article edited) => edited.copyWith(published: true).save(),
    );

// A save the model refuses says so on the form, names the field at fault and
// puts the focus on it. Nothing has to be written to get that.
// docs:end

// docs:start forms-password-toggle
// A field that hides what is typed into it gets the eye by default, so nobody
// has to ask for it and nobody has to check a mistyped password by deleting
// the whole thing.
Widget passwordField() => DVText('')
    .modifier(const DVModifier().input(label: 'PASSWORD', obscureText: true));

// Turn it off where the eye is in the way: a field asking for a key somebody
// can see on the machine in front of them, say.
Widget unlockKeyField() => DVText('').modifier(
      const DVModifier().input(
        label: 'UNLOCK KEY',
        obscureText: true,
        visibilityToggle: .none,
      ),
    );

// Or draw your own. The builder is told whether the field is obscured and
// given the way to change that, so a custom control cannot get the state wrong,
// and it is an ordinary focusable control like any other: Tab reaches it and
// Enter or Space presses it.
Widget ownToggleField() => DVText('').modifier(
      DVModifier().input(
        label: 'PASSWORD',
        obscureText: true,
        visibilityToggle: .custom(
          (BuildContext context, bool obscured, VoidCallback toggle) =>
              DVText(obscured ? 'Show' : 'Hide').modifier(
                DVModifier().semanticButton().onPressed(toggle),
              ),
        ),
      ),
    );
// docs:end
