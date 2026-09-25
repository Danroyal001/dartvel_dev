import '../dartvel_client/dartvel_client.dart';

// In a file of its own because generated widgets take it as a parameter, and
// the generated widget file sees the types of the files a component imports.
/// One docs page: where it lives, what it is called, and its group.
class const DocsPageInfo(
  final DVRouteTarget target,
  final String title,

  /// A line for the index and the pager.
  final String summary,
  final String group,
) {
  String get path => target.path;
}
