import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

// Applications declare what a product grants as a const set. A const set
// takes only elements with primitive equality, so an operator == on
// Entitlement stops every such app from compiling; this file is the check.
const Entitlement pro = Entitlement('pro');
const Entitlement exports = Entitlement('exports');
const Set<Entitlement> declared = <Entitlement>{pro, exports};

void main() {
  test('entitlements can be declared in a const set', () {
    expect(declared.map((entitlement) => entitlement.id), <String>['pro', 'exports']);
  });
}
