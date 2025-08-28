
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(Request req) async {
  return Res.json({'ok': true, 'hello': 'world'});
}
