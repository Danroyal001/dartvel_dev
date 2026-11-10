// The agent docs a project commits name where the installed Dartvel's own
// documentation is. Written with the machine's home directory in it, the path
// is wrong on every other machine, and the build's own conventions check
// (DV-CONV-017) flagged the file dartvel create had just written.
import 'package:dartvel_cli/src/agents/agent_docs.dart';
import 'package:test/test.dart';

void main() {
  test('a path under the home directory is written from ~', () {
    expect(
      dvPortableDocsPath('/home/ada/.pub-cache/hosted/pub.dev/dartvel_cli-0.13.31/docs', home: '/home/ada'),
      '~/.pub-cache/hosted/pub.dev/dartvel_cli-0.13.31/docs',
    );
    expect(dvPortableDocsPath('/Users/ada/.pub-cache/x/docs', home: '/Users/ada'), '~/.pub-cache/x/docs');
  });

  test('a path elsewhere, or a home that is only a prefix of a name, is left alone', () {
    expect(dvPortableDocsPath('/opt/dart/pub-cache/dartvel_cli/docs', home: '/home/ada'), '/opt/dart/pub-cache/dartvel_cli/docs');
    expect(dvPortableDocsPath('/home/adam/docs', home: '/home/ada'), '/home/adam/docs');
  });

  test('the rendered block carries no home directory', () {
    final String block = dvAgentBlock(
      version: '0.13.31',
      rules: 'Rules.',
      docsPath: dvPortableDocsPath('/home/ada/.pub-cache/hosted/pub.dev/dartvel_cli-0.13.31/docs', home: '/home/ada'),
    );
    expect(block, isNot(contains('/home/')));
    expect(block, contains('~/.pub-cache/hosted/pub.dev/dartvel_cli-0.13.31/docs'));
  });
}
