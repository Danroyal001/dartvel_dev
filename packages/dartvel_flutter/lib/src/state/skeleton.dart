/// The skeleton of a card list or grid whose records are on their way.
///
/// Error, Empty, and Loading States: skeletons are derived from the model's
/// field layout, so the placeholder is the shape of what is coming rather than
/// a spinner. A generated `Model.List(null)` or card grid knows its fields
/// before it has records, and draws one card per placeholder with one line
/// per field. Loading is not empty, so it never says "nothing here yet".
library;

import 'package:dartvel_flutter/dartvel_flutter.dart'
    show DV, DVFrameworkStrings;
import 'package:flutter/material.dart';

/// Placeholder cards for a loading list ([columns] null) or grid.
class DVSkeletonCards extends StatelessWidget {
  const DVSkeletonCards({
    super.key,
    required this.fields,
    this.count = 3,
    this.columns,
  });

  /// The fields each card will show, in order: one placeholder line each.
  final List<String> fields;

  /// How many placeholder cards.
  final int count;

  /// The grid's columns, or null for a list.
  final int? columns;

  @override
  Widget build(BuildContext context) {
    final List<Widget> cards = <Widget>[
      for (int i = 0; i < count; i += 1) _SkeletonCard(fields: fields),
    ];
    final int? across = columns;
    final Widget body = across == null || across <= 1
        ? Column(crossAxisAlignment: .stretch, mainAxisSize: .min, children: cards)
        : Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: .min,
            children: <Widget>[
              for (int start = 0; start < cards.length; start += across)
                Row(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    for (int i = start; i < start + across; i += 1)
                      Expanded(child: i < cards.length ? cards[i] : const SizedBox.shrink()),
                  ],
                ),
            ],
          );
    // Announced once, as loading; a placeholder is not a record, and nobody
    // should hear a list of grey bars read out one by one.
    return Semantics(
      container: true,
      liveRegion: true,
      label: DV.I18n.t(DVFrameworkStrings.collectionLoading),
      excludeSemantics: true,
      child: body,
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({required this.fields});

  final List<String> fields;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const .all(12),
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: <Widget>[
              for (int i = 0; i < fields.length; i += 1)
                // The first line is the title's, and wider: the shape of a
                // card is a heading over its details.
                DVSkeletonLine(widthFactor: i == 0 ? 0.7 : 0.45),
            ],
          ),
        ),
      );
}

/// One placeholder line of a skeleton card, as its own type so a test can
/// count them.
class DVSkeletonLine extends StatelessWidget {
  const DVSkeletonLine({super.key, this.widthFactor = 0.5});

  /// How much of the card's width the line takes.
  final double widthFactor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const .symmetric(vertical: 6),
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: widthFactor,
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
              borderRadius: .circular(4),
            ),
          ),
        ),
      );
}
