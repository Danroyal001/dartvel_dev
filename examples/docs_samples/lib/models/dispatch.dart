import 'package:dartvel_core/dartvel.dart';

// docs:start offline-model
// A data model that has to work with no network says so, and says how a
// write made offline is resolved when it reaches the server. Nothing else
// is declared: the device keeps its own copy and a queue, and the server
// applies what the device sends, both from this declaration.
@DVModel(offline: DVConflict.lastWriteWins)
class _Dispatch {
  final String id;
  final String reference;
  final int quantity;

  const _Dispatch({
    required this.id,
    required this.reference,
    required this.quantity,
  });
}
// docs:end
