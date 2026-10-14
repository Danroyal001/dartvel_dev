/// The eye on the web: reading the server-rendered field Flutter replaces,
/// and carrying the pressed state onto the button Flutter puts in the page.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'password_reveal.dart' show DVPasswordReveal, DVServerFieldState;

/// The server-rendered input named [label], read once and then emptied.
///
/// Emptied because the document stays in the page after Flutter takes over --
/// it is what find and print read -- and a password left in a hidden input is
/// a password left lying about. Marked taken, so a later form with the same
/// label does not inherit it.
DVServerFieldState? dvReadServerField(String label) {
  final web.NodeList inputs = web.document.querySelectorAll(
    '.dv-fallback input[data-dv-field]',
  );
  for (int index = 0; index < inputs.length; index++) {
    final web.HTMLInputElement input =
        inputs.item(index)! as web.HTMLInputElement;
    if (input.getAttribute('data-dv-field') != label) continue;
    if (input.hasAttribute('data-dv-taken')) return null;
    input.setAttribute('data-dv-taken', '');
    final web.Element? eye = input.id.isEmpty
        ? null
        : web.document.querySelector('[aria-controls="${input.id}"]');
    final DVServerFieldState state = DVServerFieldState(
      value: input.value,
      revealed: eye?.getAttribute('aria-pressed') == 'true',
    );
    input.value = '';
    return state;
  }
  return null;
}

/// Whether each eye in the page is pressed, by its identifier.
final Map<String, bool> _pressed = <String, bool>{};

bool _watching = false;
bool _scheduled = false;

/// Records that the eye [identifier] is [pressed], and puts that on the
/// button Flutter draws for it as `aria-pressed`.
///
/// Applied after the frame, once Flutter has written its semantics to the
/// page, and again whenever Flutter adds or rewrites the element: it rebuilds
/// its semantics elements when it likes, and an attribute set once would be
/// right only until the next rebuild of the node.
void dvSetPressed(String identifier, bool pressed) {
  _pressed[identifier] = pressed;
  _watch();
  if (_scheduled) return;
  _scheduled = true;
  web.window.requestAnimationFrame(((JSNumber _) {
    _scheduled = false;
    _sync();
  }).toJS);
}

/// Forgets an eye that has left the page.
void dvForgetPressed(String identifier) => _pressed.remove(identifier);

void _sync() {
  final web.NodeList eyes = web.document
      .querySelectorAll('[flt-semantics-identifier^="${DVPasswordReveal.identifier}"]');
  for (int index = 0; index < eyes.length; index++) {
    final web.Element eye = eyes.item(index)! as web.Element;
    final bool? pressed = _pressed[eye.getAttribute('flt-semantics-identifier')];
    if (pressed == null) continue;
    if (eye.getAttribute('aria-pressed') != '$pressed') {
      eye.setAttribute('aria-pressed', '$pressed');
    }
  }
}

void _watch() {
  if (_watching) return;
  _watching = true;
  web.MutationObserver(
          ((JSArray<web.MutationRecord> _, web.MutationObserver __) {
    _sync();
  }).toJS)
      .observe(
    web.document.documentElement!,
    web.MutationObserverInit(
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: <JSString>['flt-semantics-identifier'.toJS].toJS,
    ),
  );
}
