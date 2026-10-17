/// Everything hoverable has a tooltip, and the tooltip is the control's name.
///
/// A control that is only a picture makes a pointer user guess and gives a
/// screen reader nothing to say. So the name is a precondition of the control,
/// not a courtesy: it comes from the words on the control, or from the
/// application saying so with `.tooltip('...')`, or the control is refused
/// with the file and line that drew it.
///
/// One piece of text does three jobs, so they cannot drift apart: the tooltip
/// a mouse sees on hover, a keyboard sees on focus and a finger sees on a long
/// press; the label a screen reader announces; and the `title` and
/// `aria-label` the server-rendered HTML carries (the HTML is built from the
/// same semantics tree, see the CLI's `dvSemanticHtml`).
library dartvel_flutter.accessibility.tooltips;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart' show DVBox, DVModifier, DVText;

/// The file and line that is calling, for an error that says where to look.
///
/// Debug builds only: it is read from a stack trace, which is not a cost a
/// release build pays. Frames inside this package's own modifier plumbing are
/// skipped so the answer is the application line, or the Studio line, that
/// asked for the control.
String? dvCallSite() {
  String? site;
  assert(() {
    final RegExp frame = RegExp(r'\(?((?:package:|file:)[^\s)]+?):(\d+):\d+\)?');
    for (final String line in StackTrace.current.toString().split('\n')) {
      final Match? match = frame.firstMatch(line);
      if (match == null) continue;
      final String path = match.group(1)!;
      if (path.endsWith('/dartvel_flutter.dart') ||
          path.endsWith('/tooltips.dart') ||
          path.startsWith('package:flutter/') ||
          path.startsWith('package:flutter_test/') ||
          path.startsWith('package:test_api/')) {
        continue;
      }
      site = '${path.replaceFirst(RegExp(r'^file://'), '')}:${match.group(2)}';
      break;
    }
    return true;
  }());
  return site;
}

/// The words a widget shows, found without building it: text, an icon's own
/// label, and what sits in the children it was handed. Null when there are none.
///
/// A widget composed from other widgets (a stateless wrapper) is not looked
/// inside; [DVTooltipTarget] looks at the built elements for those, one frame
/// later.
String? dvDeriveLabel(Widget? widget) {
  if (widget == null) return null;
  final List<String> parts = <String>[];
  void visit(Widget? current) {
    if (current == null) return;
    if (current is Text) {
      final String? text = current.data ?? current.textSpan?.toPlainText();
      if (text != null && text.trim().isNotEmpty) parts.add(text.trim());
    } else if (current is RichText) {
      final String text = current.text.toPlainText();
      if (text.trim().isNotEmpty) parts.add(text.trim());
    } else if (current is Icon) {
      final String? label = current.semanticLabel;
      if (label != null && label.trim().isNotEmpty) parts.add(label.trim());
    } else if (current is Semantics) {
      final String? label = current.properties.label;
      if (label != null && label.trim().isNotEmpty) {
        parts.add(label.trim());
        return;
      }
    }
    if (current is SingleChildRenderObjectWidget) visit(current.child);
    if (current is MultiChildRenderObjectWidget) {
      for (final Widget child in current.children) {
        visit(child);
      }
    }
    if (current is ProxyWidget) visit(current.child);
    if (current is DVText) {
      if (current.text.trim().isNotEmpty) parts.add(current.text.trim());
    } else if (current is DVBox) {
      for (final Widget child in current.labelChildren) {
        visit(child);
      }
    }
    if (current is Tooltip) {
      final String? message = current.message;
      if (message != null && message.trim().isNotEmpty && parts.isEmpty) {
        parts.add(message.trim());
      }
    }
  }

  visit(widget);
  if (parts.isEmpty) return null;
  return parts.join(' ');
}

