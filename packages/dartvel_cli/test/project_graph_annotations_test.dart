// The graph is what `dartvel inspect`, the framework MCP server and the
// documentation site all read, so a node it misreads is misread three times
// and agrees with itself everywhere -- which is what makes it look right.
import 'dart:io';

import 'package:dartvel_cli/src/graph/project_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<DartvelProjectGraph> _graphFor(Map<String, String> files) async {
  final Directory root = Directory.systemTemp.createTempSync('dv_graph_ann_');
  addTearDown(() => root.deleteSync(recursive: true));
  files.forEach((String relative, String contents) {
    final File file = File(
      p.joinAll(<String>[root.path, ...relative.split('/')]),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
  });
  return DartvelProjectGraph.build(root: root.path, pkgName: 'probe');
}

void main() {
  test('a field is sensitive whichever order its annotations stack in, and '
      'when the annotation takes arguments', () async {
    // The model generator already skips other annotations between a field
    // annotation and its `final`. The graph required the sensitive one to be
    // directly above it, with empty parentheses, so these were described to
    // an agent and to the documentation as ordinary fields.
    final DartvelProjectGraph graph = await _graphFor(<String, String>{
      'lib/models/user.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVModel()
class _User {
  @DVModel.sensitiveField()
  @DVModel.searchableField()
  final String taxId;

  @DVModel.searchableField()
  @DVModel.sensitiveField(encrypted: true)
  final String bankAccount;

  @DVModel.searchableField()
  final String email;

  const _User({required this.taxId, required this.bankAccount, required this.email});
}
''',
    });
    final Map<String, bool> sensitive = <String, bool>{
      for (final DVGraphField f in graph.models.single.fields)
        f.name: f.sensitive,
    };
    expect(sensitive, <String, bool>{
      'taxId': true,
      'bankAccount': true,
      'email': false,
    });
  });

  test('a backend function with middleware under its annotation is still the '
      'annotated function', () async {
    final DartvelProjectGraph graph = await _graphFor(<String, String>{
      'lib/backend/functions/checkout.post.dart': '''
import 'package:dartvel_core/dartvel.dart';

@DVBackendFunction(policy: DVPolicies.checkout)
@DVUseMiddleware([DVMiddlewares.tracing, DVMiddlewares.rateLimit])
Future<String> _charge(DVContext context, String basketId) async => basketId;
''',
    });
    final DVGraphFunction f = graph.functions.single;
    expect(f.name, 'charge');
    expect(f.annotated, isTrue);
    expect(f.source, 'lib/backend/functions/checkout.post.dart:3');
  });
}
