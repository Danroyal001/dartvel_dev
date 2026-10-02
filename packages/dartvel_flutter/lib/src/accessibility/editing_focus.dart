/// Whether somebody is typing.
///
/// The page-wide key handlers -- keyboard scrolling, a remote's D-pad and
/// select key -- sit above every control and see a key only after the focused
/// control has passed on it. A text field passes on most of its keys: Space,
/// Enter, the arrows, Home and End reach it from the platform's text input,
/// not as handled key events. Answered as handled above it, the browser was
/// told the page had used them, so Space scrolled instead of typing, the
/// caret would not move, and Enter never submitted a form.
library;

import 'package:flutter/widgets.dart';

/// True while the focused node belongs to a text field, or any other
/// [EditableText].
bool dvFocusIsEditingText() {
  final BuildContext? context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  return context.widget is EditableText ||
      context.findAncestorWidgetOfExactType<EditableText>() != null;
}
