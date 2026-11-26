// DVChoice: one value picked from a few, as a Dartvel primitive.
//
//   DVChoice<DVTextSize>(
//     options: DVTextSize.values,
//     selected: settings.textSize,
//     name: (DVTextSize size) => size.label,
//     label: 'Text size',
//     onChanged: (DVTextSize size) => ...,
//   ).paddingOnly(top: 8)
//
// Chips that wrap (the default) for a handful of short options; a menu
// ([DVChoiceStyle.menu]) for a longer list. Either way each option has its
// name, the selected one is marked for the eye and for a screen reader, and
// the keyboard reaches and picks every option.
import 'package:flutter/material.dart';

import '../../dartvel_flutter.dart' show DVBox, DVModifier, DVText;
import 'modifier_chain.dart';

/// How a [DVChoice] is drawn.
enum DVChoiceStyle {
  /// One chip per option, wrapping onto more lines when the row is full:
  /// a handful of short options.
  chips,

  /// A field showing the selected option, which opens the list: a longer
  /// list, or one with long names.
  menu,
}

/// One value picked from [options]. See the library documentation.
class DVChoice<T> extends StatelessWidget with DVModifierChain<DVChoice<T>> {
  const DVChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.name,
    required this.onChanged,
    this.optionTooltip,
    this.label,
    this.style = DVChoiceStyle.chips,
    this.modifier,
  });

  /// What can be picked, in the order shown.
  final List<T> options;

  /// The option picked now.
  final T selected;

  /// The words an option is shown and announced by.
  final String Function(T option) name;

  /// Called with the option picked.
  final ValueChanged<T> onChanged;

  /// An option's tooltip, when its name alone does not say enough
  /// (`Large text (135%)`). The name otherwise.
  final String Function(T option)? optionTooltip;

  /// What is being picked: the group's name for a screen reader, and the
  /// field's label for a menu.
  final String? label;

  final DVChoiceStyle style;

  /// Padding, width and the rest round the whole choice.
  final DVModifier? modifier;

  @override
  DVModifier? get chainModifier => modifier;

  @override
  DVChoice<T> withModifier(DVModifier modifier) => DVChoice<T>(
        key: key,
        options: options,
        selected: selected,
        name: name,
        onChanged: onChanged,
        optionTooltip: optionTooltip,
        label: label,
        style: style,
        modifier: modifier,
      );

  @override
  Widget build(BuildContext context) {
    final Widget choice = switch (style) {
      .chips => _chips(context),
      .menu => _menu(context),
    };
    final DVModifier? outer = modifier;
    return outer == null ? choice : DVBox(choice, outer);
  }

  Widget _chips(BuildContext context) {
    final Widget chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final T option in options)
          ChoiceChip(
            label: DVText(name(option)),
            tooltip: optionTooltip?.call(option) ?? name(option),
            selected: option == selected,
            showCheckmark: true,
            onSelected: (bool _) {
              if (option != selected) onChanged(option);
            },
          ),
      ],
    );
    final String? group = label;
    return group == null ? chips : Semantics(container: true, label: group, explicitChildNodes: true, child: chips);
  }

  Widget _menu(BuildContext context) => DropdownButtonFormField<T>(
        // The field keeps its own value; a new selection from outside is a
        // new field.
        key: ValueKey<T>(selected),
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: <DropdownMenuItem<T>>[
          for (final T option in options)
            DropdownMenuItem<T>(
              value: option,
              child: DVText(name(option)).maxLines(1).overflow(.ellipsis),
            ),
        ],
        onChanged: (T? option) {
          if (option != null && option != selected) onChanged(option);
        },
      );
}
