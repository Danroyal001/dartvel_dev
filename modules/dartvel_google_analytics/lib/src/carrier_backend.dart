import 'package:dartvel_core/dartvel.dart';

import 'runtime.dart';

/// Runs the operation named [operation] with the JSON [arguments] a client
/// sent, answering with JSON. Served by the application's backend at
/// `<apiBasePath>/_dv/modules/<id>/<operation>`.
///
/// One operation is carried here: `collect`, a device's event on its way to
/// the Measurement Protocol. Anything else is refused rather than run.
Future<Object?> dvModuleDispatch(
  String operation,
  Map<String, Object?> arguments,
) async {
  switch (operation) {
    case 'collect':
      return GoogleAnalyticsRuntime.instance.collect(arguments);
  }
  throw DVModuleRpcRefused(GoogleAnalyticsRuntime.instance.moduleId, operation,
      'the module does not carry it to the backend');
}
