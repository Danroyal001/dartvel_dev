import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel authorization: policies and permission checks',
  description: 'Write who may do what once, in a policy class. Pages, backend '
      'functions and the generated admin all ask that same policy '
      'before they act.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsAuthorizationPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsauthorization,
      lead: <String>[
        'Write who may do what once, in a policy class.',
        'Pages, backend functions and the admin all ask the same policy.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'policy',
          title: 'Write a policy class',
          children: <Widget>[
            DocsCode('authz-policy'),
            Bullets(<String>[
              '@DVPolicy(Order) registers each method named after an action: '
                  'viewAny, view, create, update, delete, restore, forceDelete, '
                  'export or impersonate.',
              'Each method takes the user and the resource. Make the resource '
                  'nullable to answer for a route, which has none.',
              'The class can live anywhere under lib and needs a constructor '
                  'with no arguments.',
            ]),
            DocsNote('Keep server policies free of Flutter',
                'The backend loads a policy only when its file does not import '
                'Flutter. The generated barrel exports Flutter, so import '
                'dartvel_core in a policy the server enforces.'),
          ],
        ),
        DocsSection(
          id: 'guard',
          title: 'Guard pages and functions',
          children: <Widget>[
            DocsCode('backend-context'),
            DocsCode('models-admin-page'),
            Bullets(<String>[
              'policy: \'Order.update\' asks OrderPolicy.update.',
              'DVPolicies has shared names: viewAdmin, refund, manageBilling, '
                  'exportData and impersonate.',
              'A route whose policy no class answers stops the build.',
            ]),
          ],
        ),
        DocsSection(
          id: 'check',
          title: 'Check a permission in code',
          children: <Widget>[
            DocsCode('authz-check'),
            DocsText('An action nothing registered is denied. authorize(...) '
                'throws instead of returning false.'),
          ],
        ),
        DocsSection(
          id: 'register',
          title: 'Register a rule without a class',
          children: <Widget>[
            DocsCode('authz-register'),
            DocsText('A rule you register yourself wins over a declared '
                'policy for the same action.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Authorization', missing: <String>[
              'A standalone Model.Form checks no policy.',
              'The admin does not check view or viewAny yet.',
            ]),
          ],
        ),
      ],
    );
