// GENERATED – do not edit.
// ignore_for_file: unused_import, unused_element, directives_ordering
library dartvel_client_policies;

import 'package:dartvel_core/dartvel.dart';

/// Puts every policy the application declares into the
/// authorization registry.
///
/// Called before anything can ask a question of it. A
/// policy nobody registered is answered false, so the cost
/// of calling this late is a check that denies for a while
/// rather than one that throws.
void dartvelRegisterPolicies() {
  // The application declares no @DVPolicy class.
}
