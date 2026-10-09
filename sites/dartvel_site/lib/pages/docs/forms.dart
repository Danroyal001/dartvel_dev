import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel forms: a form for every model, generated',
  description:
      'Every Dartvel model gets a form with an input per field, so a '
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
    'A form is driven from the keyboard with nothing added: Tab walks it in '
        'the order it is drawn, Enter submits from the last field, and a '
        'refused save says what is wrong and puts the focus on the field at '
        'fault.',
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
          'The form awaits the save, shows progress and prevents another '
              'submission or reset while it runs. A failed save keeps '
              'your edits and announces a safe error message.',
          'Each field the model serializes becomes a text input, '
              'labelled with the field\'s name, followed by Save and '
              'Reset.',
          'Text typed into a number or date field that the model cannot '
              'hold is refused on save, naming the field, saying so in a '
              'live region for a screen reader, and moving the focus to it.',
          'Tab reaches every field and every control in the order the form '
              'is drawn. Enter in a field moves to the next one; Enter in '
              'the last field submits. In a multiline field Enter is a '
              'newline instead.',
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
          'The fields a builder draws register with the same scope the '
              'generated ones do, so Tab order, Enter-to-submit, the focus '
              'ring and the refusal message are already there. Wrap fields '
              'in DVFormScope yourself only when the inputs live outside '
              'the form.',
        ]),
      ],
    ),
    DocsSection(
      id: 'keyboard',
      title: 'Drive the form from the keyboard',
      children: <Widget>[
        DocsText(
          'Generated forms support keyboard and screen reader input '
          'automatically. Tab reaches fields and controls, Enter submits, '
          'and rejected values are announced and focused.',
        ),
        DocsCode('forms-keyboard'),
        Bullets(<String>[
          'Tab and Shift+Tab walk the fields and the controls in the order '
              'the form is drawn.',
          'Enter moves to the next field, and submits from the last one. In '
              'a field declared .input(multiline: true) it is a newline, '
              'because a paragraph of text does not want to save itself.',
          'Enter or Space on a control presses it. Anything drawn with '
              '.onTap() or .onPressed() is a real focusable control with a '
              'visible focus ring and a name, whether it is a DVBox or a '
              'DVText.',
          'A save the model refuses is shown on the form, announced in a '
              'live region, written under the field it names, and given '
              'the focus. A person who pressed Enter and was refused is '
              'looking at a form that otherwise looks unchanged.',
          'DVFormScope is the public piece of this, for inputs a form does '
              'not draw itself: it holds the field order and the submit, '
              'and an application that lays out its own inputs inside one '
              'gets the same behaviour.',
        ]),
        DocsNote(
          'The eye is on a password field by default',
          'A field drawn with .input(obscureText: true) starts with a '
              'Show password control, which can be turned off with '
              '.none or replaced with .custom(builder). See the sensitive '
              'fields below.',
        ),
      ],
    ),
    DocsSection(
      id: 'sensitive',
      title: 'Sensitive fields are write-only',
      children: <Widget>[
        DocsText(
          'A field marked @DVModel.sensitiveField() works like a '
          'password field. Model.Form() and the Studio record form show '
          'an input for it that hides what is typed and always starts '
          'empty: the stored value is never put in it.',
        ),
        Bullets(<String>[
          'Type a value and save, and the value is stored.',
          'Leave it empty and save, and the stored value stays as it '
              'was. An edit form says so under the input.',
          'No read gives the value back: not toPublicJson, GraphQL, '
              'Studio, tables, cards or model pages. GraphQL takes it as '
              'an optional argument of the save mutation.',
          'The builder\'s controls have no getter for it. '
              '@DVModel.sensitiveField(showInForms: true) makes it an '
              'ordinary, readable field on forms and controls instead.',
          'The input for a sensitive field carries a Show password '
              'control, so what was typed can be checked. Someone typing on '
              'a keyboard is the person most likely to mistype and least '
              'able to reach for a mouse.',
        ]),
        DocsCode('forms-password-toggle'),
        Bullets(<String>[
          'visibilityToggle: .none draws no control at all.',
          'visibilityToggle: .custom(builder) draws yours. The builder is '
              'given whether the field is obscured and the way to change '
              'that, so it cannot get the state wrong.',
          'The control is named for what it does right now, so a reader is '
              'not told to hide a password that is already showing.',
        ]),
      ],
    ),
    DocsSection(
      id: 'conflicts',
      title: 'Save at the version you opened',
      children: <Widget>[
        DocsText(
          'The edited model keeps the version of the record the form '
          'opened. If someone saved a newer version in between, save() '
          'throws DVConflictError. See Models for the conflict options.',
        ),
        DocsStatus(
          'Record History and Optimistic Concurrency',
          missing: <String>[
            'A form does not reload and merge the newer version for you.',
          ],
        ),
      ],
    ),
    DocsSection(
      id: 'status',
      title: 'Status',
      children: <Widget>[DocsStatus('Forms')],
    ),
  ],
);
