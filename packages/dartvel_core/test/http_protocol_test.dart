// Protocol negotiation, early hints, and the fallback walk.
//
// A fake transport stands in for the network so the *policy* is what is being
// tested: which protocols get attempted, in what order, and when the walk
// stops. A test that needed a server would be testing the server.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// Records what it was asked to do and answers however the test says.
class _FakeTransport implements DVHttpTransport {
  _FakeTransport({
    required this.supportedProtocols,
    this.failWith,
  });

  @override
  final Set<DVHttpProtocol> supportedProtocols;

  @override
  String get name => 'fake';

  /// Protocols that fail, and whether the failure is worth retrying.
  final Map<DVHttpProtocol, bool>? failWith;

  final List<DVHttpProtocol> attempted = <DVHttpProtocol>[];

  DVHttpProtocol _only(DVHttpRequest request) =>
      request.protocols.protocols.single;

  @override
  Future<DVHttpResponse> send(DVHttpRequest request) async {
    final protocol = _only(request);
    attempted.add(protocol);
    final retryable = failWith?[protocol];
    if (retryable != null) {
      throw DVHttpNegotiationFailure(protocol, 'refused', retryable: retryable);
    }
    return DVHttpResponse(statusCode: 200, body: 'ok', protocol: protocol);
  }

  @override
  Future<DVHttpStreamedResponse> stream(DVHttpRequest request) async {
    final protocol = _only(request);
    attempted.add(protocol);
    return DVHttpStreamedResponse(
      statusCode: 200,
      headers: const <String, String>{},
      body: const Stream<List<int>>.empty(),
      protocol: protocol,
    );
  }
}

