// The studio's graph, as the backend actually served it.
//
// `dart tool/ci/studio_graph_check.dart <file> <key>...`
//
// The dashboard reads this at runtime. A build that wrote it and a server
// that served it are two different claims, and the second one is the one
// worth checking: everything around the admin -- the mount, the hidden
// answer, the file serving -- was built and working while nothing ever put
// a file in the directory it read from, so enabling the admin produced a
// 404 from a mount that was correct.
//
// Checks that the body parses as a JSON object and carries each named key as
// a list. Not that the lists have anything in them: a project can genuinely
// declare no jobs, and failing on that would make the check a description of
// this one site rather than of the contract.
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: studio_graph_check.dart <file> <key>...');
    exit(2);
  }

  final File file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('${file.path} is not there. The server answered nothing.');
    exit(1);
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (error) {
    stderr.writeln('${file.path} is not JSON: ${error.message}');
    exit(1);
  }

  if (decoded is! Map<String, Object?>) {
    stderr.writeln('${file.path} is a ${decoded.runtimeType}, not an object.');
    exit(1);
  }

  final List<String> missing = <String>[];
  for (final String key in args.skip(1)) {
    if (decoded[key] is! List) missing.add(key);
  }

  if (missing.isNotEmpty) {
    stderr.writeln('the served graph has no list for: ${missing.join(', ')}');
    stderr.writeln('it has: ${decoded.keys.join(', ')}');
    exit(1);
  }

  stdout.writeln('studio graph: ${args.skip(1).join(', ')} all present '
      '(${file.lengthSync()} bytes)');
}
