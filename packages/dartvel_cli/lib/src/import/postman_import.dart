/// A Postman collection becoming Dartvel source.
///
/// An OpenAPI document is the tidy case. What people are handed, very often,
/// is somebody's Postman collection — the requests a team already makes,
/// exported from the tool they make them in. Reading it is the same job and
/// the same answer: ordinary files in the project rather than a runtime
/// dependency on the export.
///
/// It is a thinner document than a spec. A collection describes requests and
/// almost never describes types, so this produces calls and says so, rather
/// than inventing models out of whatever a single saved example happened to
/// contain.
library dartvel_cli.import.postman;

import 'dart:convert';

import 'import_names.dart';

/// What an import produced.
class DVPostmanImport {
  const DVPostmanImport({required this.sources, required this.problems});

  /// Path to Dart source.
  final Map<String, String> sources;

  /// What could not be read, or what the document does not carry.
  final List<String> problems;
}

/// Reads a Postman collection (schema v2 or v2.1).
///
/// Throws [FormatException] when the document is not JSON: "import failed"
/// against an export nobody has read is not something anybody can act on.
DVPostmanImport dvImportPostman(String document) {
  final Object? decoded;
  try {
    decoded = jsonDecode(document);
  } on FormatException catch (error) {
    throw FormatException(
      'A Postman collection is a JSON export: ${error.message}',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('A Postman collection is a JSON object.');
  }

  final List<String> problems = <String>[];
  final Object? info = decoded['info'];
  final String name = info is Map ? '${info['name'] ?? 'api'}' : 'api';

  final List<_Request> requests = <_Request>[];
  _collect(decoded['item'], requests, problems);

  if (requests.isEmpty) {
    problems.add('$name has no requests in it. A collection with only folders '
        'exports as one, and there is nothing to generate from it.');
    return DVPostmanImport(
      sources: const <String, String>{},
      problems: problems,
    );
  }

  // Said once, here, rather than left for somebody to discover by looking in
  // lib/models and finding nothing. A collection carries requests; it carries
  // types only by accident, in whatever example somebody last saved.
  problems.add('A Postman collection describes requests, not types, so no '
      'models were generated. Import an OpenAPI document for those, or write '
      'the @DVModel inputs by hand.');

  return DVPostmanImport(
    sources: <String, String>{
      'lib/api/${dvImportFileName(name)}.dart': _clientSource(name, requests),
    },
    problems: problems,
  );
}

/// One request, flattened out of the folders it was filed under.
class _Request {
  const _Request({
    required this.name,
    required this.verb,
    required this.path,
    required this.pathVariables,
    required this.query,
    required this.hasBody,
  });

  final String name;
  final String verb;

  /// The path with `:id` replaced by `$id`, ready to interpolate.
  final String path;
  final List<String> pathVariables;
  final List<String> query;
  final bool hasBody;
}

/// Walks the item tree. Folders nest, and a request three folders deep is
/// still a request the application makes.
void _collect(Object? items, List<_Request> into, List<String> problems) {
  if (items is! List) return;
  for (final Object? entry in items) {
    if (entry is! Map) continue;
    final Object? nested = entry['item'];
    if (nested is List) {
      _collect(nested, into, problems);
      continue;
    }
    final Object? request = entry['request'];
    if (request is! Map) continue;
    final _Request? parsed =
        _request('${entry['name'] ?? 'request'}', request, problems);
    if (parsed != null) into.add(parsed);
  }
}

_Request? _request(
  String name,
  Map<Object?, Object?> request,
  List<String> problems,
) {
  final String verb = '${request['method'] ?? 'GET'}'.toLowerCase();
  final Object? url = request['url'];

  final List<String> segments;
  final List<String> query = <String>[];
  if (url is Map) {
    final Object? path = url['path'];
    segments = <String>[
      if (path is List)
        for (final Object? segment in path) '$segment'
      else if (path is String)
        ...path.split('/').where((String part) => part.isNotEmpty),
    ];
    final Object? raw = url['query'];
    if (raw is List) {
      for (final Object? parameter in raw) {
        if (parameter is Map && parameter['key'] != null) {
          query.add('${parameter['key']}');
        }
      }
    }
  } else if (url is String) {
    segments = _segmentsOf(url);
  } else {
    problems.add('"$name" has no URL, so there is no request to write.');
    return null;
  }

  if (segments.isEmpty) {
    problems.add('"$name" has a URL with no path, so it was skipped.');
    return null;
  }

  // {{baseUrl}} and friends are Postman's environment, and the generated
  // client already knows where the API is. Left in, they produce a request to
  // a literal "{{baseUrl}}/books", which fails at run time and reads as a
  // network problem rather than as an import that did half a job.
  final List<String> variables = <String>[];
  final StringBuffer path = StringBuffer();
  for (final String segment in segments) {
    if (segment.startsWith('{{') && segment.endsWith('}}')) continue;
    path.write('/');
    if (segment.startsWith(':')) {
      final String variable = dvImportFieldName(segment.substring(1));
      variables.add(variable);
      path.write('\$$variable');
    } else {
      path.write(segment.replaceAllMapped(
        RegExp(r'\{\{([^}]+)\}\}'),
        (Match match) => '',
      ));
    }
  }

  return _Request(
    name: dvImportMethodName(name),
    verb: verb,
    path: path.toString(),
    pathVariables: variables,
    query: query,
    hasBody: request['body'] != null,
  );
}

List<String> _segmentsOf(String url) {
  final Uri? parsed = Uri.tryParse(url);
  if (parsed == null) return const <String>[];
  return parsed.pathSegments.where((String part) => part.isNotEmpty).toList();
}

String _clientSource(String name, List<_Request> requests) {
  final StringBuffer out = StringBuffer()
    ..writeln("import 'package:dartvel_core/dartvel.dart';")
    ..writeln()
    ..writeln('// Imported from the "$name" Postman collection: one function')
    ..writeln('// per request, calling the API the collection calls.')
    ..writeln('//')
    ..writeln('// These are ordinary functions. Annotate one with')
    ..writeln('// @DVBackendFunction to serve it from this application')
    ..writeln('// instead, or leave them as the client they are.')
    ..writeln('//')
    ..writeln('// A collection carries no types, so these answer with the')
    ..writeln('// decoded JSON. Give them a model when you have one.');

  final Set<String> claimed = <String>{};
  for (final _Request request in requests) {
    // Two requests can carry one name in Postman -- it is a label, not an
    // identifier -- and two Dart functions cannot.
    String name = request.name;
    for (int suffix = 2; !claimed.add(name); suffix++) {
      name = '${request.name}$suffix';
    }

    final List<String> arguments = <String>[
      for (final String variable in request.pathVariables) 'String $variable',
      if (request.hasBody) 'Object? body',
      if (request.query.isNotEmpty)
        '{${request.query.map((String q) => 'String? ${dvImportFieldName(q)}').join(', ')}}',
    ];

    out
      ..writeln()
      ..writeln('/// `${request.verb.toUpperCase()} ${request.path}`')
      ..writeln('Future<Object?> $name(${arguments.join(', ')}) async {');
    if (request.query.isEmpty) {
      out.writeln("  final DVHttpResponse response = "
          "await DV.Http.${request.verb}('${request.path}'"
          "${request.hasBody ? ', body: body' : ''});");
    } else {
      out
        ..writeln('  final Map<String, String> query = <String, String>{')
        ..writeln(request.query
            .map((String q) =>
                "    if (${dvImportFieldName(q)} != null) '$q': ${dvImportFieldName(q)},")
            .join('\n'))
        ..writeln('  };')
        ..writeln('  final String suffix = query.isEmpty')
        ..writeln("      ? ''")
        ..writeln("      : '?\${Uri(queryParameters: query).query}';")
        ..writeln("  final DVHttpResponse response = "
            "await DV.Http.${request.verb}('${request.path}\$suffix'"
            "${request.hasBody ? ', body: body' : ''});")
        ;
    }
    out
      ..writeln('  return response.json;')
      ..writeln('}');
  }
  return out.toString();
}
