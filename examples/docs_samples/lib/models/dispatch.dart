import 'package:dartvel_core/dartvel.dart';

// docs:start offline-model
// A data model that has to work with no network says so, and says how a
// write made offline is resolved when it reaches the server. Nothing else
// is declared: the device keeps its own copy and a queue, and the server
// applies what the device sends, both from this declaration.
@DVModel(offline: DVConflict.lastWriteWins)
class const _Dispatch({
  required final String id,
  required final String reference,
  required final int quantity,
});
// docs:end
