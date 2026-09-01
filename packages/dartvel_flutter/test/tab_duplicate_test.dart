// Two tabs on one route, and the one case where that is wanted.
//
// The contract: "a route already open as a tab focuses that tab; a deliberate
// second tab says DVTab(route, duplicate: true), mirroring open()". The first
// half was written and did not work. add() deduplicated with
// _tabs.indexOf(tab), and DVTab overrides no ==, so indexOf compared by
// identity -- two DVTab objects naming the same route were never equal, and
// every add appended.
//
// Nothing caught it because a test that reuses one DVTab instance passes
// either way, and reusing the instance is the natural thing to write.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DVTabWorkspaceController controller;

  setUp(() => controller = DVTabWorkspaceController(
        tabs: <DVTab>[
          const DVTab(DVRouteTarget('/orders')),
          const DVTab(DVRouteTarget('/customers')),
        ],
      ));

  group('a route already open', () {
    test('focuses its tab rather than adding another', () {
      // A separate object naming the same route, which is what a second
      // navigation actually produces.
      controller.add(const DVTab(DVRouteTarget('/orders')));

      expect(controller.tabs, hasLength(2));
      expect(controller.activeIndex, 0);
    });

    test('even when the label differs', () {
      // Identity is the route. A different label is a different presentation
      // of the same page, not a second page.
      controller.add(
          const DVTab(DVRouteTarget('/customers'), label: 'Client list'));

      expect(controller.tabs, hasLength(2));
      expect(controller.tabs[1].title, 'customers',
          reason: 'the tab that was already there is untouched');
      expect(controller.activeIndex, 1);
    });

    test('a genuinely new route is added', () {
      controller.add(const DVTab(DVRouteTarget('/reports')));
      expect(controller.tabs, hasLength(3));
      expect(controller.activeIndex, 2);
    });
  });

  group('a deliberate second tab', () {
    test('duplicate: true adds one on the same route', () {
      controller.add(const DVTab(DVRouteTarget('/orders'), duplicate: true));

      expect(controller.tabs, hasLength(3));
      expect(
          controller.tabs.where((DVTab t) => t.route.path == '/orders'),
          hasLength(2));
      expect(controller.activeIndex, 2);
    });

    test('and does not itself become a magnet for later adds', () {
      // Two /orders tabs exist; a third plain add must still focus rather
      // than append, or duplicate: true would quietly change the rule for
      // every later navigation to that route.
      controller.add(const DVTab(DVRouteTarget('/orders'), duplicate: true));
      controller.add(const DVTab(DVRouteTarget('/orders')));

      expect(controller.tabs, hasLength(3));
    });

    test('duplicate is false by default, mirroring open()', () {
      expect(const DVTab(DVRouteTarget('/a')).duplicate, isFalse);
    });
  });

  group('closing one of a duplicated pair', () {
    test('leaves the other', () {
      controller.add(const DVTab(DVRouteTarget('/orders'), duplicate: true));

      controller.removeAt(2);

      expect(
          controller.tabs.where((DVTab t) => t.route.path == '/orders'),
          hasLength(1));
    });
  });
}