/// The words in the elements already built under [context].
String? _builtLabel(BuildContext context) {
  final List<String> parts = <String>[];
  void visit(Element element) {
    final Widget widget = element.widget;
    // Text and Icon draw themselves with a RichText; reading that too would
    // say every word twice, and an icon's glyph is not a word at all.
    if (widget is Text) {
      final String? text = widget.data ?? widget.textSpan?.toPlainText();
      if (text != null && text.trim().isNotEmpty) parts.add(text.trim());
      return;
    }
    if (widget is Icon) {
      final String? label = widget.semanticLabel;
      if (label != null && label.trim().isNotEmpty) parts.add(label.trim());
      return;
    }
    if (widget is RichText) {
      final String text = widget.text.toPlainText();
      if (text.trim().isNotEmpty) parts.add(text.trim());
      return;
    }
    if (widget is Tooltip && widget.message != null && parts.isEmpty) {
      parts.add(widget.message!);
    }
    element.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
  return parts.isEmpty ? null : parts.join(' ');
}

/// Puts the tooltip on a control, and tells it the name it ended up with.
///
/// [label] is the explicit name, if the application gave one; otherwise the
/// name is derived from the words inside [child]. With neither, a debug build
/// reports the error naming [site]: that is the "icon-only control with no
/// label fails" rule, and `dartvel build` and `dartvel doctor` run the same
/// rule over the source so a release build cannot ship it either.
class DVTooltipTarget extends StatefulWidget {
  const DVTooltipTarget({
    super.key,
    required this.label,
    required this.child,
    this.site,
    this.required = true,
    this.builder,
  });

  /// What the application said this control is. Null to derive it.
  final String? label;

  /// Where the control was written, for the error.
  final String? site;

  /// Whether a missing name is an error. False for decoration that only gains
  /// a tooltip when it has one.
  final bool required;

  final Widget child;

  /// Draws the child with the resolved name. Used by the pressable, whose
  /// semantics node must carry the same words.
  final Widget Function(BuildContext context, String? name)? builder;

  @override
  State<DVTooltipTarget> createState() => _DVTooltipTargetState();
}

class _DVTooltipTargetState extends State<DVTooltipTarget> {
  final GlobalKey<TooltipState> _tooltip = GlobalKey<TooltipState>();
  String? _built;

  String? get _name {
    final String? explicit = widget.label?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return dvDeriveLabel(widget.child) ?? _built;
  }

  @override
  void initState() {
    super.initState();
    _verifyAfterFrame();
  }

  @override
  void didUpdateWidget(DVTooltipTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label) {
      _built = null;
      _verifyAfterFrame();
    }
  }

  void _verifyAfterFrame() {
    if (_name != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _name != null) return;
      final String? found = _builtLabel(context);
      if (found != null) {
        setState(() => _built = found);
        return;
      }
      if (!widget.required) return;
      if (kDebugMode) {
        throw FlutterError(
            'A control has no tooltip and no name.\n'
            '${widget.site == null ? '' : 'It is drawn at ${widget.site}.\n'}'
            'Everything hoverable has a tooltip, and the same words are its '
            'semantic label. Give it one with .tooltip(\'What it does\') on '
            'its DVModifier, or put text in it. An icon-only control is a '
            'DVBox around the Icon with .tooltip(...).onTap(...).',
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? name = _name;
    final Widget inner = widget.builder == null
        ? widget.child
        : widget.builder!(context, name);
    if (name == null || Overlay.maybeOf(context) == null) return inner;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      includeSemantics: false,
      onFocusChange: (bool focused) {
        if (focused) {
          // Only the keyboard's focus: a click also focuses, and the mouse
          // already gets its tooltip from hovering.
          if (FocusManager.instance.highlightMode ==
              FocusHighlightMode.traditional) {
            _tooltip.currentState?.ensureTooltipVisible();
          }
        } else {
          Tooltip.dismissAllToolTips();
        }
      },
      child: Tooltip(
        key: _tooltip,
        message: name,
        // The name is announced by the control's own semantics node; the
        // tooltip adding it again would read it twice.
        excludeFromSemantics: true,
        triggerMode: TooltipTriggerMode.longPress,
        waitDuration: const Duration(milliseconds: 400),
        child: inner,
      ),
    );
  }
}
