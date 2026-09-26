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
          id: 'format',
          title: 'Choose the envelope and the signature',
          children: <Widget>[
            DocsText('With no dartvel.webhooks block, deliveries use Dartvel\'s '
                'envelope and signature. Existing subscribers see no change.'),
            DocsYaml('yaml-webhooks'),
            Bullets(<String>[
              'format: cloudevents sends each delivery as a CloudEvents 1.0.2 '
                  'event. Its id is the delivery id and its type is the event '
                  'name.',
              'mode: structured sends application/cloudevents+json, so every '
                  'attribute is inside the signed body. mode: binary puts the '
                  'attributes in ce- headers, which the signature does not '
                  'cover.',
              'source defaults to /<your package name>.',
              'signature: standard signs the Standard Webhooks way, with '
                  'webhook-id, webhook-timestamp and webhook-signature. The '
                  'subscription\'s secret must hold a whsec_ key.',
              'A key or value Dartvel does not know stops dartvel build with '
                  'DV-WEBHOOK-009.',
            ]),
          ],
        ),
        DocsSection(
          id: 'verify',
          title: 'Verify a delivery on the receiving side',
          children: <Widget>[
            DocsText('By default each request carries dartvel-webhook-id, '
                '-event, -timestamp and -signature headers. The signature is '
                'an HMAC SHA-256 of the timestamp and the body.'),
            DocsCode('webhooks-verify'),
            DocsText('With signature: standard, your customers can verify with '
                'the official standardwebhooks library for their language. '
                'In Dart:'),
            DocsCode('webhooks-verify-standard'),
            DocsText('A receiver reads a CloudEvent in either mode. Verify the '
                'signature first, over the body exactly as it arrived.'),
            DocsCode('webhooks-read-cloudevent'),
          ],
        ),
        DocsSection(
          id: 'catalog',
          title: 'Publish the event catalog',
          children: <Widget>[
            DocsText('dartvel build writes an AsyncAPI 3.0 document for your '
                'declared events, and the backend serves it at '
                '/api/asyncapi.json.'),
            Bullets(<String>[
              'It is read from the same DVWebhookEvent declarations emit '
                  'checks, so the catalog and the code list the same events.',
              'Each message is described in the envelope and with the headers '
                  'dartvel.webhooks selects.',
              'Write each event name as a string literal. A name the build '
                  'cannot read stops it with DV-WEBHOOK-010.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Outbound Webhooks', missing: <String>[
              'Subscriptions and events are not generated.',
              'The envelope and signature are set for the whole app. A '
                  'subscription cannot choose its own yet.',
              'The AsyncAPI document describes the envelope. The data inside '
                  'it has no schema yet.',
              'You call drainAll. Nothing drains deliveries in the background '
                  'yet.',
              'The tenant is recorded and not enforced.',
            ]),
          ],
        ),
      ],
    );
