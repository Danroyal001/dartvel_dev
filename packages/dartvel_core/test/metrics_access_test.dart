// GET /metrics answers the operator, not the internet.
//
// dartvel.dev served its request counts, route timings and uptime to anyone
// who asked: /metrics answered every caller. A scraper sits on the same host
// or network as the server, or holds a token; a stranger on the internet is
// told what a path nobody serves tells them.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart'
    show DVClientAddress, DVPeerAddress, dvConfigureRuntimeLogging;
import 'package:dartvel_core/src/http/router.dart';
import 'package:dartvel_core/src/http/wintercg.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

Future<Response> metrics({
  String? peer,
  Map<String, String> headers = const <String, String>{},
}) {
  final Headers h = Headers();
  headers.forEach(h.set);
  return Router()(Request(
    method: 'GET',
    url: Uri.parse('http://app.test/metrics'),
    headers: h,
    bodyStream: const Stream<List<int>>.empty(),
    peerAddress: peer == null ? null : DVPeerAddress.parse(peer),
  ));
}

void main() {
  tearDown(() {
    DVClientAddress.reset();
    DVObservability.metricsToken = null;
  });

  test('a caller on the internet gets a 404', () async {
    expect((await metrics(peer: '203.0.113.9:51000')).status, 404);
  });

  test('the same host and a private network are answered', () async {
    expect((await metrics(peer: '127.0.0.1:51000')).status, 200);
    expect((await metrics(peer: '10.1.2.3:51000')).status, 200);
    expect((await metrics(peer: '[::1]:51000')).status, 200);
  });

  test('a public caller forwarded by a proxy on the same host gets a 404, '
      'trusted proxy or not', () async {
    // No proxy trusted: the peer is the proxy, and the request still came
    // from somewhere else.
    expect(
        (await metrics(
                peer: '127.0.0.1:51000',
                headers: <String, String>{'x-forwarded-for': '203.0.113.9'}))
            .status,
        404);
    DVClientAddress.install(
        DVClientAddress.parse(const <String>['127.0.0.1/32']));
    expect(
        (await metrics(
                peer: '127.0.0.1:51000',
                headers: <String, String>{'x-forwarded-for': '203.0.113.9'}))
            .status,
        404);
  });

  test('the metrics token opens it from anywhere, and a wrong one does not',
      () async {
    dvConfigureRuntimeLogging(
        const <String, String>{'DARTVEL_METRICS_TOKEN': 'a-long-scrape-token'},
        write: (_) {});
    expect(
        (await metrics(
                peer: '203.0.113.9:51000',
                headers: <String, String>{
                  'authorization': 'Bearer a-long-scrape-token'
                }))
            .status,
        200);
    expect(
        (await metrics(
                peer: '203.0.113.9:51000',
                headers: <String, String>{'authorization': 'Bearer wrong'}))
            .status,
        404);
  });
}
