/// What a page's generated widget is called, and what a page file declares.
///
/// One definition, because two would drift: the parent of a mounted module
/// names the class the module's own generator made, and a second copy of
/// the rule would have it importing a name that is not there.
library;

/// The class name generated for the page whose entrypoint is [symbol].
String dvGeneratedPageWidgetName(String symbol) {
  final List<String> words = RegExp(r'[A-Za-z0-9]+')
      .allMatches(symbol)
      .map((RegExpMatch match) => match.group(0)!)
      .where((String word) => word.isNotEmpty)
      .toList();
  final String pascalName =
      words.map((String word) => word[0].toUpperCase() + word.substring(1)).join();
  final String baseName = pascalName.isEmpty ? 'Generated' : pascalName;
  return '${baseName}GeneratedPage';
}

/// The page entrypoint [source] declares: a class extending DartvelPage or
/// DVClassWidget, else an `@DVPage` function. Null when it declares neither,
/// which is a file under the pages directory that is not a page.
String? dvPageSymbol(String source) {
  final RegExpMatch? asClass = RegExp(
    r'(?:@DVPage\([^)]*\)\s*)?(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+(?:DartvelPage|DVClassWidget)',
  ).firstMatch(source);
  if (asClass != null) return asClass.group(1);

  final RegExpMatch? asFunction = RegExp(
    r'@DVPage\([^)]*\)\s*(?:@pragma\([^)]*\)\s*)*(?:@DVFunctionalWidget\(\)\s*)?Widget\s+([A-Za-z_][A-Za-z0-9_]*)\(',
  ).firstMatch(source);
  return asFunction?.group(1);
}
