/// Turning names from an imported document into Dart names.
///
/// Shared by every importer rather than copied into each. Two importers with
/// their own idea of what `order-line` becomes would produce two different
/// files from the same API, and the difference would only show up to whoever
/// imported the spec and the collection for the same service.
library dartvel_cli.import.names;

/// `order-line` as `OrderLine`.
String dvImportClassName(String name) {
  final List<String> parts = name
      .split(RegExp('[^A-Za-z0-9]'))
      .where((String part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'Model';
  return parts
      .map((String part) => part[0].toUpperCase() + part.substring(1))
      .join();
}

/// `order-line` as `order_line`, and `Catalog API` as `catalog_api`.
///
/// A break goes before an uppercase that follows a lowercase or digit, and
/// before the last uppercase of a run that is followed by a lowercase. Naively
/// breaking at every uppercase turned "Catalog API" into `catalog_a_p_i` --
/// the sort of name nobody would have typed and everybody would have to live
/// with. Real documents are full of API, HTTP, ID and URL.
String dvImportFileName(String name) {
  final String cleaned = dvImportClassName(name);
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < cleaned.length; i++) {
    final String character = cleaned[i];
    final bool upper = character != character.toLowerCase();
    if (upper && out.isNotEmpty) {
      final String previous = cleaned[i - 1];
      final bool afterLower = previous == previous.toLowerCase();
      final bool beforeLower = i + 1 < cleaned.length &&
          cleaned[i + 1] == cleaned[i + 1].toLowerCase();
      if (afterLower || beforeLower) out.write('_');
    }
    out.write(character.toLowerCase());
  }
  return out.toString();
}

/// `line-total` as `lineTotal`.
String dvImportFieldName(String name) {
  final String upper = dvImportClassName(name);
  return upper[0].toLowerCase() + upper.substring(1);
}

/// `get /health` as `getHealth`.
String dvImportMethodName(String name) => dvImportFieldName(name);
