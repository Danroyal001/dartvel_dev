import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import '../components/site.dart';

@DVPage(title: 'Cloud — Dartvel', showAppBar: false)
@pragma('vm:entry-point')
Widget _cloudPage(BuildContext context) => buildCloudPage(context);

Widget buildCloudPage(BuildContext context) => const SitePage(
      current: '/cloud',
      children: <Widget>[
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
              Card_(
                'One command',
                'dartvel deploy, with the backend, the database, the queues '
                'and the static build going out together.',
              ),
              Card_(
                'The runtime as it is built',
                'The same Axum and Tokio server the CLI runs locally, rather '
                'than a different one you discover in production.',
              ),
              Card_(
                'Durable work included',
                'Jobs and queues run where the app runs, so background work '
                'is not a second piece of infrastructure to stand up.',
              ),
              Card_(
                'Not a lock-in',
                'Self-hosting stays a supported path. Cloud is the '
                'convenience, not the requirement.',
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
      ],
    );
