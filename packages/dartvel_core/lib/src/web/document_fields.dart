/// A form field in a server-rendered document: a labelled input a person can
/// type into before the application's script has run, and -- for a password
/// -- the eye that shows what they typed.
///
/// One writer for every document the server sends: the pages the build
/// captured (`dvSemanticHtml` in dartvel_cli) and Studio's own sign-in and
/// setup, which no capture can reach. The words and the markup are the
/// running app's own: the eye is "Show password", that name is its tooltip,
/// and `aria-pressed` says whether the password is showing, as the eye
/// Flutter draws once it has taken over (`DVPasswordReveal` in
/// dartvel_flutter) says it.
///
/// `data-dv-field` carries the field's label, which is how the running app
/// finds the input it replaces and takes over what was typed into it.
library;

import 'dart:convert';

const HtmlEscape _text = HtmlEscape(HtmlEscapeMode.element);
const HtmlEscape _attribute = HtmlEscape(HtmlEscapeMode.attribute);

/// The eye's name, tooltip and `aria-label`.
const String dvRevealName = 'Show password';

/// What pressing the document's eye does: flips the field it controls between
/// hidden and shown, and says which in `aria-pressed`. Inline, so the button
/// works before the application's own script has loaded.
///
/// A browser with scripting off cannot change an input's type at all, so
/// there the eye is not drawn ([dvRevealNoscriptCss]) rather than drawn and
/// dead.
const String dvRevealScript =
    "var f=document.getElementById(this.getAttribute('aria-controls')),"
    "s=f.type=='password';f.type=s?'text':'password';"
    "this.setAttribute('aria-pressed',s)";

/// Hides the eye from a reader with scripting off.
const String dvRevealNoscriptCss = '.dv-fallback .dv-reveal{display:none}';

/// One field, as a paragraph holding its label and its input.
///
/// [type] is an `<input>` type (`text`, `email`, `password`, ...) or
/// `textarea`; anything that is not a plain word is written as `text`, since
/// it goes into an attribute. [id] must be unique in the document.
/// [autocomplete] is the token a password manager matches on; a password
/// field defaults to `current-password`.
String dvDocumentField({
  required String type,
  required String label,
  required String id,
  String? autocomplete,
}) {
  final String name = _attribute.convert(label);
  final StringBuffer out = StringBuffer(
      '<p><label for="$id">${_text.convert(label)}</label> ');
  if (type == 'textarea') {
    out.write('<textarea id="$id" name="$name" data-dv-field="$name">'
        '</textarea></p>');
    return out.toString();
  }
  final String safeType = RegExp(r'^[a-z-]+$').hasMatch(type) ? type : 'text';
  final String? complete =
      autocomplete ?? (safeType == 'password' ? 'current-password' : null);
  out.write('<input id="$id" type="$safeType" name="$name" '
      'data-dv-field="$name"');
  if (complete != null) {
    out.write(' autocomplete="${_attribute.convert(complete)}"');
  }
  out.write('>');
  if (safeType == 'password') {
    final String eye = _attribute.convert(dvRevealName);
    out.write('<button type="button" class="dv-reveal" aria-controls="$id" '
        'aria-pressed="false" title="$eye" aria-label="$eye" '
        'onclick="$dvRevealScript">${_text.convert(dvRevealName)}</button>');
  }
  out.write('</p>');
  return out.toString();
}
