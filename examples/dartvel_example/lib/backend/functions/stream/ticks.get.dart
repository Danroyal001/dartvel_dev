import 'dart:async';
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction()
@pragma('vm:entry-point')
Stream<String> _getTicks() => createTicksStream();

Stream<String> createTicksStream() {
  final controller = StreamController<String>();
  int i = 0;
  Timer.periodic(const Duration(seconds: 1), (t) {
    i += 1;
    controller.add('tick $i');
    if (i >= 10) {
      t.cancel();
      controller.close();
    }
  });
  return controller.stream;
}
