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
import 'dart:js_interop_unsafe';

import 'package:dartvel_core/src/web/ssr_first.dart' show dvSsrFirstHead;
import 'package:dartvel_flutter/src/seo/ssr_fields_web.dart';
import 'package:dartvel_flutter/src/widgets/password_reveal.dart' show dvTakeOverServerField;
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

  // eatingtoday (Dartvel 3.47.11): the sign-in page's fields read the
  // server-rendered field in initState (dvTakeOverServerField, from before
  // SSR-first), which emptied the document's input while the visitor was
  // still typing in it, and the form built again after the session check
  // found it taken: the text was in neither field at the handover. While the
  // document is the page, its fields are left to the handover; a field the
  // handover carried is emptied and marked taken then, so a form built later
  // does not take it a second time.
  testWidgets('a field that reads the server-rendered field while the document is the page leaves it to the handover',
      (WidgetTester tester) async {
    final web.Element marker = web.document.createElement('style')..id = 'dartvel-ssr-first';
    web.document.head!.append(marker);
    addTearDown(() => marker.remove());
    final web.Element fallback = web.document.createElement('div')
      ..className = 'dv-fallback'
      ..innerHTML = '<p><label for="dv-field-2">Email</label> <input id="dv-field-2" name="Email" data-dv-field="Email"></p>'.toJS;
    web.document.body!.append(fallback);
    addTearDown(() => fallback.remove());
    final web.HTMLInputElement field = web.document.querySelector('#dv-field-2')! as web.HTMLInputElement;
    field
      ..focus()
      ..value = 'hello wor';
    field.dispatchEvent(web.InputEvent('input'));

    final TextEditingController early = TextEditingController();
    dvTakeOverServerField('Email', early);
    expect(early.text, isEmpty, reason: 'the document is still the page');
    expect(field.value, 'hello wor', reason: 'nothing is taken out from under the visitor');

    final TextEditingController content = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Semantics(label: 'Email', child: TextField(controller: content)),
      ),
    ));
    await dvHandOverSsrFields();
    expect(content.text, 'hello wor');
    field.blur();
    expect(field.value, isEmpty, reason: 'carried, then emptied: what was typed is not left lying in the page');
    web.document.documentElement!.setAttribute('data-dv-app', '');
    addTearDown(() => web.document.documentElement!.removeAttribute('data-dv-app'));
    final TextEditingController later = TextEditingController();
    dvTakeOverServerField('Email', later);
    expect(later.text, isEmpty, reason: 'a form built later does not take it again');
  });

  // ChopDesk's sign-in (3.47.12 check): at the app's first frame the engine
  // focused a node of the app's semantics tree (the route's focus scope),
  // behind the document, and the field being typed in lost the keyboard
  // until the handover: keys typed meanwhile went nowhere.
  test('the app focusing its own semantics behind the document does not take the keyboard', () {
    final web.Element fallback = _document();
    addTearDown(() => fallback.remove());
    final web.Element host = web.document.createElement('flt-semantics-host')
      ..innerHTML = '<flt-semantics tabindex="-1" role="group"></flt-semantics>'.toJS;
    web.document.body!.append(host);
    addTearDown(() => host.remove());
    final web.HTMLTextAreaElement field = web.document.querySelector('#dv-field-1')! as web.HTMLTextAreaElement;
    field.focus();
    (host.firstElementChild! as web.HTMLElement).focus();
    expect(web.document.activeElement, field);

    // Once the app has carried the fields it moves the keyboard itself.
    web.document.documentElement!.setAttribute('data-dv-carried', '');
    (host.firstElementChild! as web.HTMLElement).focus();
    expect(web.document.activeElement, host.firstElementChild);
  });

  // The held handover never strands the page: whatever goes wrong while it
  // waits (here, reading the document's field throws), the app still takes
  // the page instead of the document staying for good with the app behind it.
  testWidgets('a failure while the handover waits still hands the page over', (WidgetTester tester) async {
    final web.Element fallback = _document();
    addTearDown(() => fallback.remove());
    final web.HTMLTextAreaElement field = web.document.querySelector('#dv-field-1')! as web.HTMLTextAreaElement;
    field.focus();
    _type(field, 'hello');
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Checking your session'))));
    bool handed = false;
    unawaited(dvHandOverSsrFields().then((_) => handed = true));
    // From now on the field cannot be read.
    (web.window as JSObject).callMethod<JSAny?>(
      'eval'.toJS,
      '(function(f){var d=Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype,"value");'
              'Object.defineProperty(f,"value",{get:function(){throw new Error("unreadable")},set:d.set,configurable:true})})'
              '(document.querySelector("#dv-field-1"))'
          .toJS,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(handed, isTrue, reason: 'the app takes the page, and the failure is reported');
    expect(tester.takeException(), isNotNull);
  });
}
