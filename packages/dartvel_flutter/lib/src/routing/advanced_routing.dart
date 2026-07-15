// Advanced routing features: route groups, nested layouts, catch-all
import 'dart:async';

import 'package:flutter/widgets.dart';
import '../../dartvel_flutter.dart';

/// Route group configuration
/// Note: RouteBase is from go_router package
class RouteGroup {
  final String prefix;
  final List<dynamic>
      routes; // Using dynamic to avoid go_router dependency here
  final List<NavigatorObserver>? observers;
  final String? redirect;
  final Widget Function(BuildContext, Widget)? wrapper;

  const RouteGroup({
    required this.prefix,
    required this.routes,
    this.observers,
    this.redirect,
    this.wrapper,
  });
}

/// Route metadata
class RouteMeta {
  final String name;
  final Map<String, dynamic> data;
  final List<String> roles;
  final bool requiresAuth;

  const RouteMeta({
    required this.name,
    this.data = const {},
    this.roles = const [],
    this.requiresAuth = false,
  });
}

/// Route transition config
enum RouteTransitionType {
  fade,
  slide,
  scale,
  rotation,
  none,
}

class RouteTransition {
  final RouteTransitionType type;
  final Duration duration;
  final Curve curve;

  const RouteTransition({
    this.type = RouteTransitionType.fade,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeInOut,
  });
}

/// Route middleware (guards)
typedef RouteGuard = Future<String?> Function(
  BuildContext context,
  String path,
  Map<String, String> params,
);

/// Common route guards
class RouteGuards {
  static FutureOr<bool> Function(BuildContext context)? isAuthenticated;
  static FutureOr<List<String>> Function(BuildContext context)? currentRoles;

  /// Require authentication
  static RouteGuard requireAuth({String redirectTo = '/login'}) {
    return (context, path, params) async {
      final authenticated = await _isAuthenticated(context);

      if (!authenticated) {
        return '$redirectTo?redirect=$path';
      }

      return null;
    };
  }

  /// Require specific role
  static RouteGuard requireRole(
    List<String> roles, {
    String redirectTo = '/unauthorized',
  }) {
    return (context, path, params) async {
      final userRoles = await _currentRoles(context);

      if (!roles.any((role) => userRoles.contains(role))) {
        return redirectTo;
      }

      return null;
    };
  }

  /// Redirect if authenticated
  static RouteGuard redirectIfAuth({String redirectTo = '/'}) {
    return (context, path, params) async {
      final authenticated = await _isAuthenticated(context);

      if (authenticated) {
        return redirectTo;
      }

      return null;
    };
  }

  static Future<bool> _isAuthenticated(BuildContext context) async {
    final configured = isAuthenticated;
    if (configured != null) return configured(context);
    return DV.Auth.currentUser != null;
  }

  static Future<List<String>> _currentRoles(BuildContext context) async {
    final configured = currentRoles;
    if (configured != null) return configured(context);
    final user = DV.Auth.currentUser;
    if (user is DVAuthUser) {
      final roles = user.metadata['roles'];
      if (roles is List) return roles.map((role) => '$role').toList();
      final role = user.metadata['role'];
      if (role != null) return ['$role'];
    }
    return const <String>[];
  }
}

/// Breadcrumb for navigation
class Breadcrumb {
  final String label;
  final String path;
  final IconData? icon;

  const Breadcrumb({
    required this.label,
    required this.path,
    this.icon,
  });
}

/// Route helpers
class RouteHelpers {
  /// Generate breadcrumbs from current path
  static List<Breadcrumb> getBreadcrumbs(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final breadcrumbs = <Breadcrumb>[
      const Breadcrumb(label: 'Home', path: '/'),
    ];

    var currentPath = '';
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      currentPath += '/$segment';

      // Format label (capitalize, replace dashes/underscores)
      final label = segment
          .replaceAll(RegExp(r'[-_]'), ' ')
          .split(' ')
          .map((word) =>
              word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1))
          .join(' ');

      breadcrumbs.add(Breadcrumb(
        label: label,
        path: currentPath,
      ));
    }

    return breadcrumbs;
  }

  /// Check if path matches pattern
  static bool matchesPattern(String path, String pattern) {
    // Convert :param to regex
    final regex = pattern.replaceAllMapped(
      RegExp(r':([a-zA-Z0-9_]+)'),
      (m) => '([^/]+)',
    );

    return RegExp('^$regex\$').hasMatch(path);
  }

  /// Extract params from path
  static Map<String, String> extractParams(String path, String pattern) {
    final params = <String, String>{};

    final paramNames = RegExp(r':([a-zA-Z0-9_]+)')
        .allMatches(pattern)
        .map((m) => m.group(1)!)
        .toList();

    final regex = pattern.replaceAllMapped(
      RegExp(r':([a-zA-Z0-9_]+)'),
      (m) => '([^/]+)',
    );

    final match = RegExp('^$regex\$').firstMatch(path);
    if (match != null) {
      for (var i = 0; i < paramNames.length; i++) {
        params[paramNames[i]] = match.group(i + 1)!;
      }
    }

    return params;
  }
}
