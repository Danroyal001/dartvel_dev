import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'peer_address.dart';

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
  Map<String, List<String>>? _decoded;
  Map<String, List<String>> Function()? _decode;

  // The headers, decoded the first time anything reads or changes them when
  // they were built with [Headers.decodedOnRead].
  Map<String, List<String>> get _map =>
      _decoded ??= _decode?.call() ?? <String, List<String>>{};

  /// Headers decoded by [decode] the first time anything reads or changes
  /// them, rather than now.
  ///
  /// For a server building a request from the bytes the connection carried:
  /// many handlers never read a header, and decoding a browser's twenty of
  /// them was a cost every such request paid. [decode] is called at most
  /// once, and must give every name in lowercase, as [Headers] keeps them.
  Headers.decodedOnRead(Map<String, List<String>> Function() decode)
      : _decode = decode;

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

  /// Calls [action] with each value of each header, names in lowercase, in
  /// the order they were added.
  ///
  /// For writing headers out: [multiValueMap] copies the map, which is a
  /// cost every response paid for nothing.
  void forEachValue(void Function(String name, String value) action) {
    _map.forEach((String name, List<String> values) {
      for (final String value in values) {
        action(name, value);
      }
    });
  }
}

class Request {
  final String method;
  final Uri url;
  final Headers headers;
  final Body body;
  final Map<String, String> params;

  /// The address at the other end of the connection this request arrived
  /// on, as the server's socket reports it -- or null when whatever built
  /// this request had no connection to ask.
  ///
  /// Never read from a header. When a proxy sits in front of the server this
  /// is the proxy; who the proxy was forwarding for is the client address
  /// resolver's question, answered only for proxies the application trusts.
  DVPeerAddress? get peerAddress {
    final DVPeerAddress? Function()? read = _peerAddressOf;
    if (read != null) {
      _peerAddressOf = null;
      _peerAddress = read();
    }
    return _peerAddress;
  }

  DVPeerAddress? _peerAddress;
  DVPeerAddress? Function()? _peerAddressOf;

  /// [peerAddress] is the address itself; [peerAddressOf] reads it the
  /// first time [peerAddress] is asked for, for a server that has it as text
  /// and would otherwise parse it for every request, most of which never
  /// look. Given both, [peerAddressOf] wins.
  Request({
    required this.method,
    required this.url,
    required this.headers,
    required Stream<List<int>> bodyStream,
    Map<String, String>? params,
    DVPeerAddress? peerAddress,
    DVPeerAddress? Function()? peerAddressOf,
  })  : _peerAddress = peerAddress,
        _peerAddressOf = peerAddressOf,
        params = params == null
            ? <String, String>{}
            : Map<String, String>.from(params),
        body = Body(bodyStream);
}

class Response {
  final int status;
  final Headers headers;
  final Stream<List<int>>? _stream;
  final Uint8List? _whole;
  final bool isStream;
  Response(this.status,
      {Headers? headers, Stream<List<int>>? body, this.isStream = false})
      : headers = headers ?? Headers(),
        _stream = body,
        _whole = null;

  /// A response whose body is [bytes], already in memory.
  ///
  /// The same response as one built with `body: Stream.value(bytes)`, except
  /// that [bufferedBytes] hands the bytes over directly, so a server sends
  /// them as one copy rather than listening to a stream for them.
  Response.bytes(this.status, Uint8List bytes, {Headers? headers})
      : headers = headers ?? Headers(),
        _stream = null,
        _whole = bytes,
        isStream = false;

  /// The whole body when it is already in memory as one piece
  /// ([Response.bytes], [Response.text], [Response.json]); null for a body
  /// that is a stream, or for no body.
  Uint8List? get bufferedBytes => _whole;

  Stream<List<int>>? get _body {
    final Uint8List? whole = _whole;
    return whole == null ? _stream : Stream<List<int>>.value(whole);
  }

  Body? get body {
    final Stream<List<int>>? stream = _body;
    return stream == null ? null : Body(stream);
  }

  static Response text(String s,
      {int status = 200, Headers? headers, Encoding encoding = utf8}) {
    final h = headers ?? Headers();
    if (!h.has('content-type')) {
      h.set('content-type', 'text/plain; charset=${encoding.name}');
    }
    final data = encoding.encode(s);
    return Response.bytes(
        status, data is Uint8List ? data : Uint8List.fromList(data),
        headers: h);
  }

  static Response json(Object? data, {int status = 200, Headers? headers}) {
    final h = headers ?? Headers();
    if (!h.has('content-type')) {
      h.set('content-type', 'application/json; charset=utf-8');
    }
    return Response.bytes(status, utf8.encode(jsonEncode(data)), headers: h);
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

  /// The path itself, for a pattern with no parameter in it: every other
  /// character is escaped before it is compiled, so such a pattern matches
  /// that one path and nothing else, and is compared rather than run as a
  /// regular expression on every request.
  final String? _literal;

  URLPattern(String pattern) : this._internal(_normalize(pattern));

  URLPattern._internal(String normalized)
      : _names = RegExp(r':([A-Za-z_][A-Za-z0-9_]*)')
            .allMatches(normalized)
            .map((m) => m.group(1)!)
            .toList(),
        _literal = normalized.contains(':') ? null : normalized,
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
    final String? literal = _literal;
    if (literal != null) {
      return url.path == literal ? (pathname: <String, String>{}) : null;
    }
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
