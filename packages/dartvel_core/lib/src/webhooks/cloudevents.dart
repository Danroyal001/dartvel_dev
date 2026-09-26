/// CloudEvents 1.0.2 (https://cloudevents.io) over HTTP, in both of the HTTP
/// binding's content modes.
///
/// CloudEvents standardises the envelope -- `specversion`, `id`, `source`,
/// `type`, `time`, `datacontenttype`, `data` -- so that a consumer's router,
/// queue or serverless trigger reads an event from any producer the same way.
/// An application sets `dartvel.webhooks.format: cloudevents` and its
/// deliveries leave in this envelope; a receiving application reads one with
/// [DVCloudEvent.fromHttp] whichever mode the sender chose.
///
/// - **Structured** (the default): the whole event, attributes and data, is
///   the JSON body, sent as `application/cloudevents+json`. The body is what
///   the webhook signature covers, so every attribute is signed.
/// - **Binary**: the data alone is the body, in its own content type, and
///   each attribute is a `ce-` header. The signature covers the body, so the
///   attributes are not signed; under Standard Webhooks the `webhook-id`
///   header, which is signed, carries the same id as `ce-id`.
///
/// Batches (`application/cloudevents-batch+json`) are refused: a webhook is
/// one event, and a batch would make one delivery's success or failure mean
/// several events'.
library dartvel_core.webhooks.cloudevents;

import 'dart:convert';

/// The HTTP binding's two content modes.
enum DVCloudEventMode { structured, binary }

/// `DV-WEBHOOK-008`: a request that is not a CloudEvent this receiver reads.
class DVCloudEventFormatException implements Exception {
  const DVCloudEventFormatException(this.message);
  final String message;
  String get code => 'DV-WEBHOOK-008';

  @override
  String toString() => '$code: $message';
}

/// An event as HTTP: the headers to send, and the body.
class DVCloudEventMessage {
  const DVCloudEventMessage(this.headers, this.body);
  final Map<String, String> headers;
  final String body;
}

/// One CloudEvent.
class DVCloudEvent {
  const DVCloudEvent({
    required this.id,
    required this.source,
    required this.type,
    this.time,
    this.subject,
    this.dataschema,
    this.datacontenttype,
    this.data,
    this.extensions = const <String, Object?>{},
  });

  /// The only version this reads and writes.
  static const String specversion = '1.0';

  /// Unique per [source]; a consumer deduplicates on the pair.
  final String id;

  /// A URI-reference naming what produced the event.
  final String source;

  /// The event's type, such as `order.paid`.
  final String type;
  final DateTime? time;
  final String? subject;
  final String? dataschema;

  /// The media type of [data]. Unset means JSON in structured mode.
  final String? datacontenttype;

  /// The decoded JSON value when [datacontenttype] is JSON or unset, the text
  /// when it is not, and the bytes of a structured event's `data_base64`.
  final Object? data;

  /// Attributes the specification does not define, by name.
  final Map<String, Object?> extensions;

  static const Set<String> _attributes = <String>{
    'specversion',
    'id',
    'source',
    'type',
    'time',
    'subject',
    'dataschema',
    'datacontenttype',
    'data',
    'data_base64',
  };

  /// Whether [contentType] is JSON: `application/json`, `text/json` or a
  /// `+json` suffix.
  static bool _isJson(String? contentType) {
    if (contentType == null) return true;
    final String media = _mediaType(contentType);
    return media == 'application/json' ||
        media == 'text/json' ||
        media.endsWith('+json');
  }

  static String _mediaType(String contentType) =>
      contentType.split(';').first.trim().toLowerCase();

