import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';

class PluginCommand extends Command<void> {
  @override
  final String name = 'plugin';

  @override
  String get description => 'Manage Dartvel plugins.';

  /// [root] is the project; null reads the working directory when the command
  /// runs. A test passes its own, because that directory is one value shared
  /// by every suite in the process.
  PluginCommand({String? root}) {
    addSubcommand(_PluginAddCommand(root: root));
    addSubcommand(_PluginListCommand());
    addSubcommand(_PluginRemoveCommand(root: root));
  }
}

class _PluginAddCommand extends Command<void> {
  @override
  final String name = 'add';

  @override
  String get description => 'Add a plugin to your project.';

  final String? _root;

  _PluginAddCommand({this._root}) {
    argParser.addOption('name',
        abbr: 'n', help: 'Plugin name (e.g., auth, analytics)');
  }

  @override
  Future<void> run() async {
    final pluginName = argResults?['name'] as String?;
    final restArgs = argResults?.rest ?? const <String>[];

    final plugin = pluginName ?? (restArgs.isNotEmpty ? restArgs.first : null);

    if (plugin == null) {
      Logger.log('❌ Please specify a plugin name');
      Logger.log('   Example: dartvel plugin add auth');
      exitCode = 64;
      return;
    }

    final root = _root ?? Directory.current.path;

    Logger.log('📦 Adding plugin: $plugin');

    switch (plugin.toLowerCase()) {
      case 'auth':
        await _addAuthPlugin(root);
        break;
      case 'analytics':
        await _addAnalyticsPlugin(root);
        break;
      default:
        Logger.log('❌ Unknown plugin: $plugin');
        Logger.log('   Available: auth, analytics');
        exitCode = 64;
        return;
    }

    Logger.log('✅ Plugin added successfully!');
    Logger.log('');
    Logger.log('Next steps:');
    Logger.log('  1. Review the generated files');
    Logger.log('  2. Run: dartvel dev');
  }

  Future<void> _addAuthPlugin(String root) async {
    Logger.log('  Creating auth pages and endpoints...');

    // Create login page
    final loginPage = File(p.join(root, 'lib/pages/login.page.dart'));
    loginPage.parent.createSync(recursive: true);
    loginPage.writeAsStringSync(_authLoginPageTemplate);

    // Create auth backend endpoints
    final authDir = Directory(p.join(root, 'lib/backend/functions/auth'));
    authDir.createSync(recursive: true);

    File(p.join(authDir.path, 'login.dart'))
        .writeAsStringSync(_authLoginEndpointTemplate);
    File(p.join(authDir.path, 'logout.dart'))
        .writeAsStringSync(_authLogoutEndpointTemplate);
    File(p.join(authDir.path, 'me.get.dart'))
        .writeAsStringSync(_authMeEndpointTemplate);

    Logger.log('  ✓ Created lib/pages/login.page.dart');
    Logger.log('  ✓ Created lib/backend/functions/auth/login.dart');
    Logger.log('  ✓ Created lib/backend/functions/auth/logout.dart');
    Logger.log('  ✓ Created lib/backend/functions/auth/me.get.dart');
  }

  Future<void> _addAnalyticsPlugin(String root) async {
    Logger.log('  Creating analytics utilities...');

    final analyticsFile = File(p.join(root, 'lib/utils/analytics.dart'));
    analyticsFile.parent.createSync(recursive: true);
    analyticsFile.writeAsStringSync(_analyticsUtilTemplate);

    Logger.log('  ✓ Created lib/utils/analytics.dart');
  }

  static const String _authLoginPageTemplate =
      '''import '../dartvel_client/dartvel_client.dart';
import 'package:flutter/widgets.dart';

@DVPage(title: 'Login')
@pragma('vm:entry-point')
Widget _loginPage(BuildContext context) => DV.Auth.SignInWithEmailAndPasswordPage();
''';

  // The three endpoints are raw HTTP for a client that is not a page -- a
  // mobile app, a command-line tool, another server -- and every one of them
  // is the framework's own sign-in underneath: the installed accounts, the
  // password check with its velocity limits, and DVSessions. A page signs in
  // at the generated <api>/auth/sign-in, which sets the session cookie behind
  // a CSRF check.
  //
  // A raw path checks no CSRF token and reads no session cookie, so these
  // speak bearer tokens only. That is also why login refuses a browser: a
  // cookie set here would be a sign-in no CSRF check stood in front of.
  static const String _authLoginEndpointTemplate =
      '''import 'package:dartvel_core/dartvel.dart';

/// `POST /auth/login` with `email` and `password`: a session token in the
/// body, from the framework's own sign-in.
///
/// The caller sends `x-dartvel-session-delivery: token`. A page cannot, and
/// signs in at `<api>/auth/sign-in` instead.
@DVBackendFunction(rawPath: '/auth/login')
@pragma('vm:entry-point')
Future<Response> _login(Request request) async {
  if (!DVAuthEndpoints.deliversToken(request)) {
    return Response.json(<String, Object?>{
      'error': 'token_delivery_required',
      'message': 'Send x-dartvel-session-delivery: token from a client that '
          'is not a browser. A page signs in at <api>/auth/sign-in.',
    }, status: 400);
  }
  return DVAuthEndpoints.signIn(request);
}
''';

