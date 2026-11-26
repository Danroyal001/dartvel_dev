// SSR-first fields at the handover when the app builds its form after its
// first frame, in a browser: the server-rendered page's head script, a real
// document field, then the app.
//
// eatingtoday, elena, wahala, tori and Cloud (Dartvel 3.47.11): the sign-in
// form appears once the session check says nobody is signed in, a few
// frames after the app's first frame. At that frame there was no app field
// to carry into, and what the visitor had typed into the document was lost
// at the handover. The handover now waits for the app's field (the document
// stays the page and keeps taking typing), then carries the text, caret and
// focus; it never waits longer than dvSsrFieldHold.
//
// Its own file, so it starts in a page of its own: the engine's and the
// framework's focus state from another test's handover would decide the
// outcome otherwise.
//
// Run with: flutter test --platform chrome test/ssr_fields_late_browser_test.dart
@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:dartvel_core/src/web/ssr_first.dart' show dvSsrFirstHead;
import 'package:dartvel_flutter/src/seo/ssr_fields_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

/// The SSR-first head's scripts, run as the page runs them.
void _installHead() {
  final String head = dvSsrFirstHead(background: '#ffffff', darkBackground: '#000000', accent: '#0055ff');
  for (final RegExpMatch script in RegExp(r'<script>(.*?)</script>', dotAll: true).allMatches(head)) {
    final web.HTMLScriptElement element = web.document.createElement('script') as web.HTMLScriptElement
      ..text = script.group(1)!;
    web.document.head!.append(element);
  }
}

/// A server-rendered document with one field.
web.Element _document() {
  final web.Element fallback = web.document.createElement('div')
    ..className = 'dv-fallback'
    ..innerHTML =
        ('<p><label for="dv-field-1">Your content</label> '
                '<textarea id="dv-field-1" name="Your content" data-dv-field="Your content"></textarea></p>')
            .toJS;
  web.document.body!.append(fallback);
  return fallback;
}

void _type(web.HTMLTextAreaElement field, String value) {
  field
    ..value = value
    ..setSelectionRange(value.length, value.length);
  field.dispatchEvent(web.InputEvent('input'));
}

void main() {
  setUpAll(_installHead);
  setUp(
    () => web.document.documentElement!
      ..removeAttribute('data-dv-app')
      ..removeAttribute('data-dv-carried'),
  );
  final TestExceptionReporter report = reportTestException;
  reportTestException = (FlutterErrorDetails details, String description) {
    // ignore: avoid_print
    print('FAILED: ${details.exceptionAsString()}');
    report(details, description);
  };

  // eatingtoday, elena, wahala, tori, Cloud (Dartvel 3.47.11): the sign-in
  // form is built after the app's first frame (once the session check says
  // nobody is signed in), so at the first frame there was no app field to
  // carry into and what the visitor typed was lost. The handover waits for
  // the app's field: the document stays the page, the visitor keeps typing,
  // and the text, caret and focus go over once the field is there.
  testWidgets('a field the app builds a few frames after its first frame still gets what was typed', (
    WidgetTester tester,
  ) async {
    final web.Element fallback = _document();
    addTearDown(() => fallback.remove());
    final web.HTMLTextAreaElement field = web.document.querySelector('#dv-field-1')! as web.HTMLTextAreaElement;
    field.focus();
    _type(field, 'hello wor');
    final TextEditingController content = TextEditingController();
    final FocusNode focus = FocusNode();
    final ValueNotifier<bool> signedOut = ValueNotifier<bool>(false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: signedOut,
            builder: (BuildContext context, bool showForm, Widget? _) => showForm
                ? Semantics(
                    label: 'Your content',
                    child: TextField(controller: content, focusNode: focus, maxLines: null),
                  )
                : const Text('Checking your session'),
          ),
        ),
      ),
    );

    bool handed = false;
    unawaited(dvHandOverSsrFields().then((_) => handed = true));
    await tester.pump(const Duration(milliseconds: 100));
    expect(handed, isFalse, reason: 'the document stays the page until the field is there');
    expect(web.document.activeElement, field);
    // Still typing in the document while the app checks the session.
    _type(field, 'hello world');
    signedOut.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(handed, isTrue, reason: 'handed once the field is there');
    expect(content.text, 'hello world');
    expect(content.selection, const TextSelection.collapsed(offset: 11));
    await tester.pump();
    expect(focus.hasFocus, isTrue, reason: 'the app field has the keyboard');
  });

  testWidgets('a field that never comes does not hold the page for ever', (WidgetTester tester) async {
    final web.Element fallback = _document();
    addTearDown(() => fallback.remove());
    final web.HTMLTextAreaElement field = web.document.querySelector('#dv-field-1')! as web.HTMLTextAreaElement;
    field.focus();
    _type(field, 'hello');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Welcome back'))));
    bool handed = false;
    unawaited(dvHandOverSsrFields().then((_) => handed = true));
    await tester.pump(const Duration(seconds: 1));
    expect(handed, isFalse);
    await tester.pump(dvSsrFieldHold);
    expect(handed, isTrue, reason: 'after the hold the app takes the page anyway');
  });

  testWidgets('nothing typed, nothing held', (WidgetTester tester) async {
    final web.Element fallback = _document();
    addTearDown(() => fallback.remove());
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Checking your session'))));
    bool handed = false;
    unawaited(dvHandOverSsrFields().then((_) => handed = true));
    await tester.pump();
    expect(handed, isTrue);
  });
}