  /// This event as an HTTP request in [mode].
  DVCloudEventMessage toHttp(
      {DVCloudEventMode mode = DVCloudEventMode.structured}) {
    final String? time = this.time?.toUtc().toIso8601String();
    if (mode == DVCloudEventMode.structured) {
      final Object? data = this.data;
      return DVCloudEventMessage(
        const <String, String>{
          'content-type': 'application/cloudevents+json; charset=utf-8',
        },
        jsonEncode(<String, Object?>{
          'specversion': specversion,
          'id': id,
          'source': source,
          'type': type,
          if (time != null) 'time': time,
          if (subject != null) 'subject': subject,
          if (dataschema != null) 'dataschema': dataschema,
          'datacontenttype': datacontenttype ?? 'application/json',
          ...extensions,
          if (data is List<int> && !_isJson(datacontenttype))
            'data_base64': base64.encode(data)
          else if (data != null)
            'data': data,
        }),
      );
    }
    final String contentType =
        datacontenttype ?? 'application/json; charset=utf-8';
    final Object? data = this.data;
    final String body;
    if (data == null) {
      body = '';
    } else if (_isJson(contentType)) {
      body = jsonEncode(data);
    } else if (data is String) {
      body = data;
    } else {
      throw ArgumentError(
          'Binary mode sends ${_mediaType(contentType)} data as text; '
          'this event\'s data is not a String.');
    }
    return DVCloudEventMessage(
      <String, String>{
        'ce-specversion': specversion,
        'ce-id': _encode(id),
        'ce-source': _encode(source),
        'ce-type': _encode(type),
        if (time != null) 'ce-time': _encode(time),
        if (subject != null) 'ce-subject': _encode(subject!),
        if (dataschema != null) 'ce-dataschema': _encode(dataschema!),
        for (final MapEntry<String, Object?> e in extensions.entries)
          if (e.value != null) 'ce-${e.key}': _encode('${e.value}'),
        'content-type': contentType,
      },
      body,
    );
  }

  /// Reads a CloudEvent from an HTTP request, in either mode.
  ///
  /// Structured when the content type is `application/cloudevents+json`,
  /// binary when a `ce-specversion` header is present. Anything else --
  /// plain JSON, a batch, a missing required attribute, a specversion other
  /// than 1.0, a header value that does not decode -- is refused with
  /// [DVCloudEventFormatException] rather than read as far as it goes.
  ///
  /// This reads the envelope; it does not authenticate it. Verify the
  /// request's signature first, over the body exactly as received.
  static DVCloudEvent fromHttp({
    required Map<String, String> headers,
    required String body,
  }) {
    final Map<String, String> lower = <String, String>{
      for (final MapEntry<String, String> e in headers.entries)
        e.key.toLowerCase(): e.value,
    };
    final String? contentType = lower['content-type'];
    final String? media = contentType == null ? null : _mediaType(contentType);
    if (media == 'application/cloudevents-batch+json') {
      throw const DVCloudEventFormatException(
          'a CloudEvents batch is not accepted; send one event per request.');
    }
    if (media == 'application/cloudevents+json') return _structured(body);
    if (lower.containsKey('ce-specversion')) {
      return _binary(lower, contentType, body);
    }
    throw const DVCloudEventFormatException(
        'the request is not a CloudEvent: its content type is not '
        'application/cloudevents+json and it has no ce-specversion header.');
  }

  static DVCloudEvent _structured(String body) {
    final Object? parsed;
    try {
      parsed = jsonDecode(body);
    } on FormatException {
      throw const DVCloudEventFormatException(
          'a structured CloudEvent must be a JSON object; the body is not JSON.');
    }
    if (parsed is! Map<String, Object?>) {
      throw const DVCloudEventFormatException(
          'a structured CloudEvent must be a JSON object.');
    }
    final Map<String, Object?> decoded = parsed;
    String? optional(String name) {
      final Object? value = decoded[name];
      if (value == null) return null;
      if (value is! String) {
        throw DVCloudEventFormatException('"$name" must be a string.');
      }
      return value;
    }

    _checkVersion(optional('specversion'));
    final String? datacontenttype = optional('datacontenttype');
    Object? data = decoded['data'];
    final String? base64Data = optional('data_base64');
    if (base64Data != null) {
      if (decoded.containsKey('data') && decoded['data'] != null) {
        throw const DVCloudEventFormatException(
            'a CloudEvent carries data or data_base64, not both.');
      }
      try {
        data = base64.decode(base64Data);
      } on FormatException {
        throw const DVCloudEventFormatException('"data_base64" is not base64.');
      }
    }
    return DVCloudEvent(
      id: _required('id', optional('id')),
      source: _required('source', optional('source')),
      type: _required('type', optional('type')),
      time: _time(optional('time')),
      subject: optional('subject'),
      dataschema: optional('dataschema'),
      datacontenttype: datacontenttype,
      data: data,
      extensions: <String, Object?>{
        for (final MapEntry<String, Object?> e in decoded.entries)
          if (!_attributes.contains(e.key) && e.value != null) e.key: e.value,
      },
    );
  }

