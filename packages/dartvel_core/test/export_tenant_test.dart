// The tenant an export declares has to be the tenant its rows came from.
//
// DVExportOptions.tenantId was stored, written into the file's metadata, and
// read by nothing that decided which rows were written. So
// `User.Export.csv(users, options: DVExportOptions(tenantId: 'tenant_123'))`
// wrote whatever rows it was handed and stamped them tenant_123 -- a file
// that states a tenant it was never narrowed to. Next to it in the same
// object, policyFilter did narrow, which is what made the pair look like two
// filters instead of one filter and one label.
//
// An export cannot re-scope rows it was given: they were read before it was
// called, and the tenant column is not a field on the generated model. So the
// declared tenant is checked against the tenant the export is running as, and
// a mismatch is refused rather than labelled.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

class _Row {
  const _Row(this.name, {this.active = true});
  final String name;
  final bool active;
}

void main() {
  tearDown(DVTenants.reset);

  test('an export claiming a tenant it is not running as is refused', () {
    const DVExportOptions<_Row> options =
        DVExportOptions<_Row>(tenantId: 'tenant_123');

    const DVTenants().withTenant('acme', () {
      expect(
        () => options.apply(const <_Row>[_Row('a')]).toList(),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            allOf(contains('tenant_123'), contains('acme')),
          ),
        ),
      );
    });
  });

  test('an export claiming the tenant it is running as writes its rows', () {
    const DVExportOptions<_Row> options =
        DVExportOptions<_Row>(tenantId: 'acme');

    final List<String> names = const DVTenants().withTenant(
      'acme',
      () => options
          .apply(const <_Row>[_Row('a'), _Row('b')])
          .map((_Row row) => row.name)
          .toList(),
    );

    expect(names, <String>['a', 'b']);
  });

  test('the policy filter still narrows alongside the tenant check', () {
    // The two are separate questions and the tenant check must not have
    // replaced the one that already worked.
    final DVExportOptions<_Row> options = DVExportOptions<_Row>(
      tenantId: 'acme',
      policyFilter: (_Row row) => row.active,
    );

    final List<String> names = const DVTenants().withTenant(
      'acme',
      () => options
          .apply(const <_Row>[_Row('a'), _Row('b', active: false)])
          .map((_Row row) => row.name)
          .toList(),
    );

    expect(names, <String>['a']);
  });

  test('an export that declares no tenant is left alone', () {
    // Most applications have one tenant and never name it. Refusing those
    // would make the honest call the one that fails.
    const DVExportOptions<_Row> options = DVExportOptions<_Row>();

    expect(options.apply(const <_Row>[_Row('a')]).length, 1);
  });
}
