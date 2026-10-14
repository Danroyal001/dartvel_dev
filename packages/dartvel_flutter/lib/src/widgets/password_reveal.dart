/// The one control that shows or hides what was typed into a password field.
///
/// Every hidden field Dartvel draws uses it: a data model form's password
/// field, the account pages, and Studio's sign-in, first-run setup and record
/// editor. Before this there were two eyes and three fields with none, and
/// the fields with none were Studio's -- where an owner types the long
/// password the application printed on its first run.
///
/// It is a toggle button in the ARIA sense: one name, "Show password", and a
/// pressed state. The earlier eye renamed itself to "Hide password" once
/// pressed, which a screen reader announces as "Hide password, button" with
/// nothing to say the password is showing; renaming a toggle is the pattern
/// the ARIA practices warn against, because the name then reads as an
/// instruction one moment and a state the next. The same words are its
/// tooltip, as every control's tooltip is its name.
///
/// On the web the pressed state is `aria-pressed` on the button Flutter puts
/// in the page, which is what the server-rendered document's own eye carries
/// too, so the control is announced the same way before and after Flutter
/// takes over. Flutter's web semantics have no pressed state of their own --
/// a toggled node becomes `role="switch"` -- so the attribute is set by
/// `password_reveal_web.dart`, keyed by each eye's own identifier. Everywhere else the state
/// is Flutter's own toggled flag, which TalkBack and VoiceOver announce.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'password_reveal_stub.dart'
    if (dart.library.js_interop) 'password_reveal_web.dart'
    as platform;

/// What a field rendered by the server held when Flutter took over.
///
/// The server-rendered document is a real page with real inputs, so a person
/// can start typing, and reveal what they typed, before the application has
/// painted. A field that started empty when Flutter arrived would throw that
/// away; this is what the field picks up instead.
@immutable
class DVServerFieldState {
  const DVServerFieldState({required this.value, required this.revealed});

  /// What was typed into the field.
  final String value;

  /// Whether its eye was pressed.
  final bool revealed;
}

/// Reads the server-rendered field named [label], or null when there is none
/// -- off the web, on a page the server did not render, or once read: a field
/// is taken over once, so a second form with the same label later in the
/// session does not inherit what was typed into the first.
///
/// A variable so a test can stand in for the document.
DVServerFieldState? Function(String label) dvServerField =
    platform.dvReadServerField;

/// The eye in a password field.
class DVPasswordReveal extends StatefulWidget {
  const DVPasswordReveal({
    super.key,
    required this.revealed,
    required this.onPressed,
    this.color,
    this.size = 20,
  });

  /// The control's name, its tooltip and the `aria-label` the server-rendered
  /// document gives its own eye: one string, so the three cannot drift.
  static const String name = 'Show password';

  /// What the button's semantics identifier starts with, and what the build's
  /// capture of a page recognises it by. Each eye adds `|<n>`, its own number,
  /// so its pressed state can be put on its own element on the web.
  static const String identifier = 'dartvel:reveal';

  /// Whether the password is showing: the button's pressed state.
  final bool revealed;

  final VoidCallback onPressed;

  /// The icon's colour; the theme's when null.
  final Color? color;

  final double size;

  @override
  State<DVPasswordReveal> createState() => _DVPasswordRevealState();
}

class _DVPasswordRevealState extends State<DVPasswordReveal> {
  static int _next = 0;

  /// This eye's own number, constant for its life. The pressed state is not
  /// put in the identifier itself: Flutter's web engine did not always write
  /// a changed identifier back to the page, and the eye stayed "pressed"
  /// after it had hidden the password again.
  late final String _identifier = '${DVPasswordReveal.identifier}|${_next++}';

  @override
  void dispose() {
    if (kIsWeb) platform.dvForgetPressed(_identifier);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool revealed = widget.revealed;
    if (kIsWeb) platform.dvSetPressed(_identifier, revealed);
    // One node: the name, the state and the identifier on the same node as
    // the button's tap and focus. The tooltip is shown on hover, focus and
    // long press, and kept out of the semantics: it is the same words as the
    // name, and with both a screen reader read "Show password Show password".
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: DVPasswordReveal.name,
        // Off the web, the platform's own toggled state. On the web a toggled
        // node is drawn as a switch, so the state goes out as aria-pressed
        // instead (see the library comment).
        toggled: kIsWeb ? null : revealed,
        identifier: _identifier,
        child: Tooltip(
          message: DVPasswordReveal.name,
          excludeFromSemantics: true,
          child: IconButton(
            onPressed: widget.onPressed,
            icon: Icon(
              revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: widget.size,
              color: widget.color,
            ),
            visualDensity: VisualDensity.compact,
            // The keyboard's own affordance: the ring Material draws around a
            // focused button, which a field's decoration would otherwise
            // cover.
            focusColor: Theme.of(context).focusColor,
          ),
        ),
      ),
    );
  }
}

/// A hidden field's reveal state, with the takeover from the server-rendered
/// page folded in: mixed into the state of any widget that draws a password
/// field, so each of them starts from what the person already did.
mixin DVPasswordRevealState<T extends StatefulWidget> on State<T> {
  /// Whether the password is showing.
  bool revealed = false;

  /// Picks up the server-rendered field named [label], if there was one, and
  /// returns what was typed into it (null when nothing was).
  String? takeOverServerField(String label) {
    final DVServerFieldState? server = dvServerField(label);
    if (server == null) return null;
    revealed = server.revealed;
    return server.value.isEmpty ? null : server.value;
  }

  void toggleRevealed() => setState(() => revealed = !revealed);
}

/// A password field drawn by its host, with the reveal state and the eye
/// handed to it: what a screen with its own [TextField] uses, so it does not
/// have to keep the state, the takeover or the button itself.
///
/// [label] names the field the server rendered, and [controller] receives
/// what was typed into it before Flutter took over.
class DVPasswordRevealBuilder extends StatefulWidget {
  const DVPasswordRevealBuilder({
    super.key,
    required this.label,
    required this.controller,
    required this.builder,
    this.eyeColor,
  });

  final String label;
  final TextEditingController controller;

  /// Draws the field: [obscured] is what its `obscureText` should be, and
  /// [eye] goes in it, usually as the decoration's `suffixIcon`.
  final Widget Function(BuildContext context, bool obscured, Widget eye)
  builder;

  final Color? eyeColor;

  @override
  State<DVPasswordRevealBuilder> createState() =>
      _DVPasswordRevealBuilderState();
}

class _DVPasswordRevealBuilderState extends State<DVPasswordRevealBuilder>
    with DVPasswordRevealState<DVPasswordRevealBuilder> {
  @override
  void initState() {
    super.initState();
    final String? typed = takeOverServerField(widget.label);
    if (typed != null && widget.controller.text.isEmpty) {
      widget.controller.text = typed;
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    !revealed,
    DVPasswordReveal(
      revealed: revealed,
      onPressed: toggleRevealed,
      color: widget.eyeColor,
    ),
  );
}

/// Puts what was typed into the server-rendered field named [label] into
/// [controller], when there was something and [controller] is empty.
///
/// For a field with no eye -- an email beside a password -- so a person who
/// started on the server-rendered form keeps both halves of what they typed.
void dvTakeOverServerField(String label, TextEditingController controller) {
  final DVServerFieldState? server = dvServerField(label);
  if (server == null || server.value.isEmpty || controller.text.isNotEmpty) {
    return;
  }
  controller.text = server.value;
}
