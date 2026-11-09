// docs:start backend-refusal
// lib/backend/functions/wallets.post.dart is served at POST /api/wallets.
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
Future<String> _wallets(String address) async {
  if (address.startsWith('0x')) {
    // Answers 422 with {"error": "..."}; the reader is shown the message.
    throw const DVRefusal(
        'That looks like an Ethereum address. Paste a TRON (TRC-20) one.');
  }
  if (address.length != 34) {
    throw const DVRefusal('A TRON address is 34 characters.');
  }
  return address;
}
// docs:end
