/// Joining the pieces of the generated router's route list.
///
/// The list is built from four blocks -- the pages, the model pages, the home
/// widgets and the mounted modules -- any of which may be empty, and the
/// entries in some of them end in a comma while the entries in others do not.
///
/// Each block used to be responsible for putting a separator in front of
/// itself, and each one got it right on its own. Two of them present at once
/// emitted a comma after a block that already ended in one:
///
/// ```
///     ),
///     ,
///         GoRoute(
/// ```
///
/// which the compiler reports as `Expected an identifier, but got ','`
/// against a file nobody wrote. It survived because no project in the
/// repository had both a model page and a home widget, so two blocks were
/// never both present in a build.
library;

/// [blocks] as one route list, with a separator only where one is missing.
///
/// Empty blocks contribute nothing -- not an empty line and not a separator.
/// An empty block that still contributed its comma is how the stray one got
/// there in the first place.
String dvJoinRouteBlocks(List<String> blocks) {
  final List<String> present = <String>[
    for (final String block in blocks)
      if (block.trim().isNotEmpty) block,
  ];
  if (present.isEmpty) return '';

  final StringBuffer out = StringBuffer(present.first);
  for (final String block in present.skip(1)) {
    // The last character that is not whitespace: blocks are joined with
    // newlines and some arrive with a line ending after the final comma, so
    // a rule reading the final character alone would add a second one.
    out
      ..write(out.toString().trimRight().endsWith(',') ? '\n' : ',\n')
      ..write(block);
  }
  return out.toString();
}
