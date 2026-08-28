/// Reading `docs/spec-status.json`.
///
/// The file carries two independent labels per section: `stability` (how much
/// the surface can still move) and `status` (how much is built). A frozen
/// contract that is deliberately unbuilt is the scope rule working, so the
/// pair matters more than either alone.
class SpecStatusSummary {
  const SpecStatusSummary({
    required this.total,
    required this.labelled,
    required this.shipped,
    required this.partial,
    required this.designed,
    required this.unbuiltContracts,
  });

  /// Every section in the index, including narrative headings.
  final int total;

  /// Sections carrying a status. A narrative heading is not an unbuilt
  /// feature, and counting it as one makes the totals argue for work that
  /// does not exist.
  final int labelled;

  final int shipped;
  final int partial;
  final int designed;

  /// Sections whose surface is frozen and whose implementation is not
  /// finished. The number worth surfacing: one is the scope rule working,
  /// fourteen is a decision someone should be making on purpose.
  final List<String> unbuiltContracts;
}

/// Summarise a decoded `docs/spec-status.json` section list.
SpecStatusSummary specStatusSummary(List<Map<String, Object?>> sections) {
  var shipped = 0;
  var partial = 0;
  var designed = 0;
  var labelled = 0;
  final unbuilt = <String>[];

  for (final Map<String, Object?> section in sections) {
    final status = section['status'];
    if (status == null) continue;
    labelled++;
    switch (status) {
      case 'Shipped':
        shipped++;
      case 'Partial':
        partial++;
      case 'Designed':
        designed++;
    }
    if (status != 'Shipped' && section['stability'] == 'Contract') {
      unbuilt.add('${section['section']}');
    }
  }

  return SpecStatusSummary(
    total: sections.length,
    labelled: labelled,
    shipped: shipped,
    partial: partial,
    designed: designed,
    unbuiltContracts: unbuilt,
  );
}
