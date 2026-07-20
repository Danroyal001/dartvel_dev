import 'package:dartvel_cli/src/templates/project_templates.dart';
import 'package:test/test.dart';

void main() {
  test('backend project templates emit strongly typed response maps', () {
    expect(ProjectTemplates.healthFunctionTemplate, isNot(contains('dynamic')));
    expect(ProjectTemplates.contactFormTemplate, isNot(contains('dynamic')));
    expect(ProjectTemplates.readmeTemplate('example'),
        isNot(contains('Map<String, dynamic>')));
  });
}
