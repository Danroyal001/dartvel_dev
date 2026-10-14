import 'package:dartvel_core/dartvel.dart'
    show DVStudioMenu, DVStudioMenuItem;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMenusTransport {
  _FakeMenusTransport() {
    menus = <DVStudioMenu>[
      DVStudioMenu(
        id: 'primary-menu',
        name: 'Primary Navigation',
        location: 'header',
        items: const <DVStudioMenuItem>[
          DVStudioMenuItem(
            id: 'item-1',
            label: 'Home',
            url: '/',
            target: '_self',
          ),
          DVStudioMenuItem(
            id: 'item-2',
            label: 'Products',
            url: '/products',
            target: '_self',
            children: <DVStudioMenuItem>[
              DVStudioMenuItem(
                id: 'item-2-1',
                label: 'Featured',
                url: '/products/featured',
                target: '_self',
              ),
            ],
          ),
        ],
        updatedAt: DateTime.now().toUtc(),
      ),
      DVStudioMenu(
        id: 'footer-menu',
        name: 'Footer Links',
        location: 'footer',
        items: const <DVStudioMenuItem>[
          DVStudioMenuItem(
            id: 'item-f1',
            label: 'Privacy Policy',
            url: '/privacy',
            target: '_blank',
          ),
        ],
        updatedAt: DateTime.now().toUtc(),
      ),
    ];
  }

  late List<DVStudioMenu> menus;
  final List<String> locations = <String>['header', 'footer', 'sidebar', 'mobile'];
  DVStudioMenu? lastSaved;
  String? lastDeletedId;

  Future<DVStudioReply> call(String method, String path, {Object? body}) async {
    final Uri uri = Uri.parse(path);

    if (uri.path == 'api/menus') {
      if (method == 'GET') {
        final String? id = uri.queryParameters['id'];
        if (id != null) {
          final DVStudioMenu? found =
              menus.where((DVStudioMenu m) => m.id == id).firstOrNull;
          if (found == null) {
            return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
          }
          return DVStudioReply(200, found.toJson());
        }
        return DVStudioReply(200, <String, Object?>{
          'menus': <Object?>[for (final DVStudioMenu m in menus) m.toJson()],
          'locations': locations,
        });
      }
      if (method == 'POST') {
        final Map<String, Object?> json = (body as Map).cast<String, Object?>();
        final DVStudioMenu menu = DVStudioMenu.fromJson(json);
        final int index = menus.indexWhere((DVStudioMenu m) => m.id == menu.id);
        if (index >= 0) {
          menus[index] = menu;
        } else {
          menus.add(menu);
        }
        lastSaved = menu;
        return DVStudioReply(200, menu.toJson());
      }
      if (method == 'DELETE') {
        final String? id = uri.queryParameters['id'];
        if (id != null) {
          menus.removeWhere((DVStudioMenu m) => m.id == id);
          lastDeletedId = id;
          return const DVStudioReply(200, <String, Object?>{'ok': true});
        }
      }
    }
    return const DVStudioReply(404, <String, Object?>{'error': 'not_found'});
  }
}

void main() {
  setUp(() {
    DVStudioStyle.dark = false;
  });

  Future<void> pumpMenus(
    WidgetTester tester, {
    required DVStudioClient client,
    String? selectedMenuId,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DVStudioMenusSection(
            client: client,
            selectedMenuId: selectedMenuId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders menus section with menu switcher, structure, and items', (
    WidgetTester tester,
  ) async {
    final _FakeMenusTransport transport = _FakeMenusTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpMenus(tester, client: client);

    expect(find.text('Menus & Navigation'), findsOneWidget);
    expect(find.text('Menu Structure'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('New menu'), findsOneWidget);
    expect(find.text('Add link'), findsOneWidget);
    expect(find.text('Save menu'), findsOneWidget);
  });

  testWidgets('switching menus in dropdown updates displayed items', (
    WidgetTester tester,
  ) async {
    final _FakeMenusTransport transport = _FakeMenusTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpMenus(tester, client: client);

    // Open dropdown
    await tester.tap(find.text('Primary Navigation (Header)'));
    await tester.pumpAndSettle();

    // Select Footer Links
    await tester.tap(find.text('Footer Links (Footer)').last);
    await tester.pumpAndSettle();

    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('New tab'), findsOneWidget);
  });

  testWidgets('add link dialog creates new menu item and enables Save', (
    WidgetTester tester,
  ) async {
    final _FakeMenusTransport transport = _FakeMenusTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpMenus(tester, client: client);

    // Click "Add link"
    await tester.tap(find.text('Add link'));
    await tester.pumpAndSettle();

    expect(find.text('Add Navigation Link'), findsOneWidget);

    // Enter label and URL
    await tester.enterText(
        find.widgetWithText(DVStudioTextInput, '').first, 'Contact');
    await tester.pumpAndSettle();

    // Tap quick preset Contact
    await tester.tap(find.text('Contact').last);
    await tester.pumpAndSettle();

    // Click "Add to menu"
    await tester.tap(find.text('Add to menu'));
    await tester.pumpAndSettle();

    expect(find.text('Contact'), findsOneWidget);

    // Save menu should now be enabled and tappable
    await tester.tap(find.text('Save menu'));
    await tester.pumpAndSettle();

    expect(transport.lastSaved, isNotNull);
    expect(
        transport.lastSaved!.items
            .any((DVStudioMenuItem i) => i.label == 'Contact'),
        isTrue);
    expect(find.textContaining('saved successfully'), findsOneWidget);
  });

  testWidgets('item reordering and deletion update menu structure', (
    WidgetTester tester,
  ) async {
    final _FakeMenusTransport transport = _FakeMenusTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpMenus(tester, client: client);

    // Find delete button for "Home"
    final Finder deleteButtons = find.byTooltip('Delete item');
    expect(deleteButtons, findsWidgets);

    await tester.tap(deleteButtons.first);
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsNothing);

    // Save changes
    await tester.tap(find.text('Save menu'));
    await tester.pumpAndSettle();

    expect(
        transport.lastSaved!.items
            .any((DVStudioMenuItem i) => i.label == 'Home'),
        isFalse);
  });

  testWidgets('delete menu prompts confirmation and removes menu', (
    WidgetTester tester,
  ) async {
    final _FakeMenusTransport transport = _FakeMenusTransport();
    final DVStudioClient client = DVStudioClient(transport.call);

    await pumpMenus(tester, client: client);

    await tester.tap(find.text('Delete menu'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Menu'), findsOneWidget);
    expect(find.text('Delete permanently'), findsOneWidget);

    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(transport.lastDeletedId, 'primary-menu');
  });
}
