import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel edge security: sign-in limits, WAF rules and query budgets',
  description: 'Password guessing is slowed on the sign-in your server already '
      'has, with no setup. Add firewall rules, breached-password '
      'checks and GraphQL budgets where you need them.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsEdgeSecurityPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsedgesecurity,
      lead: <String>[
        'Password guessing is slowed down on the sign-in your server already '
            'has, with no setup.',
        'Add firewall rules, breached-password checks and GraphQL budgets '
            'where you need them.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'sign-in',
          title: 'Sign-in is rate limited by default',
          children: <Widget>[
            Bullets(<String>[
              'With a database, the generated server guards sign-in and sign-up: '
                  '5 failures per account and 100 per source in 15 minutes.',
              'A refused sign-in takes at least 400 ms and says the same thing '
                  'whether or not the account exists.',
              'Too many failures answer with DV-EDGE-005 and a retry time.',
            ]),
          ],
        ),
        DocsSection(
          id: 'credentials',
          title: 'Refuse breached passwords',
          children: <Widget>[
            DocsCode('edge-credentials'),
            Bullets(<String>[
              'Sign-up and a password change are refused with DV-EDGE-004 when '
                  'the password is in the breach list.',
              'The range query goes through DV.Http, so its host must be '
                  'declared under dartvel.http.hosts.',
              'If the service is down, sign-up goes ahead and logs it. Set '
                  'breachCheckFailsClosed: true to refuse instead.',
            ]),
          ],
        ),
        DocsSection(
          id: 'waf',
          title: 'Block paths by country',
          children: <Widget>[
            DocsCode('edge-waf'),
            Bullets(<String>[
              'The first rule that matches decides. A refusal is logged with '
                  'DV-EDGE-003 and the rule\'s name.',
              'A country header counts only from a proxy you trust. From '
                  'anywhere else the country is unknown.',
              'lint() lists rules that match everything, and rules that have '
                  'matched nothing for 90 days.',
            ]),
          ],
        ),
        DocsSection(
          id: 'graphql',
          title: 'Put a budget on GraphQL queries',
          children: <Widget>[
            DocsYaml('yaml-graphql'),
            Bullets(<String>[
              'Depth and cost budgets are on by default, worked out from your '
                  'models. A query over budget is refused with DV-EDGE-001.',
              'persistedQueries: require answers only queries in the manifest, '
                  'with DV-EDGE-002 for the rest.',
            ]),
          ],
        ),
        DocsSection(
          id: 'proxies',
          title: 'Trust your proxy for the client address',
          children: <Widget>[
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  server:',
              '    trustedProxies: [10.0.0.0/8]',
              '    forwardedHeader: x-forwarded-for',
              '    ipv6SourcePrefix: 64',
            ]),
            Bullets(<String>[
              'Forwarded headers are read only from a peer in trustedProxies. '
                  'DARTVEL_TRUSTED_PROXIES sets the list at run time.',
              'IPv6 clients are counted per /64 by default, so one host cannot '
                  'dodge a limit by changing its address.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Edge Security', missing: <String>[
              'The WAF is not a middleware key or a pubspec setting. You add it '
                  'to a MiddlewareChain you run.',
              'Sign-in counts are kept per process, and there is no firewall or '
                  'captcha provider adapter.',
              'Generated clients do not send persisted query hashes yet.',
            ]),
          ],
        ),
      ],
    );
