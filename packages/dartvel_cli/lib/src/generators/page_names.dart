/// What a page's generated widget is called, and what a page file declares.
///
/// One definition, because two would drift: the parent of a mounted module
/// names the class the module's own generator made, and a second copy of
/// the rule would have it importing a name that is not there.
library;

import 'annotation_args.dart';

/// The class name generated for the page whose entrypoint is [symbol].
String dvGeneratedPageWidgetName(String symbol) {
  final List<String> words = RegExp(r'[A-Za-z0-9]+')
      .allMatches(symbol)
      .map((RegExpMatch match) => match.group(0)!)
      .where((String word) => word.isNotEmpty)
      .toList();
  final String pascalName = words
      .map((String word) => word[0].toUpperCase() + word.substring(1))
      .join();
  final String baseName = pascalName.isEmpty ? 'Generated' : pascalName;
  return '${baseName}GeneratedPage';
}

/// The page entrypoint [source] declares: a class extending DartvelPage or
/// DVClassWidget, else an `@DVPage` function. Null when it declares neither,
/// which is a file under the pages directory that is not a page.
///
/// Matched against a copy whose annotation arguments have been flattened,
/// because the pattern steps over `@DVPage(...)` to reach the declaration
/// under it and `[^)]*` stops inside a nested call -- so a page whose
/// annotation carried `sitemap: DVPageSitemap(...)` was not a page at all,
/// and its route was missing from the router with nothing said.
String? dvPageSymbol(String source) {
  final String flat = dvMaskAnnotationArgs(source, 'DVPage');

  final RegExpMatch? asClass = RegExp(
    r'(?:@DVPage\([^)]*\)\s*)?(?:@pragma\([^)]*\)\s*)*class\s+([A-Za-z_][A-Za-z0-9_]*)\s+extends\s+(?:DartvelPage|DVClassWidget)',
  ).firstMatch(flat);
  if (asClass != null) return asClass.group(1);

  final RegExpMatch? asFunction = RegExp(
    r'@DVPage\([^)]*\)\s*(?:@pragma\([^)]*\)\s*)*(?:@DVFunctionalWidget\(\)\s*)?Widget\s+([A-Za-z_][A-Za-z0-9_]*)\(',
  ).firstMatch(flat);
  return asFunction?.group(1);
}