  static const String _authLogoutEndpointTemplate =
      '''import 'package:dartvel_core/dartvel.dart';

/// `POST /auth/logout` with `Authorization: Bearer <token>`: revokes that
/// session on the server, so the token stops working everywhere.
@DVBackendFunction(rawPath: '/auth/logout')
@pragma('vm:entry-point')
Future<Response> _logout(Request request) async {
  // A bearer token was judged before this ran; without one there is no
  // session this endpoint may end.
  if (DVSessionPrincipal.current == null) {
    return Response.json(<String, Object?>{
      'error': 'unauthenticated',
      'message': 'Send the session token as Authorization: Bearer <token>.',
    }, status: 401);
  }
  return DVAuthEndpoints.signOut(request);
}
''';

  static const String _authMeEndpointTemplate =
      '''import 'package:dartvel_core/dartvel.dart';

/// `GET /auth/me` with `Authorization: Bearer <token>`: the account the
/// session belongs to.
///
/// The session is the one the server issued and still holds: a token it did
/// not issue, or one that was revoked, is refused before this runs, and
/// nothing a caller writes into a token decides who they are.
@DVBackendFunction(rawPath: '/auth/me')
@pragma('vm:entry-point')
Future<Response> _me(Request request) => DVAuthEndpoints.account(request);
''';

  static const String _analyticsUtilTemplate =
      '''// Analytics utility for tracking events
class AnalyticsEvent {
  final String name;
  final Map<String, Object> parameters;
  final DateTime timestamp;

  const AnalyticsEvent(this.name, this.parameters, this.timestamp);

  Map<String, Object> toJson() => {
        'name': name,
        'parameters': parameters,
        'timestamp': timestamp.toIso8601String(),
      };
}

class Analytics {
  static final List<AnalyticsEvent> _events = [];
  static String? _userId;
  static Map<String, Object> _userProperties = {};

  static List<AnalyticsEvent> get events => List.unmodifiable(_events);
  static String? get userId => _userId;
  static Map<String, Object> get userProperties =>
      Map.unmodifiable(_userProperties);

  static void logEvent(String name, [Map<String, Object>? parameters]) {
    if (name.trim().isEmpty) {
      throw ArgumentError('Analytics event name is required');
    }
    _events.add(AnalyticsEvent(
      name.trim(),
      Map.unmodifiable(parameters ?? const {}),
      DateTime.now(),
    ));
  }

  static void logScreenView(String screenName) {
    logEvent('screen_view', {'screen_name': screenName});
  }

  static void logLogin(String method) {
    logEvent('login', {'method': method});
  }

  static void logSignUp(String method) {
    logEvent('sign_up', {'method': method});
  }

  static void setUserId(String userId) {
    if (userId.trim().isEmpty) {
      throw ArgumentError('Analytics user ID is required');
    }
    _userId = userId.trim();
  }

  static void setUserProperties(Map<String, Object> properties) {
    _userProperties = Map.unmodifiable(properties);
  }
}
''';
}

class _PluginListCommand extends Command<void> {
  @override
  final String name = 'list';

  @override
  String get description => 'List available plugins.';

  @override
  Future<void> run() async {
    Logger.log('Available plugins:');
    Logger.log('  • auth       - Authentication scaffolding (login/logout/me)');
    Logger.log('  • analytics  - Analytics tracking utilities');
    Logger.log('');
    Logger.log('Add a plugin: dartvel plugin add <name>');
  }
}

class _PluginRemoveCommand extends Command<void> {
  _PluginRemoveCommand({this._root});

  final String? _root;

  @override
  final String name = 'remove';

  @override
  String get description => 'Remove a plugin from your project.';

  @override
  Future<void> run() async {
    final root = _root ?? Directory.current.path;
    final targets = [
      File(p.join(root, 'lib/pages/login.page.dart')),
      Directory(p.join(root, 'lib/backend/functions/auth')),
      File(p.join(root, 'lib/utils/analytics.dart')),
    ];
    for (final target in targets) {
      if (target.existsSync()) {
        target.deleteSync(recursive: true);
        Logger.log('  ✓ Removed ${p.relative(target.path, from: root)}');
      }
    }
    Logger.log('✅ Plugin files removed when present.');
  }
}
