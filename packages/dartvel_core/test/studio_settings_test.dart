import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Request _request(
  String method,
  String path, {
  Object? body,
  Map<String, String>? headers,
  bool csrf = true,
}) =>
    Request(
      method: method,
      url: Uri.parse(
          'http://127.0.0.1${path.startsWith('/') ? '' : '/'}$path'),
      headers: Headers(<String, String>{
        if (body != null) 'content-type': 'application/json',
        if (csrf) 'x-dartvel-csrf-token': 'abcdefghijklmnopqrstuvwxyz012345',
        ...?headers,
      }),
      bodyStream: body == null
          ? const Stream<List<int>>.empty()
          : Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    );

Future<String> _text(Response response) async =>
    utf8.decode(await response.body!.bytes());

Future<Map<String, Object?>> _json(Response response) async =>
    (jsonDecode(await _text(response)) as Map).cast<String, Object?>();

void main() {
  group('DVStudioSettings model', () {
    test('serializes and deserializes cleanly', () {
      final DVStudioSettings original = DVStudioSettings(
        siteTitle: 'Acme Corp',
        tagline: 'Leading widgets & tools',
        siteUrl: 'https://acme.example.com',
        timezone: 'America/New_York',
        dateFormat: 'MM/DD/YYYY',
        favicon: 'https://acme.example.com/icon.png',
        defaultSeoTitle: 'Acme Corp — Quality Tools',
        defaultSeoDescription: 'Build faster with Acme industrial tools.',
        defaultSeoImage: 'https://acme.example.com/og.jpg',
        socialLinks: const <String, String>{
          'twitter': 'https://twitter.com/acme',
          'github': 'https://github.com/acme',
        },
        maintenanceMode: true,
        maintenanceMessage: 'Back in 15 minutes!',
        updatedAt: DateTime.utc(2026, 10, 14, 12, 0, 0),
      );

      final Map<String, Object?> json = original.toJson();
      final DVStudioSettings parsed = DVStudioSettings.fromJson(json);

      expect(parsed.siteTitle, 'Acme Corp');
      expect(parsed.tagline, 'Leading widgets & tools');
      expect(parsed.siteUrl, 'https://acme.example.com');
      expect(parsed.timezone, 'America/New_York');
      expect(parsed.dateFormat, 'MM/DD/YYYY');
      expect(parsed.favicon, 'https://acme.example.com/icon.png');
      expect(parsed.defaultSeoTitle, 'Acme Corp — Quality Tools');
      expect(parsed.defaultSeoDescription, 'Build faster with Acme industrial tools.');
      expect(parsed.defaultSeoImage, 'https://acme.example.com/og.jpg');
      expect(parsed.socialLinks['twitter'], 'https://twitter.com/acme');
      expect(parsed.socialLinks['github'], 'https://github.com/acme');
      expect(parsed.maintenanceMode, isTrue);
      expect(parsed.maintenanceMessage, 'Back in 15 minutes!');
      expect(parsed.updatedAt, DateTime.utc(2026, 10, 14, 12, 0, 0));
    });

    // This used to require a title, a tagline, SEO copy and social links in
    // the defaults -- the framework's own ("My Dartvel App", Dartvel's GitHub
    // and X). A new project's settings carry nothing of anybody else's.
    test('default settings are neutral', () {
      final DVStudioSettings defaults = dvStudioDefaultSettings();
      expect(defaults.siteTitle, isEmpty);
      expect(defaults.tagline, isEmpty);
      expect(defaults.siteUrl, isEmpty);
      expect(defaults.timezone, 'UTC');
      expect(defaults.dateFormat, 'YYYY-MM-DD');
      expect(defaults.defaultSeoTitle, isNull);
      expect(defaults.defaultSeoDescription, isNull);
      expect(defaults.socialLinks, isEmpty);
      expect(defaults.maintenanceMode, isFalse);
      expect(defaults.maintenanceMessage, isNot(contains('Dartvel')));
    });

    test('settings that differ only in their social links are not equal', () {
      const DVStudioSettings plain = DVStudioSettings(siteTitle: 'Harbour');
      final DVStudioSettings linked = plain.copyWith(
        socialLinks: const <String, String>{'Mastodon': 'https://example.social/@harbour'},
      );
      expect(linked, isNot(plain));
      expect(
        linked,
        plain.copyWith(
          socialLinks: const <String, String>{'Mastodon': 'https://example.social/@harbour'},
        ),
      );
    });

    test('copyWith updates specified fields', () {
      final DVStudioSettings original = dvStudioDefaultSettings();
      final DVStudioSettings updated = original.copyWith(
        siteTitle: 'Updated Portal',
        maintenanceMode: true,
      );

      expect(updated.siteTitle, 'Updated Portal');
      expect(updated.maintenanceMode, isTrue);
      expect(updated.tagline, original.tagline);
      expect(updated.siteUrl, original.siteUrl);
    });
  });

  group('DVStudioApi settings endpoints', () {
    late MemoryDVDatabaseAdapter database;
    late DVStudioApi api;

    setUp(() {
      database = MemoryDVDatabaseAdapter();
      api = DVStudioApi(database: database);
    });

    test('GET api/settings returns default settings', () async {
      final Response response = await api.respond(
        _request('GET', 'api/settings'),
        'settings',
      );

      expect(response.status, 200);
      final Map<String, Object?> body = await _json(response);

      // Was 'My Dartvel App': the framework's name on every project.
      expect(body['siteTitle'], '');
      expect(body['timezone'], 'UTC');
      expect(body['maintenanceMode'], isFalse);
    });

    test('PUT api/settings requires CSRF token', () async {
      final Response response = await api.respond(
        _request(
          'PUT',
          'api/settings',
          body: const <String, Object?>{'siteTitle': 'Hacked'},
          csrf: false,
        ),
        'settings',
      );

      expect(response.status, 403);
    });

    test('PUT api/settings updates settings and persists them in the database', () async {
      final Response response = await api.respond(
        _request(
          'PUT',
          'api/settings',
          body: const <String, Object?>{
            'siteTitle': 'Production Service',
            'tagline': 'High availability apps',
            'siteUrl': 'https://prod.service.internal',
            'timezone': 'Europe/London',
            'dateFormat': 'DD/MM/YYYY',
            'favicon': 'https://prod.service.internal/favicon.ico',
            'defaultSeoTitle': 'Production Service Portal',
            'defaultSeoDescription': 'Global enterprise deployment portal.',
            'defaultSeoImage': 'https://prod.service.internal/banner.png',
            'socialLinks': <String, String>{
              'github': 'https://github.com/my-org/service',
            },
            'maintenanceMode': true,
            'maintenanceMessage': 'Routine scheduled upgrade underway.',
          },
        ),
        'settings',
      );

      expect(response.status, 200);
      final Map<String, Object?> body = await _json(response);

      expect(body['siteTitle'], 'Production Service');
      expect(body['timezone'], 'Europe/London');
      expect(body['dateFormat'], 'DD/MM/YYYY');
      expect(body['maintenanceMode'], isTrue);
      expect(body['maintenanceMessage'], 'Routine scheduled upgrade underway.');
      expect(body['updatedAt'], isNotNull);

      // Verify GET returns updated settings
      final Response getResponse = await api.respond(
        _request('GET', 'api/settings'),
        'settings',
      );
      final Map<String, Object?> getBody = await _json(getResponse);
      expect(getBody['siteTitle'], 'Production Service');
      expect(getBody['maintenanceMode'], isTrue);
    });

    test('PUT api/settings validates non-empty site title', () async {
      final Response response = await api.respond(
        _request(
          'PUT',
          'api/settings',
          body: const <String, Object?>{
            'siteTitle': '   ',
          },
        ),
        'settings',
      );

      expect(response.status, 400);
      final Map<String, Object?> body = await _json(response);
      expect(body['error'], 'invalid_settings');
      expect(body['message'], contains('Site title cannot be empty'));
    });

    test('PUT api/settings validates site URL scheme', () async {
      final Response response = await api.respond(
        _request(
          'PUT',
          'api/settings',
          body: const <String, Object?>{
            'siteTitle': 'Valid Title',
            'siteUrl': 'ftp://invalid-url.com',
          },
        ),
        'settings',
      );

      expect(response.status, 400);
      final Map<String, Object?> body = await _json(response);
      expect(body['error'], 'invalid_settings');
      expect(body['message'], contains('http:// or https://'));
    });

    test('settings update records activity note', () async {
      await api.respond(
        _request(
          'PUT',
          'api/settings',
          body: const <String, Object?>{
            'siteTitle': 'Logged Portal',
          },
        ),
        'settings',
      );

      final DVStudioOverview overview = await api.overview();
      expect(
        overview.recent.any(
          (DVStudioActivity item) =>
              item.screen == 'settings' &&
              item.label.contains('Updated global settings: Logged Portal'),
        ),
        isTrue,
      );
    });
  });

  group('DVStudioScreenSpec and documents for settings', () {
    test('dvStudioScreens includes settings screen spec', () {
      final DVStudioScreenSpec? spec =
          dvStudioScreens.where((s) => s.id == 'settings').firstOrNull;
      expect(spec, isNotNull);
      expect(spec!.label, 'Settings');
      expect(spec.path('/__studio'), '/__studio/settings');
    });

    test('dvStudioScreenAliases maps general and config to settings', () {
      expect(dvStudioScreenAliases['general'], 'settings');
      expect(dvStudioScreenAliases['config'], 'settings');
      expect(dvStudioScreenFor('general')?.id, 'settings');
      expect(dvStudioScreenFor('config')?.id, 'settings');
    });

    test('dvStudioDocumentFor renders settings document', () {
      final DVStudioTarget? target =
          dvStudioTargetFor('/__studio/settings', mount: '/__studio');
      expect(target, isNotNull);

      final DVStudioDocument doc = dvStudioDocumentFor(
        target!,
        mount: '/__studio',
        data: const DVStudioProjectData(),
      );

      expect(doc.heading, 'Settings');
      expect(doc.html, contains('site title, tagline'));
      expect(doc.text.any((t) => t.contains('maintenance mode')), isTrue);
    });
  });
}
