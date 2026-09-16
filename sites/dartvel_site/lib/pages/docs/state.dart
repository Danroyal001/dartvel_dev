import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel state: signals, derived signals and globals', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsStatePage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsstate,
      lead: <String>[
        'Keep a value in a signal and the widget that reads it redraws when it '
            'changes.',
        'Combine signals with + * > & and the result is a signal too.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'signals',
          title: 'Create a signal with context.signal',
          children: <Widget>[
            DocsCode('state-signals'),
            Bullets(<String>[
              'context.signal(initial) creates a DVSignal for this widget.',
              'Reading .value in build subscribes the widget to it.',
              'Signals match by call order in build, like hooks. Create them '
                  'unconditionally.',
            ]),
            DocsText('signal(context, value) is the same call as a top-level '
                'function.'),
          ],
        ),
        DocsSection(
          id: 'update',
          title: 'Set, update and read a signal',
          children: <Widget>[
            DocsCode('state-update'),
          ],
        ),
        DocsSection(
          id: 'derived',
          title: 'Derive signals with operators',
          children: <Widget>[
            DocsText('An operator on a signal returns a signal that tracks its '
                'sources. There is no separate computed type to learn.'),
            DocsCode('state-operators'),
            DocsTable(columns: <String>[
              'Signal type',
              'Operators',
            ], rows: <List<String>>[
              <String>['num', '+ - * / ~/ % and < <= > >='],
              <String>['String', '+'],
              <String>['bool', '& | ^'],
            ]),
            DocsNote('Read .value to redraw',
                'A derived signal redraws a widget through its sources, so read '
                '.value in build. == and ! are not overloaded: compare .value '
                'instead.'),
          ],
        ),
        DocsSection(
          id: 'models',
          title: 'Make a model reactive',
          children: <Widget>[
            DocsText('Every generated model has model.signal(context). Pass it '
                'to the generated page to redraw on each change.'),
            DocsCode('models-reactive'),
          ],
        ),
        DocsSection(
          id: 'global',
          title: 'Share one object with DV.global',
          children: <Widget>[
            DocsCode('state-global'),
            Bullets(<String>[
              'DV.global<T>(instance) registers. DV.global<T>() reads, and '
                  'throws when nothing is registered.',
              'context.global<T>() reads and redraws the widget when the '
                  'object is replaced.',
              'Use it for app-wide objects. There is no separate service '
                  'container.',
            ]),
          ],
        ),
        DocsSection(
          id: 'lifecycle',
          title: 'Observe the app lifecycle',
          children: <Widget>[
            DocsCode('state-lifecycle'),
            Bullets(<String>[
              'DV.lifecycle.app and DV.lifecycle.build are read-only.',
              'context.lifecycle.page, .request and .transaction exist inside '
                  'a page, a request or a transaction.',
              'Use .listen or .changes. Reading .value in build does not '
                  'redraw.',
            ]),
            DocsStatus('Lifecycle Signals', missing: <String>[
              'Several states are never emitted yet, such as the page\'s '
                  'loading and leaving and the app\'s suspended.',
              'The request lifecycle never reaches completed.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('State'),
          ],
        ),
      ],
    );
