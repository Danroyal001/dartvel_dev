import 'package:dartvel_core/dartvel.dart';

// Exported from Dartvel Studio. Ordinary backend function:
// edit freely, the builder is no longer involved.
@DVBackendFunction()
@pragma('vm:entry-point')
Future<Object?> _notifyOwner(Object? email) => notifyOwnerBody(email);

Future<Object?> notifyOwnerBody(Object? email) async {
  final subject = 'Order shipped';
  if (email == true) {
    return subject;
  }
  return 'no recipient';
}