void main() {
  final url = Uri.parse('https://example.test/v1/send');

  group('protocol chain', () {
    test('the standard chain prefers HTTP/3 and floors at HTTP/1.1', () {
      expect(
        DVHttpProtocolChain.standard.protocols,
        <DVHttpProtocol>[
          DVHttpProtocol.http3,
          DVHttpProtocol.http2,
          DVHttpProtocol.http11,
        ],
      );
    });

    test('narrowing keeps the chain order, not the capability order', () {
      // Preference belongs to the caller; the transport only says what it can
      // do. If narrowing reordered, a transport could quietly demote HTTP/3.
      final narrowed = DVHttpProtocolChain.standard.supportedBy(
        <DVHttpProtocol>{DVHttpProtocol.http11, DVHttpProtocol.http3},
      );
      expect(narrowed.protocols,
          <DVHttpProtocol>[DVHttpProtocol.http3, DVHttpProtocol.http11]);
    });

    test('ALPN tokens map back, draft h3 versions included', () {
      expect(DVHttpProtocol.fromAlpn('h3'), DVHttpProtocol.http3);
      expect(DVHttpProtocol.fromAlpn('h3-29'), DVHttpProtocol.http3);
      expect(DVHttpProtocol.fromAlpn('h2'), DVHttpProtocol.http2);
      expect(DVHttpProtocol.fromAlpn('HTTP/1.1'), DVHttpProtocol.http11);
      expect(DVHttpProtocol.fromAlpn('spdy/3'), isNull);
    });
  });

  group('fallback', () {
    test('stops at the first protocol that works', () async {
      final transport = _FakeTransport(
        supportedProtocols: const <DVHttpProtocol>{
          DVHttpProtocol.http3,
          DVHttpProtocol.http2,
          DVHttpProtocol.http11,
        },
      );
      final response = await DVHttpFallbackClient(transport)
          .send(DVHttpRequest(url: url));

      expect(transport.attempted, <DVHttpProtocol>[DVHttpProtocol.http3]);
      expect(response.protocol, DVHttpProtocol.http3);
    });

    test('walks down the chain when a protocol is refused', () async {
      // The QUIC case this exists for: UDP blocked, HTTP/2 fine.
      final transport = _FakeTransport(
        supportedProtocols: const <DVHttpProtocol>{
          DVHttpProtocol.http3,
          DVHttpProtocol.http2,
          DVHttpProtocol.http11,
        },
        failWith: const <DVHttpProtocol, bool>{DVHttpProtocol.http3: true},
      );
      final response = await DVHttpFallbackClient(transport)
          .send(DVHttpRequest(url: url));

      expect(transport.attempted,
          <DVHttpProtocol>[DVHttpProtocol.http3, DVHttpProtocol.http2]);
      expect(response.protocol, DVHttpProtocol.http2);
    });

    test('skips protocols the transport cannot speak, without failing',
        () async {
      // Asking for HTTP/3 on a 1.1-only transport is not an error. It is a
      // preference that cannot be honoured.
      final transport = _FakeTransport(
        supportedProtocols: const <DVHttpProtocol>{DVHttpProtocol.http11},
      );
      final response = await DVHttpFallbackClient(transport)
          .send(DVHttpRequest(url: url));

      expect(transport.attempted, <DVHttpProtocol>[DVHttpProtocol.http11]);
      expect(response.protocol, DVHttpProtocol.http11);
    });

    test('a non-retryable failure stops the walk', () async {
      // The request reached the origin and was answered. Trying again over a
      // different handshake would just ask the same question.
      final transport = _FakeTransport(
        supportedProtocols: const <DVHttpProtocol>{
          DVHttpProtocol.http3,
          DVHttpProtocol.http2,
          DVHttpProtocol.http11,
        },
        failWith: const <DVHttpProtocol, bool>{DVHttpProtocol.http3: false},
      );

      await expectLater(
        DVHttpFallbackClient(transport).send(DVHttpRequest(url: url)),
        throwsA(isA<DVHttpProtocolExhausted>()),
      );
      expect(transport.attempted, <DVHttpProtocol>[DVHttpProtocol.http3]);
    });

    test('an HTTP/2-only request never silently downgrades', () async {
      // APNS is HTTP/2-only. Falling back to 1.1 would turn a configuration
      // problem into a connection error that cannot explain itself.
      final transport = _FakeTransport(
        supportedProtocols: const <DVHttpProtocol>{DVHttpProtocol.http11},
      );

      await expectLater(
        DVHttpFallbackClient(transport).send(
          DVHttpRequest(url: url, protocols: DVHttpProtocolChain.http2Only),
        ),
        throwsA(isA<DVHttpProtocolExhausted>()),
      );
      expect(transport.attempted, isEmpty);
    });

    test('exhaustion reports every attempt, not just the last', () async {
      final transport = _FakeTransport(
        supportedProtocols: const <DVHttpProtocol>{
          DVHttpProtocol.http3,
          DVHttpProtocol.http2,
        },
        failWith: const <DVHttpProtocol, bool>{
          DVHttpProtocol.http3: true,
          DVHttpProtocol.http2: true,
        },
      );

      try {
        await DVHttpFallbackClient(transport).send(DVHttpRequest(url: url));
        fail('expected exhaustion');
      } on DVHttpProtocolExhausted catch (error) {
        expect(error.attempts, hasLength(2));
        expect(error.attempts.map((a) => a.protocol),
            <DVHttpProtocol>[DVHttpProtocol.http3, DVHttpProtocol.http2]);
        expect(error.toString(), contains('h3'));
        expect(error.toString(), contains('h2'));
      }
    });
  });

  group('early hints', () {
    test('parses a preload link', () {
      final hints = const DVEarlyHints(<String, String>{
        'link': '</style.css>; rel=preload; as=style',
      });
      expect(hints.links, hasLength(1));
      expect(hints.links.single.uri, '/style.css');
      expect(hints.links.single.rel, 'preload');
      expect(hints.links.single.asType, 'style');
    });

    test('splits multiple links without splitting inside the URL', () {
      // A comma is legal in a URL. Splitting on every comma is the obvious
      // implementation and it corrupts exactly this case.
      final hints = const DVEarlyHints(<String, String>{
        'link': '</a,b.css>; rel=preload; as=style, </c.js>; rel=preload; '
            'as=script',
      });
      expect(hints.links.map((l) => l.uri), <String>['/a,b.css', '/c.js']);
      expect(hints.links.last.asType, 'script');
    });

    test('keeps quoted parameters intact', () {
      final hints = const DVEarlyHints(<String, String>{
        'link': '</f.woff2>; rel="preload"; as="font"; crossorigin="anonymous"',
      });
      final link = hints.links.single;
      expect(link.rel, 'preload');
      expect(link.asType, 'font');
      expect(link.parameters['crossorigin'], 'anonymous');
    });

    test('a malformed hint is skipped, not thrown', () {
      // Early hints are an optimisation. Failing a request over one would make
      // the feature worse than not having it.
      final hints = const DVEarlyHints(<String, String>{
        'link': 'garbage, </ok.css>; rel=preload',
      });
      expect(hints.links.map((l) => l.uri), <String>['/ok.css']);
    });

    test('no link header means no links', () {
      expect(const DVEarlyHints(<String, String>{}).links, isEmpty);
    });
  });

  compositeTests();

  group('default transport', () {
    tearDown(() => dvUseHttpTransport(null));

    test('package:http is declared HTTP/1.1 only', () {
      // It is dart:io's HttpClient underneath, which does not speak HTTP/2.
      // Saying so is what lets the fallback driver skip rather than pretend.
      expect(
        const DVPackageHttpTransport().supportedProtocols,
        const <DVHttpProtocol>{DVHttpProtocol.http11},
      );
    });

    test('the browser is declared to speak all three', () {
      // It negotiates them itself and acts on early hints without being asked.
      expect(
        const DVBrowserHttpTransport().supportedProtocols,
        containsAll(<DVHttpProtocol>[
          DVHttpProtocol.http3,
          DVHttpProtocol.http2,
          DVHttpProtocol.http11,
        ]),
      );
    });

    test('the native client is declared to speak HTTP/3 as well as HTTP/2', () {
      // The Rust client speaks both — quinn and h3 for QUIC, h2 for TCP — and
      // what it declares here is the only thing the fallback chain consults.
      // Under-declaring is silent: the request still succeeds, over h2,
      // and nothing reports that HTTP/3 was never attempted.
      expect(
        const DVRustHttpTransport('libdartvel.so').supportedProtocols,
        containsAll(<DVHttpProtocol>[
          DVHttpProtocol.http3,
          DVHttpProtocol.http2,
        ]),
      );
    });

    test('the native client does not claim HTTP/1.1', () {
      // ALPN is negotiated in the handshake and the Rust client asks for one
      // token. There is no HTTP/1.1 path through it, and claiming one would
      // route requests into a transport that cannot serve them instead of
      // letting package:http take them.
      expect(
        const DVRustHttpTransport('libdartvel.so').supportedProtocols,
        isNot(contains(DVHttpProtocol.http11)),
      );
    });

    test('exhaustion says why the native transport is missing, when it is', () {
      // The message a macOS or Windows user gets when calling APNS without a
      // Rust toolchain was "http cannot speak h2" — true, and useless. Only a
      // prebuilt Linux library is committed, so on those platforms the native
      // transport does not load and package:http is what remains. Nothing
      // connected the two facts for the reader.
      dvHttpTransportHint = 'native HTTP/2 library not loaded: not built here';
      addTearDown(() => dvHttpTransportHint = null);

      final error = DVHttpProtocolExhausted(
        Uri.parse('https://api.push.apple.com/3/device/abc'),
        const <DVHttpNegotiationFailure>[
          DVHttpNegotiationFailure(
              DVHttpProtocol.http2, 'http cannot speak h2', retryable: false),
        ],
      );

      expect(error.toString(), contains('not built here'),
          reason: 'the reason the native transport is absent belongs in the '
              'error, since that is the only place the caller looks');
    });

    test('exhaustion says nothing extra when the native transport is fine', () {
      // A hint that appears unconditionally is noise, and would point at a
      // missing library on a machine where the library is present and the
      // failure is something else entirely.
      dvHttpTransportHint = null;
      final error = DVHttpProtocolExhausted(
        Uri.parse('https://example.test/'),
        const <DVHttpNegotiationFailure>[
          DVHttpNegotiationFailure(DVHttpProtocol.http2, 'refused'),
        ],
      );
      expect(error.toString(), isNot(contains('native')));
    });

    test('the absence message names the path and what to do about it', () {
      final reason = describeNativeTransportAbsence(
          '/app/lib/native/macos-arm64/libdartvel_shelf.dylib', null);

      // Three things a reader needs: which protocols they lost, where it
      // looked, and what makes it appear. A message missing any of them sends
      // someone to read Dartvel's source to find out.
      expect(reason, contains('HTTP/2'));
      expect(reason, contains('macos-arm64'));
      expect(reason, contains('cargo'));
    });

    test('an open failure is reported differently from a missing file', () {
      // "It is not there" and "it is there and would not load" call for
      // different actions, and a stale or wrong-architecture library is the
      // second.
      final missing = describeNativeTransportAbsence('/x/lib.so', null);
      final broken = describeNativeTransportAbsence(
          '/x/lib.so', ArgumentError('undefined symbol: dv_http_send'));

      expect(missing, contains('not there'));
      expect(broken, contains('undefined symbol'));
      expect(broken, isNot(contains('not there')));
    });

    test('a registered transport replaces the default and can be removed', () {
      final fake = _FakeTransport(
        supportedProtocols: const <DVHttpProtocol>{DVHttpProtocol.http2},
      );
      expect(dvUseHttpTransport(fake), isNull);
      expect(dvHttpTransport, same(fake));
      dvUseHttpTransport(null);
      expect(dvHttpTransport, isNot(same(fake)));
    });
  });
}

