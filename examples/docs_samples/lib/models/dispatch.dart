import 'package:dartvel_core/dartvel.dart';

// docs:start offline-model
// A data model that has to work with no network says so, and says how a
// write made offline is resolved when it reaches the server. The local
// store and the server side both come from the table, key and columns
// declared here.
@DVModel(offline: DVConflict.lastWriteWins)
class const _Dispatch({
  required final String id,
  required final String reference,
  required final int quantity,
});
// docs:end
