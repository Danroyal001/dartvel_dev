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
  group('DVStudioFormField, DVStudioForm & DVStudioFormSubmission models', () {
    test('serializes and deserializes form and field cleanly', () {
      const DVStudioFormField field = DVStudioFormField(
        id: 'phone',
        label: 'Phone Number',
        type: 'phone',
        placeholder: '+1 555-0100',
        required: true,
      );

      final Map<String, Object?> fieldJson = field.toJson();
      expect(fieldJson['id'], 'phone');
      expect(fieldJson['label'], 'Phone Number');
      expect(fieldJson['type'], 'phone');
      expect(fieldJson['required'], true);

      final DVStudioFormField restoredField =
          DVStudioFormField.fromJson(fieldJson);
      expect(restoredField.id, 'phone');
      expect(restoredField.placeholder, '+1 555-0100');

      final DVStudioForm form = DVStudioForm(
        id: 'quote-request',
        name: 'Quote Request',
        description: 'Request a custom project quote',
        submitLabel: 'Get Quote',
        successMessage: 'We will be in touch shortly!',
        targetEmail: 'sales@example.com',
        targetModel: 'Lead',
        fields: <DVStudioFormField>[field],
        submissionsCount: 3,
        updatedAt: DateTime.parse('2026-10-14T12:00:00Z'),
      );

      final Map<String, Object?> formJson = form.toJson();
      expect(formJson['id'], 'quote-request');
      expect(formJson['name'], 'Quote Request');
      expect(formJson['targetEmail'], 'sales@example.com');
      expect(formJson['submissionsCount'], 3);
      expect((formJson['fields'] as List).length, 1);

      final DVStudioForm restoredForm = DVStudioForm.fromJson(formJson);
      expect(restoredForm.id, 'quote-request');
      expect(restoredForm.submitLabel, 'Get Quote');
      expect(restoredForm.fields.first.id, 'phone');
      expect(restoredForm.submissionsCount, 3);
    });

    test('serializes and deserializes form submission cleanly', () {
      final DVStudioFormSubmission sub = DVStudioFormSubmission(
        id: 'sub-1001',
        formId: 'contact',
        data: const <String, Object?>{
          'name': 'Alice Smith',
          'email': 'alice@example.com',
          'message': 'Hello team!',
        },
        status: 'unread',
        submittedAt: DateTime.parse('2026-10-14T12:30:00Z'),
        ipAddress: '192.168.1.1',
        userAgent: 'DartvelBrowser/1.0',
      );

      final Map<String, Object?> json = sub.toJson();
      expect(json['id'], 'sub-1001');
      expect(json['formId'], 'contact');
      expect(json['status'], 'unread');
      expect((json['data'] as Map)['name'], 'Alice Smith');

      final DVStudioFormSubmission restored =
          DVStudioFormSubmission.fromJson(json);
      expect(restored.id, 'sub-1001');
      expect(restored.data['email'], 'alice@example.com');
      expect(restored.ipAddress, '192.168.1.1');
    });

    test('default forms provide contact and newsletter forms', () {
      final List<DVStudioForm> defaults = dvStudioDefaultForms();
      expect(defaults.length, greaterThanOrEqualTo(2));
      final DVStudioForm contact =
          defaults.firstWhere((DVStudioForm f) => f.id == 'contact');
      expect(contact.name, 'Contact Form');
      expect(contact.fields, isNotEmpty);
      expect(contact.fields.any((DVStudioFormField f) => f.id == 'email'), isTrue);

      final DVStudioForm newsletter =
          defaults.firstWhere((DVStudioForm f) => f.id == 'newsletter');
      expect(newsletter.name, 'Newsletter Signup');
      expect(newsletter.fields.first.id, 'email');
    });
  });

  group('DVStudioApi forms CRUD endpoints', () {
    late MemoryDVDatabaseAdapter database;
    late DVStudioApi api;

    setUp(() {
      database = MemoryDVDatabaseAdapter();
      api = DVStudioApi(database: database);
    });

    test('GET api/forms returns default forms', () async {
      final Response response =
          await api.respond(_request('GET', 'api/forms'), 'forms');
      expect(response.status, 200);
      final Map<String, Object?> body = await _json(response);
      expect(body['forms'], isA<List>());
      final List<Object?> forms = body['forms']! as List;
      expect(forms.length, greaterThanOrEqualTo(2));
    });

    test('GET api/forms with id returns single form', () async {
      final Response response = await api.respond(
        _request('GET', 'api/forms?id=contact'),
        'forms',
      );
      expect(response.status, 200);
      final Map<String, Object?> body = await _json(response);
      expect(body['id'], 'contact');
      expect(body['name'], 'Contact Form');
      expect(body['fields'], isA<List>());
    });

    test('GET api/forms with path id returns single form', () async {
      final Response response = await api.respond(
        _request('GET', 'api/forms/contact'),
        'forms/contact',
      );
      expect(response.status, 200);
      final Map<String, Object?> body = await _json(response);
      expect(body['id'], 'contact');
    });

    test('POST api/forms creates and persists a new form', () async {
      final Response response = await api.respond(
        _request('POST', 'api/forms', body: <String, Object?>{
          'id': 'feedback',
          'name': 'Feedback Survey',
          'description': 'Tell us what you think',
          'submitLabel': 'Send Feedback',
          'fields': <Map<String, Object?>>[
            <String, Object?>{
              'id': 'rating',
              'label': 'Rating',
              'type': 'number',
              'required': true,
            },
            <String, Object?>{
              'id': 'comments',
              'label': 'Comments',
              'type': 'textarea',
              'required': false,
            },
          ],
        }),
        'forms',
      );
      expect(response.status, 200);
      final Map<String, Object?> body = await _json(response);
      expect(body['id'], 'feedback');
      expect(body['name'], 'Feedback Survey');

      final Response getResponse = await api.respond(
        _request('GET', 'api/forms/feedback'),
        'forms/feedback',
      );
      expect(getResponse.status, 200);
      final Map<String, Object?> getBody = await _json(getResponse);
      expect(getBody['id'], 'feedback');
      expect((getBody['fields'] as List).length, 2);
    });

    test('DELETE api/forms deletes form and cascades submissions', () async {
      final Response deleteResponse = await api.respond(
        _request('DELETE', 'api/forms/contact'),
        'forms/contact',
      );
      expect(deleteResponse.status, 200);
      final Map<String, Object?> body = await _json(deleteResponse);
      expect(body['ok'], true);
      expect(body['deleted'], 'contact');

      final Response getResponse = await api.respond(
        _request('GET', 'api/forms/contact'),
        'forms/contact',
      );
      expect(getResponse.status, 404);
    });
  });

  group('DVStudioApi submissions and public submit endpoints', () {
    late MemoryDVDatabaseAdapter database;
    late DVStudioApi api;

    setUp(() {
      database = MemoryDVDatabaseAdapter();
      api = DVStudioApi(database: database);
    });

    test('POST api/forms/submit without CSRF token successfully accepts submission', () async {
      final Response response = await api.respond(
        _request(
          'POST',
          'api/forms/submit',
          csrf: false, // Public submissions do NOT require CSRF token
          body: <String, Object?>{
            'formId': 'contact',
            'data': <String, Object?>{
              'name': 'Test User',
              'email': 'user@example.com',
              'message': 'Inquiring about Dartvel services.',
            },
          },
        ),
        'forms/submit',
      );
      expect(response.status, 201);
      final Map<String, Object?> body = await _json(response);
      expect(body['ok'], true);
      expect(body['submissionId'], isNotNull);
      expect(body['message'], contains('Thank you!'));

      // Check that submissionsCount on form was incremented
      final Response formResponse = await api.respond(
        _request('GET', 'api/forms/contact'),
        'forms/contact',
      );
      final Map<String, Object?> formBody = await _json(formResponse);
      expect(formBody['submissionsCount'], 1);
    });

    test('POST api/forms/:id/submit validates required fields', () async {
      final Response response = await api.respond(
        _request(
          'POST',
          'api/forms/contact/submit',
          csrf: false,
          body: <String, Object?>{
            'data': <String, Object?>{
              'name': 'Test User',
              // missing required 'email' and 'message'
            },
          },
        ),
        'forms/contact/submit',
      );
      expect(response.status, 400);
      final Map<String, Object?> body = await _json(response);
      expect(body['error'], 'validation_error');
      expect(body['message'], contains('required'));
    });

    test('POST api/forms/:id/submit validates email format', () async {
      final Response response = await api.respond(
        _request(
          'POST',
          'api/forms/contact/submit',
          csrf: false,
          body: <String, Object?>{
            'data': <String, Object?>{
              'name': 'Test User',
              'email': 'not-an-email',
              'message': 'Hello world',
            },
          },
        ),
        'forms/contact/submit',
      );
      expect(response.status, 400);
      final Map<String, Object?> body = await _json(response);
      expect(body['error'], 'validation_error');
      expect(body['message'], contains('Invalid email address'));
    });

    test('GET api/forms/submissions lists submissions and handles status filtering and search', () async {
      // Create two submissions
      await api.respond(
        _request(
          'POST',
          'api/forms/submit',
          csrf: false,
          body: <String, Object?>{
            'formId': 'contact',
            'data': <String, Object?>{
              'name': 'Bob Dylan',
              'email': 'bob@example.com',
              'message': 'Blowing in the wind',
            },
          },
        ),
        'forms/submit',
      );

      await api.respond(
        _request(
          'POST',
          'api/forms/submit',
          csrf: false,
          body: <String, Object?>{
            'formId': 'newsletter',
            'data': <String, Object?>{
              'email': 'subscriber@company.org',
            },
          },
        ),
        'forms/submit',
      );

      // Query all submissions
      final Response listAll = await api.respond(
        _request('GET', 'api/forms/submissions'),
        'forms/submissions',
      );
      expect(listAll.status, 200);
      final Map<String, Object?> allBody = await _json(listAll);
      expect(allBody['total'], 2);
      expect(allBody['unread'], 2);
      final List<Object?> subs = allBody['submissions']! as List;
      expect(subs.length, 2);

      // Filter by formId
      final Response filterForm = await api.respond(
        _request('GET', 'api/forms/submissions?formId=newsletter'),
        'forms/submissions',
      );
      final Map<String, Object?> filterFormBody = await _json(filterForm);
      expect(filterFormBody['total'], 1);

      // Search query
      final Response searchRes = await api.respond(
        _request('GET', 'api/forms/submissions?q=dylan'),
        'forms/submissions',
      );
      final Map<String, Object?> searchBody = await _json(searchRes);
      expect(searchBody['total'], 1);
      final Map<String, Object?> foundSub =
          (searchBody['submissions']! as List).first as Map<String, Object?>;
      final String subId = foundSub['id'] as String;

      // Update status to read
      final Response patchRes = await api.respond(
        _request('PATCH', 'api/forms/submissions', body: <String, Object?>{
          'id': subId,
          'status': 'read',
        }),
        'forms/submissions',
      );
      expect(patchRes.status, 200);

      // Check unread count
      final Response recheck = await api.respond(
        _request('GET', 'api/forms/submissions'),
        'forms/submissions',
      );
      final Map<String, Object?> recheckBody = await _json(recheck);
      expect(recheckBody['unread'], 1);

      // Delete submission
      final Response deleteSub = await api.respond(
        _request('DELETE', 'api/forms/submissions?id=$subId'),
        'forms/submissions',
      );
      expect(deleteSub.status, 200);

      final Response afterDelete = await api.respond(
        _request('GET', 'api/forms/submissions'),
        'forms/submissions',
      );
      final Map<String, Object?> afterDeleteBody = await _json(afterDelete);
      expect(afterDeleteBody['total'], 1);
    });
  });
}
