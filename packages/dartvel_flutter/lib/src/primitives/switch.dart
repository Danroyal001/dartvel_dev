// DVSwitch: one thing turned on or off, as a Dartvel primitive.
//
//   DVSwitch(
//     label: 'High contrast',
//     explanation: 'Pure black and white with strong outlines.',
//     value: settings.highContrast,
//     onChanged: (bool on) => ...,
//   )
//
// The whole row is the control: a tap or a press of Space/Enter anywhere on
// it flips the switch, it is one stop for the Tab key, its tooltip and its
// screen-reader name are the label, and the explanation is its hint. With no
// onChanged it is shown as given and cannot be changed (a setting the device
// already decides).
import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart' show DVBox, DVModifier, DVText;
import 'modifier_chain.dart';

/// One thing turned on or off. See the library documentation.
class DVSwitch extends StatelessWidget with DVModifierChain<DVSwitch> {
  const DVSwitch({
    super.key,
    required this.label,
    this.explanation,
    required this.value,
    this.onChanged,
    this.modifier,
  });

  /// What the switch turns on: its words, tooltip and screen-reader name.
  final String label;

  /// A sentence under the label, read as the switch's hint.
  final String? explanation;

  /// Whether it is on.
  final bool value;

  /// Called with the new value; null shows [value] and refuses changes.
  final ValueChanged<bool>? onChanged;

  /// Padding, width and the rest round the whole row.
  final DVModifier? modifier;

  @override
  DVModifier? get chainModifier => modifier;

  @override
  DVSwitch withModifier(DVModifier modifier) =>
      DVSwitch(key: key, label: label, explanation: explanation, value: value, onChanged: onChanged, modifier: modifier);

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final ValueChanged<bool>? changed = onChanged;
    final VoidCallback? flip = changed == null ? null : () => changed(!value);
    final String? help = explanation;
    final Widget row = Semantics(
      container: true,
      excludeSemantics: true,
      toggled: value,
      enabled: changed != null,
      label: label,
      hint: help,
      onTap: flip,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: flip,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: DVBox.list(<Widget>[
                      DVText(label).fontSize(16).fontWeight(.w600).color(colours.onSurface),
                      if (help != null) DVText(help).fontSize(14).color(colours.onSurfaceVariant),
                    ], spacing: 2),
                  ),
                  const SizedBox(width: 12),
                  // The row is the one control: the switch inside it is
                  // drawn, not a second Tab stop.
                  ExcludeFocus(child: Switch(value: value, onChanged: changed)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final DVModifier? outer = modifier;
    return outer == null ? row : DVBox(row, outer);
  }
}
