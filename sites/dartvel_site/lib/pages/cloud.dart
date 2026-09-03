import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Cloud — Dartvel', showAppBar: false)
@pragma('vm:entry-point')
Widget _cloudPage(BuildContext context) => const SingleChildScrollView(
      child: DVBox.list(<Widget>[
        Section(
          children: <Widget>[
            Eyebrow('COMING SOON'),
            Heading('Dartvel Cloud.', level: 1),
            Body(
              'Deploy a Dartvel application without assembling the runtime '
              'around it. Nothing here is available yet, and this page says so '
              'rather than collecting sign-ups for something that does not '
              'exist.',
              width: 640,
            ),
            Body(
              'Everything Dartvel does today runs on infrastructure you '
              'already have. dartvel build produces the artifact and dartvel '
              'deploy pushes it; Cloud is meant to remove that step, not to '
              'become the only way to run one.',
              width: 640,
            ),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            Eyebrow('WHAT IT IS MEANT TO BE'),
            DVBox.wrapLine(<Widget>[
              SiteCard(
                'One command',
                'dartvel deploy, with the backend, the database, the queues '
                'and the static build going out together.',
              ),
              SiteCard(
                'The runtime as it is built',
                'The same Axum and Tokio server the CLI runs locally, rather '
                'than a different one you discover in production.',
              ),
              SiteCard(
                'Durable work included',
                'Jobs and queues run where the app runs, so background work '
                'is not a second piece of infrastructure to stand up.',
              ),
              SiteCard(
                'Not a lock-in',
                'Self-hosting stays a supported path. Cloud is the '
                'convenience, not the requirement.',
              ),
            ], spacing: 16),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('ADVANCED STUDIO — IN PRO'),
            Heading('Design in Figma. Ship as Dart.'),
            Body(
              'Studio\'s page builder is free forever. Pro adds what only '
              'starts mattering when more than one person touches the '
              'application — and one thing that matters on day one: import.',
              width: 640,
            ),
            DVBox.wrapLine(<Widget>[
              SiteCard(
                'Figma import',
                'Paste a file URL. Every top-level frame becomes a page you '
                'can open in the builder and export as an ordinary @DVPage — '
                'auto-layout to rows and lists, fills to colours, text styles '
                'to text, image fills resolved. Every Figma component becomes '
                'a reusable component and every instance stays an instance of '
                'it, so a change pushed from the component reaches the pages. '
                'Built.',
              ),
              SiteCard(
                'Workflow builder',
                'Backend functions composed visually as a step tree that runs '
                'directly and exports to a plain @DVBackendFunction, so the '
                'builder can be dropped at any time. Built.',
              ),
              SiteCard(
                'Reusable components',
                'Save any node on a page as a named component, place it on '
                'other pages, and push a change to every instance across '
                'every page — each instance stays an ordinary node you can '
                'still style on its own. Built.',
              ),
              SiteCard(
                'Revision history',
                'Every save of every page kept, numbered, timestamped and '
                'attributed, and any of them restorable with one tap — the '
                'restore is a revision too, so history never loses a state. '
                'Built.',
              ),
              SiteCard(
                'Multi-user editing',
                'Two people on one page see each other\'s edits as they '
                'happen, with who is here and what they have selected shown '
                'as presence. Viewers follow and cannot type; editors edit; '
                'every change is written to an audit trail with who did it. '
                'Built.',
              ),
              SiteCard(
                'Approval',
                'A page published by an editor waits for an approver before '
                'it goes live; approving writes it, rejecting says why, and '
                'both are in the audit trail. An approver\'s own publish goes '
                'straight through. Built.',
              ),
              SiteCard(
                'Enterprise SSO',
                'SAML, SCIM provisioning and directory sync for your team, '
                'enforced org-wide. Planned; not yet built.',
              ),
            ], spacing: 16),
          ],
        ),
        Section(
          children: <Widget>[
            Eyebrow('IN THE MEANTIME'),
            Heading('It already deploys anywhere.'),
            Body(
              'dartvel build web produces static output for any host — this '
              'site is that output. The backend builds to a binary with the '
              'Rust runtime linked in, so it runs wherever you can run a '
              'process.',
              width: 640,
            ),
            CodeBlock(<String>[
              'dartvel build web       # static output',
              'dartvel build linux     # the app, with the runtime linked in',
              'dartvel deploy          # to a host you configure',
            ]),
            DVBox.wrapLine(<Widget>[
              GhostLink('Read the docs', '/docs'),
              GhostLink('See what works today', '/features'),
            ], spacing: 12),
          ],
        ),
        SiteFooter(),
      ], spacing: 0),
    );
