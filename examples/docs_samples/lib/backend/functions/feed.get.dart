import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';

// docs:start privacy-opt-out
@DVBackendFunction()
Future<Map<String, Object?>> _feed() async {
  // The reader's browser sent `Sec-GPC: 1`, and every generated route reads
  // it before the handler runs. Consent categories declared `tracking: true`
  // are already denied while it is in force, so nothing here has to remember
  // to check that. This is for what the application decides on top: what it
  // personalises, and what it passes on to somebody else.
  if (dvPrivacyOptOut) {
    DV.log('Serving the unpersonalised feed', code: 'GPC');
    return <String, Object?>{'items': await popular(), 'personalised': false};
  }
  return <String, Object?>{'items': await recommended(), 'personalised': true};
}
// docs:end

Future<List<String>> popular() async => <String>['a', 'b'];
Future<List<String>> recommended() async => <String>['c', 'd'];
