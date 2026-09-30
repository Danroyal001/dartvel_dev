import 'package:dartvel_core/dartvel.dart';

/// One section of one page of this site, as the site search reads it.
///
/// Written by the search itself from the pages the server serves
/// (`DVSitePages.load()`), so there is nothing to keep in step by hand: a
/// page that changes is a section that changes the next time the server
/// starts. Searchable, for the keyword half of the search, and semantic, for
/// the half that searches by meaning.
///
/// No public page per record: a section is reached on the page it is part of.
@DVModel(searchable: true, semantic: true, generatePublicPages: false)
class const _SitePage({
  /// The page's path and the section's position on it: `/docs/cache#2`.
  required final String id,

  /// Where the section is: `/docs/cache`.
  required final String path,

  /// The page's title.
  @DVModel.searchableField() required final String title,

  /// The section's heading, or the page's own for its first section.
  @DVModel.searchableField() required final String heading,

  /// What the section says.
  @DVModel.searchableField() required final String body,
});
