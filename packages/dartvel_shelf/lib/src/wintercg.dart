import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

class Body {
  final Stream<List<int>> _stream;
  bool _used = false;
  Body(Stream<List<int>> stream) : _stream = stream;

  Stream<List<int>> get stream {
    if (_used) throw StateError('Body already used');
    _used = true;
    return _stream;
  }

  Future<List<int>> bytes() async => (await bytesU8()).toList();

  Future<Uint8List> bytesU8() async {
    final chunks = <Uint8List>[];
    var total = 0;
    await for (final chunk in stream) {
      final u8 = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      chunks.add(u8);
      total += u8.length;
    }
    if (chunks.length == 1) return chunks.first;
    final out = Uint8List(total);
    var offset = 0;
    for (final c in chunks) {
      out.setRange(offset, offset + c.length, c);
      offset += c.length;
    }
    return out;
  }

  Future<String> text([Encoding enc = utf8]) async =>
      enc.decode(await bytesU8());

  Future<dynamic> jsonDecode([Encoding enc = utf8]) async =>
      _jsonDecode(await text(enc));
}

dynamic _jsonDecode(String s) {
  try {
    return json.decode(s);
  } catch (_) {
    return s;
  }
}

class Headers {
  final Map<String, List<String>> _map = {};
  Headers([Map<String, dynamic>? init]) {
    if (init != null) {
      init.forEach((k, v) {
        if (v is Iterable) {
          for (final vv in v) {
            append(k, vv.toString());
          }
        } else if (v != null) {
          set(k, v.toString());
        }
      });
    }
  }

  static String _norm(String name) => name.toLowerCase();

  void append(String name, String value) {
    final key = _norm(name);
    (_map[key] ??= <String>[]).add(value);
  }

  void set(String name, String value) {
    _map[_norm(name)] = [value];
  }

  bool has(String name) => _map.containsKey(_norm(name));

  String? get(String name) {
    final vals = _map[_norm(name)];
    if (vals == null || vals.isEmpty) return null;
    return vals.first;
  }

  Iterable<String> getAll(String name) =>
      List.unmodifiable(_map[_norm(name)] ?? const []);

  void delete(String name) => _map.remove(_norm(name));

  Map<String, String> get singleValueMap => {
        for (final e in _map.entries)
          e.key: e.value.isEmpty ? '' : e.value.first
      };

  Map<String, List<String>> get multiValueMap => Map.unmodifiable(_map);
}

class Request {
  final String method;
  final Uri url;
  final Headers headers;
  final Body body;
  final Map<String, String> params;

  Request({
    required this.method,
    required this.url,
    required this.headers,
    required Stream<List<int>> bodyStream,
    Map<String, String>? params,
  })  : params = params == null
            ? <String, String>{}
            : Map<String, String>.from(params),
        body = Body(bodyStream);
}

class Response {
  final int status;
  final Headers headers;
  final Stream<List<int>>? _body;
  final bool isStream;
  Response(this.status, {Headers? headers, Stream<List<int>>? body, this.isStream = false})
      : headers = headers ?? Headers(),
        _body = body;

  // No `!` here: with the language version this package now declares, a
  // private final field promotes after a null check, so the assertion is
  // provably redundant rather than merely unfashionable.
  Body? get body => _body == null ? null : Body(_body);

  static Response text(String s,
      {int status = 200, Headers? headers, Encoding encoding = utf8}) {
    final h = headers ?? Headers();
    if (!h.has('content-type')) {
      h.set('content-type', 'text/plain; charset=${encoding.name}');
    }
    final data = encoding.encode(s);
    return Response(status,
        headers: h, body: Stream<List<int>>.value(Uint8List.fromList(data)));
  }

  static Response json(Object? data, {int status = 200, Headers? headers}) {
    final h = headers ?? Headers();
    if (!h.has('content-type')) {
      h.set('content-type', 'application/json; charset=utf-8');
    }
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(data)));
    return Response(status, headers: h, body: Stream<List<int>>.value(payload));
  }

  static Response stream(void Function(StreamSink<List<int>>) fn,
      {int status = 200, Headers? headers}) {
    final controller = StreamController<List<int>>();
    scheduleMicrotask(() => fn(controller.sink));
    return Response(status,
        headers: headers ?? Headers(), body: controller.stream, isStream: true);
  }

  static Response redirect(String location, [int status = 302]) {
    final headers = Headers()..set('location', location);
    return Response(status, headers: headers);
  }
}

class URLPattern {
  final RegExp _re;
  final List<String> _names;
  URLPattern(String pattern) : this._internal(_normalize(pattern));

  URLPattern._internal(String normalized)
      : _names = RegExp(r':([A-Za-z_][A-Za-z0-9_]*)')
            .allMatches(normalized)
            .map((m) => m.group(1)!)
            .toList(),
        _re = _compile(normalized);

  static String _normalize(String pattern) {
    return pattern
        .replaceAllMapped(RegExp(r'<([A-Za-z_][A-Za-z0-9_]*)(\|[^>]+)?>'), (m) {
      final name = m.group(1)!;
      final custom = m.group(2);
      if (custom != null && custom.isNotEmpty) {
        final regex = custom.substring(1); // drop leading |
        return ':$name($regex)';
      }
      return ':$name';
    });
  }

  static RegExp _compile(String pattern) {
    final escaped = pattern.replaceAllMapped(
        RegExp(r'([.+*?^${}()\[\]|\\])'), (m) => '\\${m[1]}');
    final withNamed = escaped.replaceAllMapped(
        RegExp(r':([A-Za-z_][A-Za-z0-9_]*)(\([^\)]+\))?'), (m) {
      final name = m.group(1)!;
      final custom = m.group(2);
      if (custom != null) {
        return '(?<_$name>${custom.substring(1, custom.length - 1)})';
      }
      return '(?<_$name>[^/]+)';
    });
    return RegExp('^$withNamed\$');
  }

  ({Map<String, String> pathname})? exec(Uri url) {
    final match = _re.firstMatch(url.path);
    if (match == null) return null;
    final params = <String, String>{};
    for (final name in _names) {
      final value = match.namedGroup('_$name');
      if (value != null) params[name] = value;
    }
    return (pathname: params);
  }
}
