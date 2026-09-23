import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel webhooks: signed events with retries',
  description: 'Tell your customers\' systems when something happens, with '
      'signed and retried deliveries. Declare an event, let them '
      'subscribe, then emit it.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsWebhooksPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docswebhooks,
      lead: <String>[
        'Tell your customers\' systems when something happens, with signed and '
            'retried deliveries.',
        'Declare an event, let them subscribe, then emit it.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'emit',
          title: 'Declare, subscribe and emit',
          children: <Widget>[
            DocsCode('webhooks-emit'),
            Bullets(<String>[
              'Emitting an event nobody declared throws '
                  'DVWebhookUndeclaredEventException.',
              'sensitiveFields never leave in a payload, wherever they appear.',
              'signingSecret is the name of a secret, read through DV.Secrets.',
            ]),
          ],
        ),
        DocsSection(
          id: 'deliver',
          title: 'Deliver and retry',
          children: <Widget>[
            Bullets(<String>[
              'drainAll() sends pending deliveries. Failures retry up to 5 '
                  'times, 30 seconds apart by default.',
              'A subscription is disabled after 20 failures in a row.',
              'deliveries(id) and replay(deliveryId) let you inspect and resend.',
            ]),
          ],
        ),
        DocsSection(
          id: 'verify',
          title: 'Verify a delivery on the receiving side',
          children: <Widget>[
            DocsText('Each request carries dartvel-webhook-id, -event, '
                '-timestamp and -signature headers. The signature is an HMAC '
                'SHA-256 of the timestamp and the body.'),
            DocsCode('webhooks-verify'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Outbound Webhooks', missing: <String>[
              'Subscriptions and events are not generated, and dartvel.webhooks '
                  'in pubspec.yaml is not read.',
              'You call drainAll. Nothing drains deliveries in the background '
                  'yet.',
              'The tenant is recorded and not enforced.',
            ]),
          ],
        ),
      ],
    );
