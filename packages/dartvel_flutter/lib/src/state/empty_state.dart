/// The three ways a collection can be empty.
///
/// They were one state, and the answers differ: nothing yet wants the action
/// that creates the first one, nothing matching wants the filter cleared, and
/// nothing visible to you is a policy that filtered everything out -- which,
/// reported as "no records", sends a reader to support with the wrong
/// question.
library dartvel_flutter.state.empty_state;

import 'package:dartvel_flutter/dartvel_flutter.dart'
    show DV, DVFrameworkStrings;
import 'package:flutter/material.dart';

/// Which empty a collection is, and what it offers.
sealed class const DVEmpty() {
  /// An empty collection. [action] is the call to action that creates the
  /// first one; [label] replaces the framework's words.
  const factory DVEmpty.nothingYet({Widget? action, String? label}) =
      DVNothingYet;

  /// A filter or search with no results. [onClear] is offered as the way
  /// back, never a create button.
  const factory DVEmpty.nothingMatching({VoidCallback? onClear, String? label}) =
      DVNothingMatching;

  /// A policy filtered everything out.
  const factory DVEmpty.nothingVisible({String? label}) = DVNothingVisible;

  /// The application's own words, when it gave any.
  String? get label;
}

/// [DVEmpty.nothingYet]: [action] is what creates the first one.
final class const DVNothingYet({final Widget? action, final String? label})
    extends DVEmpty;

/// [DVEmpty.nothingMatching]: [onClear] clears the filter or search that
/// matched nothing.
final class const DVNothingMatching({
  final VoidCallback? onClear,
  final String? label,
}) extends DVEmpty;

/// [DVEmpty.nothingVisible].
final class const DVNothingVisible({final String? label}) extends DVEmpty;

/// How a collection renders [empty]: one sentence, announced once, and the
/// action that state calls for.
class DVEmptyView extends StatelessWidget {
  const DVEmptyView(this.empty, {super.key, this.collection});

  final DVEmpty empty;

  /// What is empty -- a data model's name, for a generated collection --
  /// which is what `DV-STATE-001` names.
  final String? collection;

  /// The collections already reported, so the diagnostic is one line per
  /// collection rather than one per frame.
  static final Set<String> _reported = <String>{};

  @override
  Widget build(BuildContext context) {
    // Nothing yet, and nothing offered to create the first one: the reader
    // is on a page with no way forward. It renders fine, which is why it is
    // a diagnostic rather than something anybody would notice.
    if (empty case DVNothingYet(action: null)) {
      final String name = collection ?? 'a collection';
      if (_reported.add(name)) {
        DV.log(
          'DV-STATE-001  $name is empty and declares no action to create '
          'the first one.',
          level: .info,
          tag: 'dartvel.state',
          code: 'DV-STATE-001',
          context: <String, Object?>{'collection': name},
        );
      }
    }
    final String text = empty.label ??
        DV.I18n.t(switch (empty) {
          DVNothingYet() => DVFrameworkStrings.nothingYet,
          DVNothingMatching() => DVFrameworkStrings.nothingMatching,
          DVNothingVisible() => DVFrameworkStrings.nothingVisible,
        });
    final Widget? action = switch (empty) {
      DVNothingYet(:final Widget? action) => action,
      DVNothingMatching(:final VoidCallback? onClear) => onClear == null
          ? null
          : TextButton(
              onPressed: onClear,
              child: Text(DV.I18n.t(DVFrameworkStrings.clearFilters)),
            ),
      DVNothingVisible() => null,
    };
    return Padding(
      padding: const .all(24),
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          Semantics(
            // Excluded, or the node carries the label twice -- once from here
            // and once from the Text under it -- and it is announced twice.
            excludeSemantics: true,
            label: text,
            child: Text(text, textAlign: .center),
          ),
          if (action != null) ...<Widget>[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    );
  }
}