// Appended: routing per protocol, which is what lets a native client ship one
// protocol at a time instead of all at once.
void compositeTests() {
  final url = Uri.parse('https://example.test/v1/send');

  group('composite transport', () {
    test('advertises the union of what its members speak', () {
      final composite = DVCompositeHttpTransport(<DVHttpTransport>[
        _FakeTransport(
            supportedProtocols: const <DVHttpProtocol>{DVHttpProtocol.http2}),
        const DVPackageHttpTransport(),
      ]);
      expect(composite.supportedProtocols,
          <DVHttpProtocol>{DVHttpProtocol.http2, DVHttpProtocol.http11});
    });

    test('sends each protocol to the member that claims it', () async {
      // The shipping case: HTTP/2 to a native client, HTTP/1.1 to
      // package:http, with neither reimplementing the other.
      final native = _FakeTransport(
          supportedProtocols: const <DVHttpProtocol>{DVHttpProtocol.http2});
      final composite = DVCompositeHttpTransport(<DVHttpTransport>[
        native,
        const DVPackageHttpTransport(),
      ]);

      final response = await DVHttpFallbackClient(composite).send(
        DVHttpRequest(url: url, protocols: DVHttpProtocolChain.http2Only),
      );

      expect(native.attempted, <DVHttpProtocol>[DVHttpProtocol.http2]);
      expect(response.protocol, DVHttpProtocol.http2);
    });

    test('the first claimant owns a protocol, so order is precedence', () {
      final first = _FakeTransport(
          supportedProtocols: const <DVHttpProtocol>{DVHttpProtocol.http11});
      final composite = DVCompositeHttpTransport(<DVHttpTransport>[
        first,
        const DVPackageHttpTransport(),
      ]);
      expect(composite.transportFor(DVHttpProtocol.http11), same(first));
    });

    test('an unclaimed protocol is a non-retryable failure', () {
      // Nothing else in the composite could serve it either, so walking on
      // would only produce the same answer more slowly.
      final composite = DVCompositeHttpTransport(
          <DVHttpTransport>[const DVPackageHttpTransport()]);
      expect(composite.transportFor(DVHttpProtocol.http3), isNull);
    });
  });
}
