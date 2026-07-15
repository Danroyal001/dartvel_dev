import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async {
  final name = req.params['name'] ?? 'unknown';
  final path = p.join(Directory.current.path, '.data', 'storage', name);
  final f = File(path);
  if (!f.existsSync()) return Res.notFound('no such file');
  final bytes = await f.readAsBytes();
  return Res.bytes(bytes,
      headers: {'content-type': 'application/octet-stream'});
}
