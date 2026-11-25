// SSR-first fields at the handover, in a browser: the server-rendered
// page's head script and a real document field, then the app.
//
// sigmadev.digital's keyword density checker on a phone (Dartvel 3.47.9):
// nothing could be typed before Flutter took over. Now the visitor types
// into the document's own field; when the app's first frame arrives, the
// app's field has the text, the caret and the focus, and a keystroke that
// still lands in the document's field mid-handover follows it. A button
// pressed before the app is there is made on the app's button afterwards.
//
// Typing is the field's value and an `input` event, as a keystroke makes
// it: a test page cannot send trusted key events. The real keyboard, mouse
// and touch are checked in Chrome on a web-server build.
//
// Run with: flutter test --platform chrome test/ssr_fields_browser_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:dartvel_core/src/web/ssr_first.dart' show dvSsrFirstHead;
import 'package:dartvel_flutter/src/seo/ssr_fields_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

bool _headInstalled = false;

/// The SSR-first head's scripts, run as the page runs them.
void _installHead() {
  if (_headInstalled) return;
  _headInstalled = true;
  final String head = dvSsrFirstHead(background: '#ffffff', darkBackground: '#000000', accent: '#0055ff');
  for (final RegExpMatch script in RegExp(r'<script>(.*?)</script>', dotAll: true).allMatches(head)) {
    final web.HTMLScriptElement element = web.document.createElement('script') as web.HTMLScriptElement
      ..text = script.group(1)!;
    web.document.head!.append(element);
  }
}

/// A server-rendered document with one field and one button.
web.Element _document() {
  final web.Element fallback = web.document.createElement('div')
    ..className = 'dv-fallback'
    ..innerHTML = ('<p><label for="dv-field-1">Your content</label> '
            '<textarea id="dv-field-1" name="Your content" data-dv-field="Your content"></textarea></p>'
            '<p><strong role="button" tabindex="0" aria-label="Analyse">Analyse</strong></p>')
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
  // The browser runner shows print, not the console dump: the failure is
  // printed as well as reported.
  final TestExceptionReporter report = reportTestException;
  reportTestException = (FlutterErrorDetails details, String description) {
    // ignore: avoid_print
    print('FAILED: ${details.exceptionAsString()}');
    report(details, description);
  };

  testWidgets('typed before the app, it is in the app after, with focus and caret, mid-word too',
      (WidgetTester tester) async {
    final web.Element fallback = _document();
    addTearDown(() => fallback.remove());
    final web.HTMLTextAreaElement field = web.document.querySelector('#dv-field-1')! as web.HTMLTextAreaElement;
    // A press on a button the app has not drawn yet.
    final web.Element button = web.document.querySelector('.dv-fallback [role=button]')!;
    (button as web.HTMLElement).click();
    expect(button.getAttribute('aria-busy'), 'true', reason: 'it says it is on its way, not dead');
    // The app's button, as its semantics tree puts it on the page.
    final web.Element host = web.document.createElement('flt-semantics-host')
      ..innerHTML = '<flt-semantics role="button" aria-label="Analyse"></flt-semantics>'.toJS;
    web.document.body!.append(host);
    addTearDown(() => host.remove());
    int appPresses = 0;
    host.firstElementChild!.addEventListener('click', ((web.Event _) => appPresses++).toJS);

    field.focus();
    _type(field, 'hello wor');

    final TextEditingController content = TextEditingController();
    final FocusNode focus = FocusNode();
    final List<String> heard = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Semantics(
          label: 'Your content',
          child: TextField(
            controller: content,
            focusNode: focus,
            maxLines: null,
            onChanged: heard.add,
          ),
        ),
      ),
    ));

    // What the app does at its first frame: carry, then say it has drawn.
    dvHandOverSsrFields();
    web.window.dispatchEvent(web.Event('dartvel-first-frame'));
    expect(content.text, 'hello wor');
    expect(content.selection, const TextSelection.collapsed(offset: 9));
    expect(heard, contains('hello wor'));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    // The app took the keyboard; the handover did not drop it on the page.
    expect(web.document.activeElement, isNot(field));
    expect(web.document.activeElement, isNot(web.document.body));

    _type(field, 'after it let go');
    await tester.pump();
    expect(content.text, 'hello wor', reason: 'once the document field lets go, it is not followed');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    expect(web.document.documentElement!.hasAttribute('data-dv-app'), isTrue);
    expect(appPresses, 1, reason: "the press is made on the app's button once the app is there");
    expect(button.hasAttribute('aria-busy'), isFalse);
    web.document.documentElement!.removeAttribute('data-dv-app');
  });
  testWidgets('a keystroke still landing in the document field follows into the app, mid-word',
      (WidgetTester tester) async {
    final web.Element fallback = _document();
    addTearDown(() => fallback.remove());
    final web.HTMLTextAreaElement field = web.document.querySelector('#dv-field-1')! as web.HTMLTextAreaElement;
    field.focus();
    _type(field, 'hello wor');
    final TextEditingController content = TextEditingController();
    // A field that cannot take focus yet keeps the keyboard in the
    // document's field, as the moment before the app's field has it does.
    final FocusNode focus = FocusNode(canRequestFocus: false);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Semantics(
          label: 'Your content',
          child: TextField(controller: content, focusNode: focus, maxLines: null),
        ),
      ),
    ));
    dvHandOverSsrFields();
    await tester.pump();
    expect(content.text, 'hello wor');
    expect(web.document.activeElement, field);
    _type(field, 'hello world');
    await tester.pump();
    expect(content.text, 'hello world');
    expect(content.selection, const TextSelection.collapsed(offset: 11));
    field.blur();
    _type(field, 'after it let go');
    await tester.pump();
    expect(content.text, 'hello world', reason: 'once the document field lets go, it is not followed');
  });
}
