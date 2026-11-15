import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Class widgets in Dartvel: DVClassWidget',
  description:
      'Write pages and reusable widgets as classes with DVClassWidget, '
      'keep state in signals, and mix classes with functional widgets.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsClassWidgetsPage(BuildContext context) => const DocsArticle(
  page: DVRoutes.docsclasswidgets,
  lead: <String>[
    'Prefer classes to functions? Extend DVClassWidget for pages and '
        'reusable widgets alike.',
    'A class and a functional widget build, route and render the same way.',
  ],
  sections: <DocsSection>[
    DocsSection(
      id: 'page',
      title: 'Write a page as a class',
      children: <Widget>[
        DocsText(
          'Put @DVPage on a class that extends DVClassWidget, in a file '
          'under lib/pages. The file path is the route, as for a function '
          'page, and the generated DVRoutes member points at it.',
        ),
        DocsCode('class-widgets-page'),
        Bullets(<String>[
          'Give the class a const primary constructor that takes super.key.',
          'The page is server-rendered on the web, selectable and readable '
              'by screen readers, like every other page.',
          'A loading or error companion (about.loading.dart, '
              'about.error.dart) can be a class too.',
        ]),
      ],
    ),
    DocsSection(
      id: 'component',
      title: 'Write a reusable widget as a class',
      children: <Widget>[
        DocsText(
          'A widget used inside pages is also a DVClassWidget. It has no '
          '@DVPage, so it gets no route. Its constructor parameters are '
          'its inputs.',
        ),
        DocsCode('class-widgets-component'),
        DocsNote(
          'Not StatelessWidget or StatefulWidget',
          'dartvel build reports a Flutter widget class in your app as '
              'DV-CONV-012. Extend DVClassWidget, or annotate a function '
              'with @DVFunctionalWidget.',
        ),
      ],
    ),
    DocsSection(
      id: 'state',
      title: 'Keep state in signals',
      children: <Widget>[
        DocsText(
          'A class widget has no State class and no setState. Create a '
          'signal with context.signal in build, and read its value there: '
          'the widget redraws when the value changes.',
        ),
        DocsCode('class-widgets-state'),
        DocsText(
          'Derived signals, globals and reactive data models work the same '
          'in a class as in a function. The State page explains them.',
        ),
      ],
    ),
    DocsSection(
      id: 'choose',
      title: 'Choose a class or a function',
      children: <Widget>[
        Bullets(<String>[
          'Both shapes are first-class. Every sample in these docs has a '
              'Function tab and a Class tab.',
          'One app can mix them: a class page can show functional widgets, '
              'and the other way round.',
          'pageScrollToTop: true on a DVClassWidget adds the "Back to top" '
              'button, the same as on @DVFunctionalWidget.',
        ]),
      ],
    ),
  ],
);
