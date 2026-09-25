/// Who may see a generated model page, and whether it may show them the
/// record's protected fields.
///
/// Every data model has a public page unless it opts out, so these two
/// questions are what stand between a record and the web. They are the
/// model's own policies under `DV.Auth.authorization`, asked the way every
/// other generated surface asks them, and they refuse whenever they cannot
/// reach an answer.
library;

import '../../dartvel.dart' show DVAuthAuthorization;
import '../auth/api_scopes.dart';

/// The policy questions a generated model page asks. The framework's, not
/// an application's: the generated page and the page resolver ask them, and
/// an application answers them by writing the model's policy.
class DVModelPageAccess {
  const DVModelPageAccess();

  /// Whether [viewer] may have [record]'s page at all. A refusal is answered
  /// as a record that does not exist -- 404, never 403 -- so a page cannot be
  /// used to learn that a record is there.
  ///
  /// A registered `<model>.view` policy decides. Without one, a model's
  /// records are public, because a model that did not opt out of pages has
  /// said so -- except where:
  ///
  /// - the record is [personal], a row that is its own privacy subject: a
  ///   person's record is nobody's to publish by default; or
  /// - a view policy is [declaredViewPolicy] somewhere this process cannot
  ///   load it, as a policy written against the generated client is to the
  ///   server. Reading that as "no policy" would publish every record the
  ///   policy exists to refuse.
  ///
  /// A policy that throws, or that cannot be asked with this viewer and
  /// record, refuses.
  Future<bool> mayView(
    String model,
    Object? viewer,
    Object? record, {
    bool personal = false,
    bool declaredViewPolicy = false,
  }) async {
    final String action = '$model.view';
    if (_registered(action)) return _ask(action, viewer, record);
    return !personal && !declaredViewPolicy;
  }

  /// Whether [viewer] may see [record]'s protected fields: its
  /// `@DVModel.sensitiveField()`s and the fields naming its privacy subject.
  ///
  /// Only a registered `<model>.viewSensitive` policy that admits [viewer]
  /// says yes. A model's view policy does not: letting anybody read an
  /// article is not letting anybody read its editor's notes.
  Future<bool> mayViewProtected(
    String model,
    Object? viewer,
    Object? record,
  ) async {
    final String action = '$model.viewSensitive';
    if (!_registered(action)) return false;
    return _ask(action, viewer, record);
  }

  static bool _registered(String action) => const DVAuthAuthorization()
      .registeredPolicies
      .contains(DVApiScopes.policyKeyOf(action));

  static Future<bool> _ask(String action, Object? viewer, Object? record) async {
    try {
      return await const DVAuthAuthorization()
          .canAction(viewer, action, resource: record);
    } on Object {
      // A policy that cannot reach its answer refuses.
      return false;
    }
  }
}
