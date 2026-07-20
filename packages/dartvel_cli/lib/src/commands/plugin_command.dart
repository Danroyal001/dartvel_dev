import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';

class PluginCommand extends Command<void> {
  @override
  final String name = 'plugin';

  @override
  String get description => 'Manage Dartvel plugins.';

  PluginCommand() {
    addSubcommand(_PluginAddCommand());
    addSubcommand(_PluginListCommand());
    addSubcommand(_PluginRemoveCommand());
  }
}

class _PluginAddCommand extends Command<void> {
  @override
  final String name = 'add';

  @override
  String get description => 'Add a plugin to your project.';

  _PluginAddCommand() {
    argParser.addOption('name',
        abbr: 'n', help: 'Plugin name (e.g., auth, analytics)');
  }

  @override
  Future<void> run() async {
    final pluginName = argResults?['name'] as String?;
    final restArgs = argResults?.rest ?? [];

    final plugin = pluginName ?? (restArgs.isNotEmpty ? restArgs.first : null);

    if (plugin == null) {
      Logger.log('❌ Please specify a plugin name');
      Logger.log('   Example: dartvel plugin add auth');
      exit(1);
    }

    final root = Directory.current.path;

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
        exit(1);
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
      '''import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

class LoginPage extends DartvelPage {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: const DVText('Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      if (formKey.currentState?.validate() ?? false) {
                        await DV.Auth.signInWithEmailAndPassword(
                          email: emailController.text.trim(),
                          password: passwordController.text,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: DVText('Signed in')),
                        );
                      }
                    },
                    child: const DVText('Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
''';

  static const String _authLoginEndpointTemplate = '''// POST /api/auth/login
import 'dart:convert';

final Map<String, Map<String, Object?>> _usersByEmail = {};
final Map<String, Map<String, Object?>> _sessionsByToken = {};

Future<Map<String, Object?>> handler({
  required String email,
  required String password,
}) async {
  final normalizedEmail = email.trim().toLowerCase();
  if (normalizedEmail.isEmpty || password.isEmpty) {
    throw Exception('Email and password required');
  }
  if (password.length < 8) {
    throw Exception('Password must be at least 8 characters');
  }

  final user = _usersByEmail.putIfAbsent(normalizedEmail, () => {
        'id': base64Url.encode(utf8.encode(normalizedEmail)).replaceAll('=', ''),
        'email': normalizedEmail,
        'createdAt': DateTime.now().toIso8601String(),
      });
  final tokenPayload = jsonEncode({
    'userId': user['id'],
    'email': normalizedEmail,
    'issuedAt': DateTime.now().toIso8601String(),
  });
  final token = base64Url.encode(utf8.encode(tokenPayload)).replaceAll('=', '');
  _sessionsByToken[token] = user;

  return {
    'success': true,
    'token': token,
    'user': user,
  };
}
''';

  static const String _authLogoutEndpointTemplate = '''// POST /api/auth/logout
final Set<String> _revokedTokens = {};

Map<String, Object?> handler({String? token}) {
  if (token != null && token.isNotEmpty) {
    _revokedTokens.add(token);
  }
  return {
    'success': true,
    'message': 'Logged out successfully',
  };
}
''';

  static const String _authMeEndpointTemplate = '''// GET /api/auth/me
import 'dart:convert';

Map<String, Object?> handler({required String token}) {
  if (token.isEmpty) {
    throw Exception('Authentication token required');
  }
  final normalized = base64.normalize(token);
  final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)))
      as Map<String, Object?>;
  return {
    'id': decoded['userId'],
    'email': decoded['email'],
    'issuedAt': decoded['issuedAt'],
  };
}
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
  @override
  final String name = 'remove';

  @override
  String get description => 'Remove a plugin from your project.';

  @override
  Future<void> run() async {
    final root = Directory.current.path;
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
