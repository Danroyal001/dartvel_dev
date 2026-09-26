import 'dart:convert';

import 'package:dartvel_core/dartvel.dart'
    show
        DVCloudEventMode,
        DVWebhookFormat,
        DVWebhookSignatureScheme,
        DVWebhooksConfig;

/// The webhook event names an application declares, from its sources as
/// `(path, source)` pairs, sorted and without repeats.
///
/// The declaration is the runtime's own: `DVWebhookEvent('order.paid')`,
/// which `DV.Webhooks.emit` refuses to send without (`DV-WEBHOOK-006`).
/// Reading the document off the same call is what keeps the catalog a
/// customer reads from drifting from what the code can send. The one way it
/// could drift is a name the build cannot read -- a variable, an
/// interpolation -- so that is refused here (`DV-WEBHOOK-010`) rather than
/// left out of the document.
List<String> discoverWebhookEvents(List<(String, String)> sources) {
  final Set<String> names = <String>{};
  final RegExp call = RegExp(r'\bDVWebhookEvent\s*\(');
  for (final (String path, String raw) in sources) {
    if (!raw.contains('DVWebhookEvent')) continue;
    final String source = _blankComments(raw);
    for (final Match match in call.allMatches(source)) {
      final int start = match.end;
      final String? name = _literalAt(source, start);
      if (name == null) {
        final int line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
        throw StateError(
          'DV-WEBHOOK-010: $path:$line declares a DVWebhookEvent whose name is '
          'not a plain string literal. The generated AsyncAPI document lists '
          'every declared event, and this one could not be read at build '
          "time; write its name as a literal, such as DVWebhookEvent('order.paid').",
        );
      }
      names.add(name);
    }
  }
  return names.toList()..sort();
}

/// The string literal starting at [from] (after whitespace), when it is the
/// whole first argument: quoted, uninterpolated, and followed by `,` or `)`.
String? _literalAt(String source, int from) {
  int i = from;
  while (i < source.length && source[i].trim().isEmpty) {
    i++;
  }
  bool raw = false;
  if (i < source.length && source[i] == 'r') {
    raw = true;
    i++;
  }
  if (i >= source.length) return null;
  final String quote = source[i];
  if (quote != "'" && quote != '"') return null;
  if (source.startsWith(quote * 3, i)) return null;
  final StringBuffer value = StringBuffer();
  i++;
  while (i < source.length && source[i] != quote) {
    final String c = source[i];
    if (c == '\n') return null;
    if (!raw && c == r'$') return null;
    if (!raw && c == r'\') {
      if (i + 1 >= source.length) return null;
      value.write(source[i + 1]);
      i += 2;
      continue;
    }
    value.write(c);
    i++;
  }
  if (i >= source.length) return null;
  i++;
  while (i < source.length && source[i].trim().isEmpty) {
    i++;
  }
  if (i >= source.length || (source[i] != ',' && source[i] != ')')) {
    return null;
  }
  return value.toString();
}

