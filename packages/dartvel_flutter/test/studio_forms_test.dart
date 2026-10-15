import 'package:dartvel_core/dartvel.dart'
    show DVStudioForm, DVStudioFormField, DVStudioFormSubmission;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFormsTransport {
  _FakeFormsTransport() {
    forms = <DVStudioForm>[
      DVStudioForm(
        id: 'contact',
        name: 'Contact Form',
        description: 'Collect inquiries and messages from visitors',
        submitLabel: 'Send Message',
        successMessage: 'Thank you! Your message has been sent.',
        submissionsCount: 1,
        fields: const <DVStudioFormField>[
          DVStudioFormField(
            id: 'name',
            label: 'Your Name',
            type: 'text',
            placeholder: 'Jane Doe',
            required: true,
          ),
          DVStudioFormField(
            id: 'email',
            label: 'Email Address',
            type: 'email',
            placeholder: 'jane@example.com',
            required: true,
          ),
          DVStudioFormField(
            id: 'message',
            label: 'Message',
            type: 'textarea',
            placeholder: 'How can we help?',
            required: true,
          ),
        ],
        updatedAt: DateTime.now().toUtc(),
      ),
      DVStudioForm(
        id: 'newsletter',
        name: 'Newsletter Signup',
        description: 'Subscribe to our product updates',
        submitLabel: 'Subscribe',
        successMessage: 'Thanks for subscribing!',
        submissionsCount: 0,
        fields: const <DVStudioFormField>[
          DVStudioFormField(
            id: 'email',
            label: 'Email Address',
            type: 'email',
            placeholder: 'you@domain.com',
            required: true,
          ),
        ],
        updatedAt: DateTime.now().toUtc(),
      ),
    ];

    submissions = <DVStudioFormSubmission>[
      DVStudioFormSubmission(
        id: 'sub-1',
        formId: 'contact',
        data: const <String, Object?>{
          'name': 'Alex Rivers',
          'email': 'alex@example.com',
          'message': 'Looking for enterprise pricing details.',
        },
        status: 'unread',
        submittedAt: DateTime.now().toUtc(),
        ipAddress: '127.0.0.1',
        userAgent: 'DartvelBrowser/1.0',
      ),
    ];
  }

  late List<DVStudioForm> forms;
  late List<DVStudioFormSubmission> submissions;
  DVStudioForm? lastSavedForm;
  String? lastDeletedFormId;
  String? lastUpdatedSubmissionId;
  String? lastUpdatedSubmissionStatus;
  String? lastDeletedSubmissionId;

  Future<DVStudioReply> call(String method, String path, {Object? body}) async {
    final Uri uri = Uri.parse(path);

    if (uri.path == 'api/forms') {
      if (method == 'GET') {
        final String? id = uri.queryParameters['id'];
        if (id != null) {
          final DVStudioForm? found =
              forms.where((DVStudioForm f) => f.id == id).firstOrNull;
          if (found == null) {
            return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
          }
          return DVStudioReply(200, found.toJson());
        }
        return DVStudioReply(200, <String, Object?>{
          'forms': <Object?>[for (final DVStudioForm f in forms) f.toJson()],
        });
      }
      if (method == 'POST') {
        final Map<String, Object?> json = (body as Map).cast<String, Object?>();
        final DVStudioForm form = DVStudioForm.fromJson(json);
        final int index = forms.indexWhere((DVStudioForm f) => f.id == form.id);
        if (index >= 0) {
          forms[index] = form;
        } else {
          forms.add(form);
        }
        lastSavedForm = form;
        return DVStudioReply(200, form.toJson());
      }
      if (method == 'DELETE') {
        final String? id = uri.queryParameters['id'];
        if (id != null) {
          forms.removeWhere((DVStudioForm f) => f.id == id);
          lastDeletedFormId = id;
          return const DVStudioReply(200, <String, Object?>{'ok': true});
        }
      }
    }

    if (uri.path == 'api/forms/submissions') {
      if (method == 'GET') {
        List<DVStudioFormSubmission> list = List<DVStudioFormSubmission>.from(submissions);
        final String? formId = uri.queryParameters['formId'];
        if (formId != null && formId.isNotEmpty && formId != 'all') {
          list = list.where((s) => s.formId == formId).toList();
        }
        final String? status = uri.queryParameters['status'];
        if (status != null && status.isNotEmpty && status != 'all') {
          list = list.where((s) => s.status == status).toList();
        }
        final String? q = uri.queryParameters['q'];
        if (q != null && q.isNotEmpty) {
          final String query = q.toLowerCase();
          list = list.where((s) {
            return s.id.toLowerCase().contains(query) ||
                s.data.values.any((v) => '$v'.toLowerCase().contains(query));
          }).toList();
        }
        final int unread = list.where((s) => s.status == 'unread').length;
        return DVStudioReply(200, <String, Object?>{
          'submissions': <Object?>[for (final s in list) s.toJson()],
          'total': list.length,
          'unread': unread,
        });
      }
      if (method == 'PATCH') {
        final Map<String, Object?> json = (body as Map).cast<String, Object?>();
        final String id = '${json['id']}';
        final String status = '${json['status']}';
        final int index = submissions.indexWhere((s) => s.id == id);
        if (index >= 0) {
          submissions[index] = submissions[index].copyWith(status: status);
          lastUpdatedSubmissionId = id;
          lastUpdatedSubmissionStatus = status;
          return DVStudioReply(200, <String, Object?>{
            'ok': true,
            'submission': submissions[index].toJson(),
          });
        }
      }
      if (method == 'DELETE') {
        final String? id = uri.queryParameters['id'];
        if (id != null) {
          submissions.removeWhere((s) => s.id == id);
          lastDeletedSubmissionId = id;
          return const DVStudioReply(200, <String, Object?>{'ok': true});
        }
      }
    }

    if (uri.path == 'api/forms/submit') {
      return const DVStudioReply(201, <String, Object?>{
        'ok': true,
        'submissionId': 'sub-fake-123',
        'message': 'Thank you! Your submission has been received.',
      });
    }

    return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
  }
}

