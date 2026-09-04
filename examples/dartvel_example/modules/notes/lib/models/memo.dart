import 'package:dartvel_core/dartvel.dart';

/// A note the module keeps.
///
/// The module is mounted schema-isolated, so this table is in the
/// application's database under the module's own name rather than beside
/// the application's own models. Nothing here says so: the mode is the
/// parent's decision, and the same module mounted shared, or standing alone
/// as its own application, is this file unchanged.
@DVModel()
@pragma('vm:entry-point')
class _Memo {
  final String id;
  final String title;
  final String body;

  const _Memo({required this.id, required this.title, required this.body});
}