/// [source] with every comment replaced by spaces, newlines kept, so a match
/// still reports the line it is on.
String _blankComments(String source) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  String? quote;
  while (i < source.length) {
    final String c = source[i];
    if (quote != null) {
      out.write(c);
      if (c == r'\' && i + 1 < source.length) {
        out.write(source[i + 1]);
        i += 2;
        continue;
      }
      if (c == quote || c == '\n') quote = null;
      i++;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      out.write(c);
      i++;
      continue;
    }
    if (source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (source.startsWith('/*', i)) {
      final int end = source.indexOf('*/', i + 2);
      final int stop = end == -1 ? source.length : end + 2;
      for (; i < stop; i++) {
        out.write(source[i] == '\n' ? '\n' : ' ');
      }
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// A component key for [name]: AsyncAPI keys match `^[A-Za-z0-9._-]+$`.
String _key(String name) {
  final String key = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return key.isEmpty ? '_' : key;
}

/// Builds the AsyncAPI 3.0.0 document for an application's outbound
/// webhooks: one channel and one `send` operation per declared event, each
/// message described in the envelope and with the signature headers
/// [config] selects, so the document says what is actually sent.
///
/// A channel's address is the subscriber's URL, which belongs to each
/// subscription and not to the application, so it is null -- AsyncAPI's
/// "unknown" -- rather than a guess.
Map<String, Object?> buildAsyncApiDocument({
  required String title,
  required String version,
  required List<String> events,
  required DVWebhooksConfig config,
}) {
  final bool cloudEvents = config.format == DVWebhookFormat.cloudevents;
  final bool binary =
      cloudEvents && config.cloudEventsMode == DVCloudEventMode.binary;
  final bool standard = config.signature == DVWebhookSignatureScheme.standard;
  final String contentType = cloudEvents && !binary
      ? 'application/cloudevents+json'
      : 'application/json';

  final String signing = standard
      ? 'Signed with Standard Webhooks (https://www.standardwebhooks.com): '
          'HMAC-SHA256 over `webhook-id.webhook-timestamp.body` with the '
          'base64-decoded `whsec_` key, sent as space-delimited `v1,<base64>` '
          'entries in `webhook-signature`. Verify with an official '
          'standardwebhooks library.'
      : 'Signed with HMAC-SHA256 over `timestamp.body`, sent as '
          'comma-separated `v1=<hex>` entries in `dartvel-webhook-signature` '
          'with the timestamp in `dartvel-webhook-timestamp`.';
  final String envelope = !cloudEvents
      ? 'The body is Dartvel\'s envelope: `{id, event, created, data}`.'
      : binary
          ? 'Each delivery is a CloudEvents 1.0.2 event in HTTP binary mode: '
              'the attributes are `ce-` headers and the body is the data. The '
              'signature covers the body, not the `ce-` headers.'
          : 'Each delivery is a CloudEvents 1.0.2 event in HTTP structured '
              'mode, sent as `application/cloudevents+json`.';

  Map<String, Object?> str([Map<String, Object?> more = const <String, Object?>{}]) =>
      <String, Object?>{'type': 'string', ...more};

  Map<String, Object?> headersFor(String event) {
    final Map<String, Object?> properties = <String, Object?>{
      if (!cloudEvents)
        'dartvel-webhook-event': str(<String, Object?>{'const': event}),
      if (binary) ...<String, Object?>{
        'ce-specversion': str(<String, Object?>{'const': '1.0'}),
        'ce-id': str(<String, Object?>{
          'description': 'The delivery id: stable across retries and replays.',
        }),
        'ce-source': str(<String, Object?>{'const': config.source}),
        'ce-type': str(<String, Object?>{'const': event}),
        'ce-time': str(<String, Object?>{'format': 'date-time'}),
      },
      if (standard) ...<String, Object?>{
        'webhook-id': str(<String, Object?>{
          'description': 'The delivery id: stable across retries and replays; '
              'deduplicate on it.',
        }),
        'webhook-timestamp': str(<String, Object?>{
          'pattern': r'^[0-9]+$',
          'description': 'Unix seconds. Refuse one more than five minutes '
              'from now.',
        }),
        'webhook-signature': str(<String, Object?>{
          'pattern': r'^v1,[A-Za-z0-9+/]+={0,2}( v1,[A-Za-z0-9+/]+={0,2})*$',
        }),
      } else ...<String, Object?>{
        'dartvel-webhook-id': str(<String, Object?>{
          'description': 'The delivery id: stable across retries and replays; '
              'deduplicate on it.',
        }),
        'dartvel-webhook-timestamp': str(<String, Object?>{
          'pattern': r'^[0-9]+$',
          'description': 'Unix seconds, inside the signature. Refuse one more '
              'than five minutes from now.',
        }),
        'dartvel-webhook-signature': str(<String, Object?>{
          'pattern': r'^v1=[0-9a-f]{64}(,v1=[0-9a-f]{64})*$',
        }),
      },
    };
    return <String, Object?>{
      'type': 'object',
      'properties': properties,
      'required': properties.keys.toList(),
    };
  }

  Map<String, Object?> payloadFor(String event) {
    if (binary) {
      return const <String, Object?>{
        'description': 'The event\'s data, as JSON.',
      };
    }
    if (cloudEvents) {
      return <String, Object?>{
        'type': 'object',
        'required': <String>[
          'specversion',
          'id',
          'source',
          'type',
          'time',
          'datacontenttype',
        ],
        'properties': <String, Object?>{
          'specversion': str(<String, Object?>{'const': '1.0'}),
          'id': str(<String, Object?>{
            'description': 'The delivery id: stable across retries and '
                'replays.',
          }),
          'source': str(<String, Object?>{'const': config.source}),
          'type': str(<String, Object?>{'const': event}),
          'time': str(<String, Object?>{'format': 'date-time'}),
          'datacontenttype': str(<String, Object?>{'const': 'application/json'}),
          'data': const <String, Object?>{},
        },
      };
    }
    return <String, Object?>{
      'type': 'object',
      'required': <String>['id', 'event', 'created', 'data'],
      'properties': <String, Object?>{
        'id': str(<String, Object?>{
          'description': 'The delivery id: stable across retries and replays.',
        }),
        'event': str(<String, Object?>{'const': event}),
        'created': str(<String, Object?>{'format': 'date-time'}),
        'data': const <String, Object?>{},
      },
    };
  }

  final Map<String, Object?> channels = <String, Object?>{};
  final Map<String, Object?> operations = <String, Object?>{};
  final Map<String, Object?> messages = <String, Object?>{};
  for (final String event in events) {
    final String key = _key(event);
    channels[key] = <String, Object?>{
      'address': null,
      'title': event,
      'description': 'Delivered by HTTPS POST to the URL each subscription '
          'to $event names.',
      'messages': <String, Object?>{
        key: <String, Object?>{r'$ref': '#/components/messages/$key'},
      },
    };
    operations[key] = <String, Object?>{
      'action': 'send',
      'title': 'Send $event',
      'channel': <String, Object?>{r'$ref': '#/channels/$key'},
      'messages': <Object?>[
        <String, Object?>{r'$ref': '#/channels/$key/messages/$key'},
      ],
      'bindings': const <String, Object?>{
        'http': <String, Object?>{'method': 'POST', 'bindingVersion': '0.3.0'},
      },
    };
    messages[key] = <String, Object?>{
      'name': event,
      'title': event,
      'contentType': contentType,
      'headers': headersFor(event),
      'payload': payloadFor(event),
    };
  }

  return <String, Object?>{
    'asyncapi': '3.0.0',
    'info': <String, Object?>{
      'title': title,
      'version': version,
      'description': 'The webhook events this application sends. $envelope '
          '$signing Delivery is at least once; a 2xx response acknowledges it.',
    },
    'defaultContentType': contentType,
    'channels': channels,
    'operations': operations,
    'components': <String, Object?>{'messages': messages},
  };
}

/// The document as pretty JSON, for writing into the client and serving.
String encodeAsyncApiDocument(Map<String, Object?> document) =>
    '${const JsonEncoder.withIndent('  ').convert(document)}\n';