  static DVCloudEvent _binary(
      Map<String, String> headers, String? contentType, String body) {
    String? attribute(String name) {
      final String? raw = headers['ce-$name'];
      return raw == null ? null : _decode('ce-$name', raw);
    }

    _checkVersion(attribute('specversion'));
    Object? data;
    if (body.isNotEmpty) {
      if (contentType != null && _isJson(contentType)) {
        try {
          data = jsonDecode(body);
        } on FormatException {
          throw const DVCloudEventFormatException(
              'the data is declared JSON by its content type and is not JSON.');
        }
      } else {
        data = body;
      }
    }
    return DVCloudEvent(
      id: _required('id', attribute('id')),
      source: _required('source', attribute('source')),
      type: _required('type', attribute('type')),
      time: _time(attribute('time')),
      subject: attribute('subject'),
      dataschema: attribute('dataschema'),
      datacontenttype: contentType == null ? null : _mediaType(contentType),
      data: data,
      extensions: <String, Object?>{
        for (final String name in headers.keys)
          if (name.startsWith('ce-') &&
              !_attributes.contains(name.substring(3)))
            name.substring(3): _decode(name, headers[name]!),
      },
    );
  }

  static void _checkVersion(String? version) {
    if (version != specversion) {
      throw DVCloudEventFormatException(
          'specversion must be "$specversion"; this event has '
          '${version == null ? 'none' : '"$version"'}.');
    }
  }

  static String _required(String name, String? value) {
    if (value == null || value.isEmpty) {
      throw DVCloudEventFormatException(
          'the required attribute "$name" is missing or empty.');
    }
    return value;
  }

  static DateTime? _time(String? value) {
    if (value == null) return null;
    final DateTime? parsed = DateTime.tryParse(value);
    if (parsed == null || !value.contains('T')) {
      throw const DVCloudEventFormatException(
          '"time" is not an RFC 3339 timestamp.');
    }
    return parsed.toUtc();
  }

  /// The binding's percent-encoding: space, `"`, `%` and every byte outside
  /// printable ASCII, over the value's UTF-8.
  static String _encode(String value) {
    final StringBuffer out = StringBuffer();
    for (final int byte in utf8.encode(value)) {
      if (byte <= 0x20 || byte >= 0x7F || byte == 0x22 || byte == 0x25) {
        out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
      } else {
        out.writeCharCode(byte);
      }
    }
    return out.toString();
  }

  /// Unquotes a legacy double-quoted value, then undoes one round of
  /// percent-encoding, refusing bytes that are not valid UTF-8 -- overlong
  /// forms included, as the binding requires.
  static String _decode(String header, String raw) {
    String value = raw.trim();
    if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
      final StringBuffer unquoted = StringBuffer();
      for (int i = 1; i < value.length - 1; i++) {
        if (value[i] == r'\' && i + 1 < value.length - 1) i++;
        unquoted.write(value[i]);
      }
      value = unquoted.toString();
    }
    final List<int> bytes = <int>[];
    for (int i = 0; i < value.length; i++) {
      final int unit = value.codeUnitAt(i);
      if (unit == 0x25) {
        final int? byte = i + 2 < value.length
            ? int.tryParse(value.substring(i + 1, i + 3), radix: 16)
            : null;
        if (byte == null) {
          throw DVCloudEventFormatException(
              '$header has a malformed percent-encoding.');
        }
        bytes.add(byte);
        i += 2;
      } else if (unit > 0x7F) {
        bytes.addAll(utf8.encode(String.fromCharCode(unit)));
      } else {
        bytes.add(unit);
      }
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw DVCloudEventFormatException('$header does not decode as UTF-8.');
    }
  }
}