void main() {
  setUp(() {
    DVStudioStyle.dark = false;
  });

  Future<void> pumpFormsSection(
    WidgetTester tester, {
    required DVStudioClient client,
    String? selectedFormId,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DVStudioFormsSection(
            client: client,
            selectedFormId: selectedFormId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders forms section with sidebar, settings, fields list, and live preview', (
    WidgetTester tester,
  ) async {
    final _FakeFormsTransport transport = _FakeFormsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpFormsSection(tester, client: client);

    expect(find.text('Forms'), findsWidgets);
    expect(find.text('Submissions Inbox'), findsOneWidget);
    expect(find.text('Contact Form'), findsWidgets);
    expect(find.text('Newsletter Signup'), findsOneWidget);
    expect(find.text('Form Settings'), findsOneWidget);
    expect(find.text('Fields (3)'), findsOneWidget);
    expect(find.text('Live Preview'), findsOneWidget);
    expect(find.text('New Form'), findsOneWidget);
    expect(find.text('Add Field'), findsOneWidget);
    expect(find.text('Embed snippet'), findsOneWidget);
  });

  testWidgets('new form dialog creates and saves a new form', (
    WidgetTester tester,
  ) async {
    final _FakeFormsTransport transport = _FakeFormsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpFormsSection(tester, client: client);

    await tester.tap(find.text('New Form'));
    await tester.pumpAndSettle();

    expect(find.text('Create New Form'), findsOneWidget);

    // Enter name
    final Finder newFormInputs = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(EditableText),
    );
    await tester.enterText(newFormInputs.first, 'Job Application');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create Form'));
    await tester.pumpAndSettle();

    expect(transport.lastSavedForm, isNotNull);
    expect(transport.lastSavedForm!.name, 'Job Application');
    expect(find.text('Job Application'), findsWidgets);
  });

  testWidgets('add field dialog adds a new field and enables Save Changes', (
    WidgetTester tester,
  ) async {
    final _FakeFormsTransport transport = _FakeFormsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpFormsSection(tester, client: client);

    await tester.tap(find.text('Add Field'));
    await tester.pumpAndSettle();

    expect(find.text('Add Form Field'), findsOneWidget);

    // Enter label
    final Finder addFieldInputs = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(EditableText),
    );
    await tester.enterText(addFieldInputs.first, 'Phone Number');
    await tester.pumpAndSettle();

    final Finder dialogAddFieldBtn = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Add Field'),
    );
    await tester.tap(dialogAddFieldBtn);
    await tester.pumpAndSettle();

    expect(find.text('Phone Number'), findsWidgets);
    expect(find.text('Save Changes'), findsOneWidget);

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(transport.lastSavedForm, isNotNull);
    expect(
        transport.lastSavedForm!.fields
            .any((DVStudioFormField f) => f.label == 'Phone Number'),
        isTrue);
  });

  testWidgets('submissions inbox lists submissions, filters, and toggles status', (
    WidgetTester tester,
  ) async {
    final _FakeFormsTransport transport = _FakeFormsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpFormsSection(tester, client: client);

    // Switch to Submissions Inbox tab
    await tester.tap(find.text('Submissions Inbox'));
    await tester.pumpAndSettle();

    expect(find.text('1 total (1 unread)'), findsOneWidget);
    expect(find.textContaining('Alex Rivers'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.text('Export JSON'), findsOneWidget);

    // Mark as read
    final Finder readButtons = find.byTooltip('Mark as read');
    expect(readButtons, findsOneWidget);

    await tester.tap(readButtons);
    await tester.pumpAndSettle();

    expect(transport.lastUpdatedSubmissionId, 'sub-1');
    expect(transport.lastUpdatedSubmissionStatus, 'read');
  });

  testWidgets('submission detail dialog opens with metadata and submitted fields', (
    WidgetTester tester,
  ) async {
    final _FakeFormsTransport transport = _FakeFormsTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpFormsSection(tester, client: client);

    await tester.tap(find.text('Submissions Inbox'));
    await tester.pumpAndSettle();

    // Tap view details icon
    final Finder viewButtons = find.byTooltip('View details');
    await tester.tap(viewButtons);
    await tester.pumpAndSettle();

    expect(find.text('Submission sub-1'), findsOneWidget);
    expect(find.text('Submitted Field Data'), findsOneWidget);
    expect(find.text('Looking for enterprise pricing details.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('DVStudioFormWidget renders fields, validates inputs, and submits successfully', (
    WidgetTester tester,
  ) async {
    Map<String, Object?>? submittedData;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            // The form is passed in. This test used to pass none and lean on
            // a contact form the widget drew by itself, which was the defect:
            // the widget renders the project's form or none.
            child: DVStudioFormWidget(
              formId: 'contact',
              form: DVStudioForm(
                id: 'contact',
                name: 'Enquiry',
                updatedAt: DateTime.utc(2026),
                fields: const <DVStudioFormField>[
                  DVStudioFormField(
                      id: 'name', label: 'Full Name', type: 'text', required: true),
                  DVStudioFormField(
                      id: 'email', label: 'Email Address', type: 'email', required: true),
                  DVStudioFormField(
                      id: 'message', label: 'Message', type: 'textarea', required: true),
                ],
              ),
              onSubmit: (Map<String, Object?> data) async {
                submittedData = data;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Full Name *'), findsOneWidget);
    expect(find.text('Email Address *'), findsOneWidget);
    expect(find.text('Message *'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);

    // Tap submit with empty inputs -> validation error
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Please complete the "Full Name" field'), findsOneWidget);

    // Fill inputs
    final Finder textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'Grace Hopper');
    await tester.enterText(textFields.at(1), 'grace@navy.mil');
    await tester.enterText(textFields.at(2), 'Compiler pioneer message');
    await tester.pumpAndSettle();

    // Tap submit
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(submittedData, isNotNull);
    expect(submittedData!['name'], 'Grace Hopper');
    expect(submittedData!['email'], 'grace@navy.mil');
    expect(find.text('Thank you! Your submission has been received.'), findsOneWidget);
    expect(find.text('Submit another response'), findsOneWidget);
  });

  testWidgets('DVStudioFormWidget with no form draws no form of its own', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DVStudioFormWidget(formId: 'enquiry')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Submit'), findsNothing);
    expect(find.textContaining('enquiry'), findsOneWidget);
  });

  testWidgets('a failed load is shown as an error with Try again, not as '
      'sample forms', (WidgetTester tester) async {
    int calls = 0;
    final _FakeFormsTransport transport = _FakeFormsTransport();
    Future<DVStudioReply> failingOnce(String method, String path,
        {Object? body}) async {
      if (Uri.parse(path).path == 'api/forms' && method == 'GET' && calls++ == 0) {
        return const DVStudioReply(500, <String, Object?>{
          'error': 'server_error',
          'message': 'Studio could not do this. The server\'s log says why.',
        });
      }
      return transport.call(method, path, body: body);
    }

    await pumpFormsSection(tester, client: DVStudioClient(failingOnce));

    expect(find.text('The forms could not be loaded'), findsOneWidget);
    expect(find.text('Contact Form'), findsNothing);
    expect(find.text('Newsletter Signup'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('The forms could not be loaded'), findsNothing);
    expect(find.text('Contact Form'), findsWidgets);
  });

  testWidgets('a project with no forms is invited to make one', (
    WidgetTester tester,
  ) async {
    final _FakeFormsTransport transport = _FakeFormsTransport()
      ..forms = <DVStudioForm>[];

    await pumpFormsSection(tester, client: DVStudioClient(transport.call));

    expect(find.text('No forms yet'), findsOneWidget);
    expect(find.text('New form'), findsOneWidget);
    expect(find.text('Contact Form'), findsNothing);
  });
}
