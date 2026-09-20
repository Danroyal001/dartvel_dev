import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';

// docs:start backend-lifecycle
@DVBackendFunction()
Future<Map<String, Object?>> _getExport(DVContext context, String id) async {
  final DVLifecycleSignal<DVRequestLifecycle> request = context.lifecycle.request;
  request.listen((DVRequestLifecycle state) {
    if (state == DVRequestLifecycle.failed) {
      DV.log('export $id failed', level: DVLogLevel.warn);
    }
  });
  return <String, Object?>{'id': id, 'stage': request.value.name};
}
// docs:end
