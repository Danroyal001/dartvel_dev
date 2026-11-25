// `find.byTooltip`, for material_ui's Tooltip.
//
// flutter_test 3.50.1's `find.byTooltip` imports `Tooltip` from
// package:flutter/material.dart. material_ui's Tooltip is a different class
// (material_ui is a copy of the library, not a re-export), so the finder
// never matches it directly. That only matters when the tooltip adds nothing
// to the semantics tree -- `excludeFromSemantics: true`, which is how every
// Dartvel control names itself once, by its own semantics label -- and then
// it finds nothing at all. This is the same rule as flutter_test's, read off
// material_ui's class.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

extension DVTooltipFinder on CommonFinders {
  /// The tooltip whose message is [message], as `find.byTooltip` finds it.
  Finder dvTooltip(Pattern message, {bool skipOffstage = true}) =>
      byWidgetPredicate((Widget widget) {
        bool matches(String? text) =>
            text != null &&
            (message is RegExp ? message.hasMatch(text) : text == message);
        if (widget is Tooltip) {
          final String text =
              widget.message ?? widget.richMessage?.toPlainText() ?? '';
          if ((widget.excludeFromSemantics ?? false) || text.isEmpty) {
            return matches(text);
          }
        }
        return widget is RawTooltip && matches(widget.semanticsTooltip);
      }, skipOffstage: skipOffstage);
}
