// A form placed on a page in Studio is drawn on the published page and a
// visitor's answer reaches the form's inbox. The page builder's form node
// drew nothing at all on a page, and the widget it had never sent anything.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart' as core
    show
        DVPublishedPages,
        DVStudioApi,
        DVStudioForm,
        Headers,
        MemoryDVDatabaseAdapter,
        Request;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _key(String key) => find.byKey(ValueKey<String>(key));

/// Lets the in-memory server answer: its replies are real futures, which a
/// widget test's clock does not move on its own.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late core.MemoryDVDatabaseAdapter database;
  late DVStudioClient studio;
  late DVStudioTransport site;

  setUp(() async {
    database = core.MemoryDVDatabaseAdapter();
    studio = DVStudioClient(
        dvStudioInProcessTransport(core.DVStudioApi(database: database)));
    final core.DVPublishedPages pages =
        core.DVPublishedPages(database: () => database);
    // The site's own server, as a browser on the page reaches it.
    site = (String method, String path, {Object? body}) async {
      final response = (await pages.respond(core.Request(
        method: method,
        url: Uri.parse('http://harbour.example$path'),
        headers: core.Headers(<String, String>{
          if (body != null) 'content-type': 'application/json',
        }),
        bodyStream: body == null
            ? const Stream<List<int>>.empty()
            : Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
      )))!;
      final String text = utf8.decode(await response.body!.bytes());
      return DVStudioReply(response.status, text.isEmpty ? null : jsonDecode(text));
    };
  });

  Future<void> makeForm() => studio.saveForm(core.DVStudioForm.fromJson(<String, Object?>{
        'id': 'enquiry',
        'name': 'Enquiry',
        'submitLabel': 'Send',
        'successMessage': 'Thanks, we will write back.',
        'fields': <Object?>[
          <String, Object?>{'id': 'email', 'label': 'Email', 'type': 'email', 'required': true},
        ],
      }));

  testWidgets('a visitor fills in the form, and the answer is kept',
      (WidgetTester tester) async {
    await tester.runAsync(makeForm);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DVStudioPublishedForm(formId: 'enquiry', transport: site),
      ),
    ));
    await _settle(tester);
    expect(find.text('Email *'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).first, 'sam@example.com');
    await tester.tap(find.text('Send'));
    await _settle(tester);
    expect(find.textContaining('Thanks, we will write back.'), findsOneWidget);

    final submissions =
        (await tester.runAsync(() => studio.submissions()))!.submissions;
    expect(submissions.single.data['email'], 'sam@example.com');
  });

  testWidgets('a form that cannot be read says so', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DVStudioPublishedForm(formId: 'missing', transport: site),
      ),
    ));
    await _settle(tester);
    expect(_key('dv-studio-form-unavailable'), findsOneWidget);
  });

  test('a form on a page is drawn by the published form', () {
    final DVStudioLeafType leaf = dvStudioLeafTypes
        .firstWhere((DVStudioLeafType t) => t.type == 'form');
    final Widget built = leaf.build(DVPageNode.form(formId: 'enquiry'));
    expect(built, isA<DVStudioPublishedForm>());
    expect((built as DVStudioPublishedForm).formId, 'enquiry');
  });
}
