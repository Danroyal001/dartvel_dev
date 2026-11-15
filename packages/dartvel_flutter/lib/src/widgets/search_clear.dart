/// The one control that empties a search field, and the behaviour around it.
///
/// Every search box Dartvel draws has it, by default: a field made with
/// `.input(search: true)`, Studio's record and element searches, and Studio's
/// command palette. It is the ergonomics every platform's own search box has
/// had for years -- an "x" in the box once there is something to clear --
/// and before this each Dartvel search box made the reader select and delete
/// what they had typed to start again.
///
/// The control:
///
/// * is shown only while the field holds text: an "x" over an empty box is a
///   control that does nothing;
/// * empties the field and leaves the focus in it, so the next search is
///   typed straight away, and says so through the field's own change callback
///   with `''` and through an optional `onCleared`;
/// * is named "Clear search": the same words are its tooltip, its screen
///   reader name, and the `title`/`aria-label` of the server-rendered
///   document's own clear button (`dvDocumentField` in dartvel_core);
/// * is a real button: reachable with Tab, pressed with Enter or Space;
/// * and Escape in the field does the same, while there is text to clear.
///   An empty field leaves Escape alone, so it still closes the dialog the
///   field is in.
library;

import 'dart:ui' show SemanticsInputType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Draws an application's own clear control, given the call that clears.
typedef DVClearButtonBuilder = Widget Function(
  BuildContext context,
  VoidCallback clear,
);

/// Whether a search field has a clear control, and which.
///
/// The default on `.input(search: true)` is [x]. [none] turns it off, and
/// [custom] draws a control of the application's own in its place; either way
/// Escape still clears while the field is a search field and [none] was not
/// chosen.
sealed class DVClearButton {
  const DVClearButton();

  /// The "x" in the field, named "Clear search". The default on a search
  /// field.
  static const DVClearButton x = DVXClearButton();

  /// No clear control, and Escape is left alone.
  static const DVClearButton none = DVNoneClearButton();

  /// A control of the application's own, shown while there is text, given the
  /// call that clears the field and keeps the focus in it.
  static DVCustomClearButton custom(DVClearButtonBuilder builder) =>
      DVCustomClearButton(builder);
}

/// The default: the "x" button inside the field.
final class DVXClearButton extends DVClearButton {
  const DVXClearButton();
}

/// Off: no clear control on this field.
final class DVNoneClearButton extends DVClearButton {
  const DVNoneClearButton();
}

/// A control of the application's own, drawn instead of the "x".
final class DVCustomClearButton extends DVClearButton {
  const DVCustomClearButton(this.builder);

  final DVClearButtonBuilder builder;
}

/// The "x" in a search field.
class DVSearchClear extends StatelessWidget {
  const DVSearchClear({
    super.key,
    required this.onPressed,
    this.color,
    this.size = 20,
  });

  /// The control's name, its tooltip and the `aria-label` the server-rendered
  /// document gives its own clear button: one string, so the three cannot
  /// drift.
  static const String name = 'Clear search';

  /// The button's semantics identifier, which the build's capture of a page
  /// recognises it by: the document writes its own clear button, which works
  /// before Flutter has run, and this one is not written a second time.
  static const String identifier = 'dartvel:clear';

  final VoidCallback onPressed;

  /// The icon's colour; the theme's when null.
  final Color? color;

  final double size;

  @override
  Widget build(BuildContext context) {
    // One node: the name and the identifier on the same node as the button's
    // tap and focus. The tooltip is shown on hover, focus and long press and
    // kept out of the semantics, since it is the same words as the name.
    return MergeSemantics(
      child: Semantics(
        button: true,
        label: name,
        identifier: identifier,
        child: Tooltip(
          message: name,
          excludeFromSemantics: true,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(Icons.close, size: size, color: color),
            visualDensity: VisualDensity.compact,
            focusColor: Theme.of(context).focusColor,
          ),
        ),
      ),
    );
  }
}

/// A search field drawn by its host, with the clear control and Escape handed
/// to it: what a screen with its own [TextField] or [EditableText] uses, so it
/// does not keep the listening, the focus or the key handling itself.
///
/// [builder] draws the field and puts `clear` in it, usually as the
/// decoration's `suffixIcon`; `clear` is null while the field is empty and
/// when [clearButton] is [DVClearButton.none]. Clearing empties [controller],
/// puts the focus back on [focusNode], then calls [onChanged] with `''` and
/// [onCleared].
///
/// The field is also announced as a search box: on the web it becomes an
/// `<input type="search">`, which is what the build's capture writes into the
/// server-rendered document.
class DVSearchClearBuilder extends StatefulWidget {
  const DVSearchClearBuilder({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.builder,
    this.clearButton = DVClearButton.x,
    this.onChanged,
    this.onCleared,
    this.color,
    this.size = 20,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget Function(BuildContext context, Widget? clear) builder;
  final DVClearButton clearButton;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onCleared;

  /// The "x"'s colour and size.
  final Color? color;
  final double size;

  @override
  State<DVSearchClearBuilder> createState() => _DVSearchClearBuilderState();
}

class _DVSearchClearBuilderState extends State<DVSearchClearBuilder> {
  late bool _hasText = widget.controller.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(DVSearchClearBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _hasText = widget.controller.text.isNotEmpty;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final bool hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText && mounted) setState(() => _hasText = hasText);
  }

  void _clear() {
    widget.controller.clear();
    widget.focusNode.requestFocus();
    widget.onChanged?.call('');
    widget.onCleared?.call();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    // Nothing to clear: Escape is the dialog's, or the page's.
    if (widget.controller.text.isEmpty) return KeyEventResult.ignored;
    _clear();
    return KeyEventResult.handled;
  }

  Widget? _control() {
    if (!_hasText) return null;
    return switch (widget.clearButton) {
      DVNoneClearButton() => null,
      DVCustomClearButton(:final DVClearButtonBuilder builder) =>
        builder(context, _clear),
      DVXClearButton() => DVSearchClear(
          onPressed: _clear,
          color: widget.color,
          size: widget.size,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final Widget field = Semantics(
      inputType: SemanticsInputType.search,
      child: widget.builder(context, _control()),
    );
    if (widget.clearButton is DVNoneClearButton) return field;
    // Not a focus stop of its own: the key arrives here from the field inside
    // it, on its way up the focus tree, before the app's own Escape.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: field,
    );
  }
}
