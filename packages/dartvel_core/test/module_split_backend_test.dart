// A module whose backend is deployed separately.
//
// split-backend is the mode where the module's UI ships inside the parent and
// its backend functions run as their own service. The parent compiles the
// pages in exactly as it would an embedded module, so everything looks
// identical -- and every call the module makes goes to the parent's API,
// which does not serve those functions.
//
// That is the failure this guards: not a crash, a 404 from an application
// that was built and deployed and looks right.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVModuleRegistry modules;

  setUp(() => modules = DVModuleRegistry());

  test('a module deployed with its own backend says where it is', () {
    modules.register(
      id: 'store',
      mountPath: '/store',
      config: const <String, Object?>{
        'deployment': 'split-backend',
        'backend': 'https://store-api.example.com',
      },
    );

    expect(modules('store').apiBase,
        'https://store-api.example.com');
  });

  test('a module whose backend is the parent\'s says nothing', () {
    // Null rather than the parent's address: the caller falls back to its own
    // base, and a module that answered with the parent's would make the two
    // cases indistinguishable to anything reading it.
    modules.register(
      id: 'store',
      mountPath: '/store',
      config: const <String, Object?>{'deployment': 'embedded'},
    );

    expect(modules('store').apiBase, isNull);
  });

  test('an empty backend is no backend', () {
    modules.register(
      id: 'store',
      mountPath: '/store',
      config: const <String, Object?>{'backend': '   '},
    );

    expect(modules('store').apiBase, isNull);
  });
}
