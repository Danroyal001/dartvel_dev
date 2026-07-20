import 'package:dartvel_flutter/src/routing/advanced_routing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('route groups and metadata expose typed values', () {
    final group = RouteGroup(
      prefix: '/admin',
      routes: <RouteBase>[
        GoRoute(
          path: '/users',
          builder: (BuildContext context, GoRouterState state) =>
              const SizedBox.shrink(),
        ),
      ],
    );
    const metadata = RouteMeta(
      name: 'users',
      data: <String, Object?>{'requiresAudit': true},
    );

    expect(group.routes, hasLength(1));
    expect(metadata.data['requiresAudit'], isTrue);
  });
}
