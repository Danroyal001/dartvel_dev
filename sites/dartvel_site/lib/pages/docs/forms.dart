import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel forms: a form for every model, generated', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsFormsPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsforms,
      lead: <String>[
        'Every @DVModel gets a form with an input per field, so a create or '
            'edit screen is one line.',
        'Lay it out yourself with DVForm.builder and keep the typed fields and '
            'the submit action.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'automatic',
          title: 'Generate a form from a model',
          children: <Widget>[
            DocsCode('forms-automatic'),
            Bullets(<String>[
              'DVForm<Article>() starts from the model\'s generated default.',
              'Each field the model serializes becomes a text input.',
              'Article.Form(article, onSubmit) builds the same DVForm<Article>.',
            ]),
            DocsNote('No onSubmit means no buttons',
                'A form without a second argument has nobody to hand the edited '
                'record to. It shows the fields and no Save or Reset.'),
          ],
        ),
        DocsSection(
          id: 'builder',
          title: 'Lay out the form yourself',
          children: <Widget>[
            DocsCode('forms-builder'),
            Bullets(<String>[
              'The builder gets ArticleFormControls, typed as DVFormControls.',
              'There is a getter per field, and titleIsValid for each String '
                  'field, which checks the value is not blank.',
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
