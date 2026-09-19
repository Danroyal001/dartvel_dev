import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

// Shipping a change safely: feature flags, previews per branch, the gates a
// backend release passes, and old clients kept working. Status boxes follow
// the "absent" notes in docs/spec-status.json.
@DVPage(title: 'Dartvel releases: flags, previews, rollouts and old clients', showAppBar: false)
@pragma('vm:entry-point')
Widget _docsReleasesPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsreleases,
      lead: <String>[
        'Turn a feature on for a slice of users, try a branch on its own '
            'preview, and keep old app versions working after the backend '
            'changes.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'flags',
          title: 'Roll a feature out with typed flags',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel flags list',
              'dartvel flags prune',
            ]),
            Bullets(<String>[
              'Declare a flag with an owner and an expiry. The build refuses '
                  'one without them, and reads become typed members of Flags.',
              'Target by percentage, platform, tenant, role, locale or app '
                  'version. The same user lands in the same bucket on the web '
                  'and on a phone.',
              'context.flag(Flags.x) is a signal, so a page redraws when rules '
                  'change. prune lists expired flags with the code still '
                  'reading them.',
            ]),
            DocsStatus('Feature Flags and Staged Rollout', missing: <String>[
              'Rules are not published per environment yet, and Studio has no '
                  'Flags section.',
              'On the backend, a flag is not yet evaluated with the '
                  'request\'s user and client version.',
            ]),
          ],
        ),
        DocsSection(
          id: 'previews',
          title: 'Give every branch its own preview',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel preview create',
              'dartvel preview list',
              'dartvel preview sweep',
            ]),
            Bullets(<String>[
              'Each branch gets its own host, database, bucket and queues. A '
                  'branch copy of production data must declare how sensitive '
                  'columns are cleaned, or it is refused.',
              'Production secrets are never deployed to a preview, and a '
                  'preview secret equal to production\'s stops the create.',
              'Previews send no real mail, skip undeclared schedules, are '
                  'hidden from search engines, and are swept when the branch '
                  'is gone.',
            ]),
            DocsStatus('Preview Environments', missing: <String>[
              'No hosting adapter ships yet, so create reports that there is '
                  'nowhere to host a preview.',
              'No preview logs or captured-mail view.',
            ]),
          ],
        ),
        DocsSection(
          id: 'backend-releases',
          title: 'Release a backend behind health gates',
          children: <Widget>[
            Bullets(<String>[
              'Every release records where it came from. A canary becomes '
                  'blue-green when the host cannot split traffic.',
              'The health gate compares errors and p95 latency with the '
                  'release being replaced, and rolls back on a regression. '
                  'Error budgets, crash health and client compatibility are '
                  'gates too.',
              'An override needs a reason and a person, and both are recorded '
                  'with the evidence it overrode.',
            ]),
            DocsStatus('Backend Release Management', missing: <String>[
              'dartvel deploy does not run these gates yet, and there is no '
                  'rollback command.',
              'No hosting adapters for Cloud Run, Lambda, Fly.io or '
                  'Kubernetes, and no source of per-release traffic numbers.',
            ]),
          ],
        ),
        DocsSection(
          id: 'old-clients',
          title: 'Keep old app versions working',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel compatibility-check',
              'dartvel compatibility-check --against production --histogram '
                  'sessions.json',
            ]),
            Bullets(<String>[
              'dartvel.protocol.lock records the shape of your models and '
                  'functions for each version you still serve.',
              'A change an old client cannot read needs an adapter. Without '
                  'one, that version is refused, so it is never served broken.',
              'Against an environment, the check refuses a deploy that would '
                  'strand too many live sessions, unless you give a reason.',
            ]),
            DocsStatus('Protocol Versioning and Client Compatibility',
                missing: <String>[
              'The contract is not yet read from your project, and no build '
                  'step runs the lock check.',
              'The generated client and backend do not do the version '
                  'handshake yet, so there is no upgrade prompt.',
            ]),
          ],
        ),
      ],
    );
