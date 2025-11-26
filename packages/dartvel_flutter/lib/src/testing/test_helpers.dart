// Testing utilities
import 'package:flutter_test/flutter_test.dart';

/// Mock HTTP client for testing
class MockHttpClient {
  final Map<String, dynamic> _responses = {};
  final List<String> _requestLog = [];

  void mockGet(String url, dynamic response) {
    _responses['GET:$url'] = response;
  }

  void mockPost(String url, dynamic response) {
    _responses['POST:$url'] = response;
  }

  void mockPut(String url, dynamic response) {
    _responses['PUT:$url'] = response;
  }

  void mockDelete(String url, dynamic response) {
    _responses['DELETE:$url'] = response;
  }

  Future<dynamic> get(String url) async {
    _requestLog.add('GET:$url');
    final response = _responses['GET:$url'];
    if (response is Exception) throw response;
    return response;
  }

  Future<dynamic> post(String url, {dynamic body}) async {
    _requestLog.add('POST:$url');
    final response = _responses['POST:$url'];
    if (response is Exception) throw response;
    return response;
  }

  List<String> get requestLog => List.unmodifiable(_requestLog);

  void clearLog() => _requestLog.clear();

  void reset() {
    _responses.clear();
    _requestLog.clear();
  }
}

/// Test helpers
class TestHelpers {
  /// Wait for async operations
  static Future<void> pumpAndSettle(WidgetTester tester,
      {Duration duration = const Duration(milliseconds: 100)}) async {
    await tester.pumpAndSettle(duration);
  }

  /// Find by text
  static Finder text(String text) => find.text(text);

  /// Find by key
  static Finder byKey(Key key) => find.byKey(key);

  /// Find by type
  static Finder byType<T>() => find.byType(T);

  /// Tap widget
  static Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Enter text
  static Future<void> enterText(
      WidgetTester tester, Finder finder, String text) async {
    await tester.enterText(finder, text);
    await tester.pumpAndSettle();
  }

  /// Scroll
  static Future<void> scroll(WidgetTester tester, Finder finder,
      {double delta = -300}) async {
    await tester.drag(finder, Offset(0, delta));
    await tester.pumpAndSettle();
  }
}

/// Mocknavigation observer
class MockNavigatorObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushedRoutes = [];
  final List<Route<dynamic>> poppedRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRoutes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    poppedRoutes.add(route);
  }

  void reset() {
    pushedRoutes.clear();
    poppedRoutes.clear();
  }
}

/// API test helpers
class ApiTestHelpers {
  static Map<String, dynamic> createUser({
    String id = '123',
    String email = 'test@example.com',
    String name = 'Test User',
  }) {
    return {
      'id': id,
      'email': email,
      'name': name,
    };
  }

  static Map<String, dynamic> createToken({
    String token = 'test_token',
    int expiresIn = 3600,
  }) {
    return {
      'token': token,
      'expiresIn': expiresIn,
    };
  }

  static Map<String, dynamic> createError({
    String message = 'Test error',
    int code = 400,
  }) {
    return {
      'error': {
        'message': message,
        'code': code,
      },
    };
  }
}
