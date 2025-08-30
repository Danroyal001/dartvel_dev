import 'dart:async';
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async {
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
  return Res.sse(controller.stream);
}
