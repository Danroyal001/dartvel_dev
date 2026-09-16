import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Dartvel Cloud and Studio Pro', showAppBar: false)
@pragma('vm:entry-point')
Widget _cloudPage(BuildContext context) => const SingleChildScrollView(
  child: DVBox.list(<Widget>[
    Section(
      children: <Widget>[
        Eyebrow('DARTVEL CLOUD'),
        Heading('Dartvel Cloud does not exist yet.', level: 1),
        Bullets(<String>[
          'There is no sign-up and nothing to buy.',
          'You can deploy a Dartvel app to your own host today.',
        ]),
      ],
    ),
    Section(
      tint: true,
      children: <Widget>[
        Eyebrow('PLANNED'),
        Heading('What Cloud is meant to do.'),
        DVBox.wrapLine(<Widget>[
          SiteCard(
            'One deploy command',
            'dartvel deploy ships the backend, database, queues and web build '
                'together.',
            built: false,
          ),
          SiteCard(
            'The runtime you run locally',
            'The same Axum and Tokio server that dartvel dev starts.',
            built: false,
          ),
          SiteCard(
            'Jobs included',
            'Queues and background jobs run next to the app, with no second '
                'service to set up.',
            built: false,
          ),
        ], spacing: 16),
      ],
    ),
    Section(
      children: <Widget>[
        Eyebrow('STUDIO PRO'),
        Heading('Import a Figma file as pages you can edit and export.'),
        Bullets(<String>[
          'Every top-level frame becomes a page in the builder.',
          'Export each page as an ordinary @DVPage file in your repository.',
          'Pro lives in the private dartvel_enterprise repository.',
        ]),
        DVBox.wrapLine(<Widget>[
          SiteCard(
            'Figma import',
            'Auto-layout, type, shadows, gradients and icons come through. '
                'Images are downloaded, so they survive Figma\'s expiring URLs.',
            built: true,
          ),
          SiteCard(
            'Reusable components',
            'Save a node as a component and push a change to every instance '
                'on every page.',
            built: true,
          ),
          SiteCard(
            'Revision history',
            'Every save is numbered and attributed. Restore any of them in one '
                'tap.',
            built: true,
          ),
          SiteCard(
            'Multi-user editing and approval',
            'See each other\'s edits live. An approver signs off before a page '
                'goes live.',
            built: true,
          ),
          SiteCard(
            'Workflow builder',
            'Compose a backend function visually and export it as a plain '
                '@DVBackendFunction.',
            built: true,
          ),
          SiteCard(
            'Enterprise SSO',
            'SAML, SCIM provisioning and directory sync for your team.',
            built: false,
          ),
        ], spacing: 16),
        Objection(
          'Do I need Pro to build pages visually?',
          'No. The builder with drag and drop, undo and code export is free.',
        ),
        GhostLink('See what the free Studio does', '/features'),
      ],
    ),
    Section(
      tint: true,
      children: <Widget>[
        Eyebrow('TODAY'),
        Heading('Deploy to your own host now.'),
        CodeBlock(<String>[
          'dartvel build web            # static files for any web host',
          'dartvel deploy --functions   # a container, Cloud Run or Lambda artifact per function',
        ]),
        Objection(
          'Will I be locked in to Cloud?',
          'No. You can deploy without it today, and self-hosting stays '
              'supported.',
        ),
        DVBox.wrapLine(<Widget>[
          PrimaryLink('Create your first app', '/docs'),
          GhostLink('See what works today', '/features'),
        ], spacing: 12),
      ],
    ),
    SiteFooter(),
  ], spacing: 0),
);
