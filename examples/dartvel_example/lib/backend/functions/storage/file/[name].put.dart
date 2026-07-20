import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:dartvel_core/dartvel.dart';

Future<ResponseType> handler(RequestType req) async {
  final name = req.params['name'] ?? 'file.bin';
  final dir = Directory(p.join(Directory.current.path, '.data', 'storage'))
    ..createSync(recursive: true);
  final file = File(p.join(dir.path, name));
  final bytes = await req.body.bytes();
  await file.writeAsBytes(bytes, flush: true);
  return Res.json({'ok': true, 'name': name});
}
