import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel forms: a form for every model, generated',
  description: 'Every Dartvel model gets a form with an input per field, so a '
      'create or edit screen is one line. Saving checks the model\'s '
      'rules and the version the form opened.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsFormsPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsforms,
      lead: <String>[
        'Every @DVModel gets a form with an input per field, so a create or '
            'edit screen is one line.',
        'Saving runs the model\'s own save(): the rules from '
            '@DVModel.validate are checked first, and an edit is saved at the '
            'version the form opened.',
        'Lay it out yourself with DVForm.builder and keep the typed field '
            'values and the submit action.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'automatic',
          title: 'Generate a form from a model',
          children: <Widget>[
            DocsCode('forms-automatic'),
            Bullets(<String>[
              'Article.Form() creates a record. article.Form() edits that '
                  'record.',
              'Neither takes a callback. Saving is what the form does.',
              'Each field the model serializes becomes a text input, '
                  'labelled with the field\'s name, followed by Save and '
                  'Reset.',
              'Text typed into a number or date field that the model cannot '
                  'hold is refused on save, naming the field.',
              'Save calls the model\'s save(), which checks the '
                  '@DVModel.validate rules (shortest and longest text, '
                  'smallest and largest number, a pattern) and refuses a '
                  'value that breaks one with DVModelRuleError. The same '
                  'rules are checked by Studio and the data API.',
              'The generated admin, GraphQL and an offline replay ask the '
                  'model\'s create and update policies before they write. The '
                  'save() a form calls on its own does not ask one yet.',
            ]),
          ],
        ),
        DocsSection(
          id: 'builder',
          title: 'Lay out the form yourself',
          children: <Widget>[
            DocsCode('forms-builder'),
            Bullets(<String>[
              'The builder gets ArticleFormControls, typed as DVFormControls.',
              'There is a typed getter per field, and titleIsValid for each '
                  'String field, which checks the value is not blank. For a '
                  'field whose name contains email it also checks for an @.',
              'The controls read values and have no setters, so a builder '
                  'form submits the model it was given. The onSubmit you pass '
                  'decides what changes, as copyWith does in the sample.',
              'controls.submit() and controls.reset() run the form\'s own '
                  'actions.',
            ]),
          ],
        ),
        DocsSection(
          id: 'sensitive',
          title: 'Keep sensitive fields off the controls',
          children: <Widget>[
            DocsText('A field marked @DVModel.sensitiveField() gets no getter '
                'on the builder\'s controls. Put one back with '
                '@DVModel.sensitiveField(showInForms: true).'),
          ],
        ),
        DocsSection(
          id: 'conflicts',
          title: 'Save at the version you opened',
          children: <Widget>[
            DocsText('The edited model keeps the version of the record the form '
                'opened. If someone saved a newer version in between, save() '
                'throws DVConflictError. See Models for the conflict options.'),
            DocsStatus('Record History and Optimistic Concurrency',
                missing: <String>[
                  'A form does not reload and merge the newer version for you.',
                ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Forms'),
          ],
        ),
      ],
    );
