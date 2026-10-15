// A form built in Studio is filled in by visitors. Its submit endpoint sat
// under the Studio mount, behind the Studio grant, so nobody a site was for
// could reach it. It is public now, beside the published pages -- and so it
// is a target: what it accepts is bounded, and what it keeps is only what the
// form asked for.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(
  String method,
  String path, {
  Object? json,
  String? text,
  String contentType = 'application/json',
  String peer = '203.0.113.7',
}) =>
    Request(
      method: method,
      url: Uri.parse('http://localhost:8080$path'),
      headers: Headers(<String, String>{
        if (json != null || text != null) 'content-type': contentType,
        'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
      }),
      peerAddress: DVPeerAddress.parse(peer),
      bodyStream: json == null && text == null
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(text ?? jsonEncode(json))),
    );

Future<Map<String, Object?>> _json(Response response) async {
  final String text = utf8.decode(await response.body!.bytes());
  return text.isEmpty
      ? <String, Object?>{}
      : (jsonDecode(text) as Map).cast<String, Object?>();
}

void main() {
  late Directory root;
  late MemoryDVDatabaseAdapter database;
  late DVAdminServer studio;
  late DVPublishedPages site;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dartvel_public_forms_');
    addTearDown(() => root.deleteSync(recursive: true));
    database = MemoryDVDatabaseAdapter();
    studio = DVAdminServer(
      mount: const DVAdminMount(path: '/__studio', enabled: true, requiresAuth: false),
      root: root.path,
      database: database,
    );
    site = DVPublishedPages(database: () => database);
    final Response made = (await studio.respond(_request('POST', '/__studio/api/forms', json: <String, Object?>{
      'id': 'enquiry',
      'name': 'Enquiry',
      'targetEmail': 'owner@harbour.example',
      'successMessage': 'Thanks.',
      'fields': <Object?>[
        <String, Object?>{'id': 'email', 'label': 'Email', 'type': 'email', 'required': true},
        <String, Object?>{'id': 'boat', 'label': 'Boat', 'type': 'select', 'options': <String>['Skiff', 'Yacht']},
        <String, Object?>{'id': 'message', 'label': 'Message', 'type': 'textarea'},
      ],
    })))!;
    expect(made.status, lessThan(300), reason: '${await _json(made)}');
  });

  Future<Response> submit(Object? json, {String peer = '203.0.113.7'}) async =>
      (await site.respond(_request('POST', '/_dartvel/forms/enquiry', json: json, peer: peer)))!;

  Future<List<Object?>> inbox() async => (await _json((await studio.respond(
          _request('GET', '/__studio/api/forms/submissions')))!))['submissions']!
      as List<Object?>;

  test('a visitor reads the form, without what is the owner\'s', () async {
    final Response response =
        (await site.respond(_request('GET', '/_dartvel/forms/enquiry')))!;
    expect(response.status, 200);
    final Map<String, Object?> form = await _json(response);
    expect(form['name'], 'Enquiry');
    expect((form['fields']! as List), hasLength(3));
    expect(jsonEncode(form), isNot(contains('owner@harbour.example')));
    expect(form.containsKey('submissionsCount'), isFalse);
  });

  test('a visitor submits it, and only what the form asks for is kept', () async {
    final Response response = await submit(<String, Object?>{
      'email': 'sam@example.com',
      'boat': 'Skiff',
      'message': 'Saturday?',
      'role': 'admin',
    });
    final Map<String, Object?> reply = await _json(response);
    expect(response.status, 201, reason: '$reply');
    expect(reply['message'], 'Thanks.');
    final Map<String, Object?> kept =
        ((await inbox()).single! as Map).cast<String, Object?>();
    final Map<String, Object?> data = (kept['data']! as Map).cast<String, Object?>();
    expect(data, <String, Object?>{
      'email': 'sam@example.com',
      'boat': 'Skiff',
      'message': 'Saturday?',
    });
  });

  test('what the form does not accept is refused, and says which field', () async {
    final Response missing = await submit(<String, Object?>{'message': 'hi'});
    expect(missing.status, 400);
    expect('${(await _json(missing))['message']}', contains('Email'));
    expect((await submit(<String, Object?>{'email': 'not-an-address'})).status, 400);
    expect((await submit(<String, Object?>{'email': 'a@b.co', 'boat': 'Tank'})).status, 400);
    expect((await submit(<String, Object?>{'email': 'a@b.co', 'message': 'x' * 10001})).status, 400);
    expect(await inbox(), isEmpty);
  });

  test('a form post from another site, or an oversized one, is refused', () async {
    final Response plain = (await site.respond(_request('POST', '/_dartvel/forms/enquiry',
        text: 'email=a@b.co', contentType: 'application/x-www-form-urlencoded')))!;
    expect(plain.status, 415);
    final Response large = (await site.respond(_request('POST', '/_dartvel/forms/enquiry',
        text: jsonEncode(<String, Object?>{'email': 'a@b.co', 'message': 'x' * 40000}))))!;
    expect(large.status, 413);
    expect(await inbox(), isEmpty);
  });

  test('a filled honeypot is thanked and kept nowhere', () async {
    final Response bot = await submit(<String, Object?>{
      'email': 'bot@example.com',
      '_dv_website': 'http://spam.example',
    });
    expect(bot.status, 201);
    expect(await inbox(), isEmpty);
  });

  test('one source submitting too often is told to wait', () async {
    for (int i = 0; i < 10; i++) {
      expect((await submit(<String, Object?>{'email': 'a$i@b.co'})).status, 201);
    }
    final Response limited = await submit(<String, Object?>{'email': 'z@b.co'});
    expect(limited.status, 429);
    expect(limited.headers.get('retry-after'), isNotNull);
    // Another source is not held back by it.
    expect((await submit(<String, Object?>{'email': 'y@b.co'}, peer: '198.51.100.4')).status, 201);
  });

  test('a form that does not exist is not found', () async {
    final Response response = (await site.respond(
        _request('POST', '/_dartvel/forms/nothing', json: <String, Object?>{'a': 1})))!;
    expect(response.status, 404);
  });
}
