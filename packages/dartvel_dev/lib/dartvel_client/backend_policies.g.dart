// GENERATED – do not edit.
// ignore_for_file: unused_import, unused_element, directives_ordering
library dartvel_client_backend_policies;

import 'package:dartvel_core/dartvel.dart';

/// Puts every policy the application declares into the
/// authorization registry.
///
/// Called before anything can ask a question of it. A
/// policy nobody registered is answered false, so the cost
/// of calling this late is a check that denies for a while
/// rather than one that throws.
void dartvelRegisterBackendPolicies() {
  // The application declares no @DVPolicy class.
}

/// How the offline replay route builds the class each
/// server-side policy takes from a record's values, so the
/// policy is asked about the model rather than a map.
final Map<String, Object? Function(Map<String, Object?>)>
    dartvelOfflineResources =
    <String, Object? Function(Map<String, Object?>)>{
};

String _dvString(Object? v) => v is String ? v : v == null ? throw ArgumentError.notNull('value') : '$v';
int _dvInt(Object? v) => v is int ? v : v is num ? v.toInt() : int.parse('$v');
double _dvDouble(Object? v) => v is num ? v.toDouble() : double.parse('$v');
bool _dvBool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';
DateTime _dvDateTime(Object? v) => v is DateTime ? v : DateTime.parse('$v');
