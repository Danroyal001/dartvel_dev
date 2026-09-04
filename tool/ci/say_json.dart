/// Prints named fields of a JSON document, for a CI step that wants to say
/// what it found.
///
///     dart tool/ci/say_json.dart overview.json 'RabbitMQ' rabbitmq_version
///
/// Every argument after the file is either a literal to print or the name of
/// a top-level field to read. A field that is not there prints `?` rather
/// than failing: the step that calls this has already decided the service is
/// up, and a health line is not the place to fail a job.
///
/// Dart because everything else in this repository's CI is: a second language
/// for three lines of JSON is a second thing to install, to pin and to read.
library;

import 'dart:convert';
import 'dart:io';

int main(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln('usage: say_json.dart <file.json> [word|field ...]');
    return 2;
  }
  final File file = File(arguments.first);
  if (!file.existsSync()) {
    stderr.writeln('${arguments.first} is not there');
    return 1;
  }
  final Object? document = jsonDecode(file.readAsStringSync());
  final Map<String, Object?> fields =
      document is Map<String, Object?> ? document : const <String, Object?>{};

  stdout.writeln(<String>[
    for (final String word in arguments.skip(1))
      fields.containsKey(word) ? '${fields[word]}' : word,
  ].join(' '));
  return 0;
}
