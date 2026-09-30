/// The address fragment for a section heading: "Choose a search provider"
/// is `choose-a-search-provider`.
///
/// Plain Dart, because two sides use it: the search, on the server, links a
/// result to the section it matched, and a docs page, in the app, scrolls to
/// the section a fragment names. One function, so the two cannot spell a
/// heading differently.
String sectionAnchor(String heading) => heading
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
