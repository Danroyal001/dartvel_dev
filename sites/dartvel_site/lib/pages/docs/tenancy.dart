import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel multi-tenancy: one deployment, many customers', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsTenancyPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docstenancy,
      lead: <String>[
        'Serve many customers from one deployment, each seeing only their own '
            'data.',
        'The tenant is resolved per request and carried into jobs and the '
            'cache.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'resolve',
          title: 'Resolve the tenant from the request',
          children: <Widget>[
            DocsYaml('yaml-tenancy'),
            Bullets(<String>[
              'source is subdomain, header, path-prefix or query-parameter.',
              'header and queryParameter rename the header (x-tenant) and the '
                  'parameter (tenant).',
              'require: true refuses a request with no tenant.',
            ]),
          ],
        ),
        DocsSection(
          id: 'models',
          title: 'Scope a model to the tenant',
          children: <Widget>[
            DocsCode('tenancy-model'),
            Bullets(<String>[
              'The table gets a dv_tenant column, and every read and write '
                  'filters on it.',
              'A tenant-scoped model cannot have public pages.',
              'For a table with rows, run dartvel db migrate --tenant <id>.',
            ]),
          ],
        ),
        DocsSection(
          id: 'scope',
          title: 'Read and switch the tenant in code',
          children: <Widget>[
            DocsCode('tenancy-scope'),
            DocsText('A job dispatched inside withTenant runs in that tenant. '
                'Cache keys are prefixed with it.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Multi-tenancy', missing: <String>[
              'schema-per-tenant and database-per-tenant do not create the '
                  'schemas or databases.',
              'Hosted search engines are not scoped by tenant.',
            ]),
          ],
        ),
      ],
    );
