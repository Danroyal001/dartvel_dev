// The scaffolded admin is guarded.
//
// `dartvel admin` generated eight pages -- studio, models, queues, cache,
// routes, outbox, policies, telemetry -- as plain @DVPage functions with no
// guard, no policy and no role between them and anybody who could load the
// application. The Studio one is the page builder, and the router prefers a
// stored Studio document over the compiled page by design, so an unguarded
// builder is a site anybody can rewrite.
//
// They carry a policy now, and the guard behind it refuses when the
// application has configured nothing to answer with. That order matters: a
// policy that defaulted to allow would be an annotation that looks like a
// guard, which is the bug this repository just spent a commit removing from
// @DVPage.
import 'package:dartvel_cli/src/commands/admin_command.dart';
import 'package:test/test.dart';

void main() {
  group('every generated admin page', () {
    test('declares a policy', () {
      // Not some of them. The index is as sensitive as the pages it links
      // to, and an unguarded telemetry page reads out the same tenants.
      final Map<String, String> pages = dvAdminScaffoldPages();

      expect(pages, isNotEmpty);
      for (final MapEntry<String, String> page in pages.entries) {
        expect(page.value, contains('policy:'),
            reason: '${page.key} has no policy on its @DVPage');
      }
    });

    test('declares the admin policy, not one of its own', () {
      // Eight different policy names would be eight things to register
      // before the dashboard works, which is how somebody ends up
      // registering an allow-everything one.
      for (final MapEntry<String, String> page
          in dvAdminScaffoldPages().entries) {
        expect(page.value, contains('DVPolicies.viewAdmin'),
            reason: page.key);
      }
    });

    test('still sits under the admin path it always did', () {
      // The guard is the change; the routes are not. An application with
      // links to these pages keeps them.
      for (final MapEntry<String, String> page
          in dvAdminScaffoldPages().entries) {
        expect(page.value, contains('/_dartvel_admin'), reason: page.key);
      }
    });
  });
}
