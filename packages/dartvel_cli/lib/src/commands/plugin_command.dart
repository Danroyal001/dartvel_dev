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
      appBar: AppBar(title: const Text('Login')),
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
                        // TODO: Call /api/auth/login
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Logging in...')),
                        );
                      }
                    },
                    child: const Text('Login'),
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
Future<Map<String, dynamic>> handler({
  required String email,
  required String password,
}) async {
  // TODO: Validate credentials against database
  if (email.isEmpty || password.isEmpty) {
    throw Exception('Email and password required');
  }

  // Mock authentication
  if (email == 'demo@example.com' && password == 'password') {
    return {
      'success': true,
      'token': 'mock_jwt_token_here',
      'user': {
        'id': '1',
        'email': email,
        'name': 'Demo User',
      },
    };
  }

  throw Exception('Invalid credentials');
}
''';

  static const String _authLogoutEndpointTemplate = '''// POST /api/auth/logout
Map<String, dynamic> handler() {
  // TODO: Invalidate session/token
  return {
    'success': true,
    'message': 'Logged out successfully',
  };
}
''';

  static const String _authMeEndpointTemplate = '''// GET /api/auth/me
Map<String, dynamic> handler() {
  // TODO: Get user from session/token
  return {
    'id': '1',
    'email': 'demo@example.com',
    'name': 'Demo User',
  };
}
''';

  static const String _analyticsUtilTemplate =
      '''// Analytics utility for tracking events
class Analytics {
  static void logEvent(String name, [Map<String, Object>? parameters]) {
    // TODO: Integrate with your analytics provider
    // e.g., Firebase Analytics, Mixpanel, etc.
    print('Analytics: \$name \${parameters ?? {}}');
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
    print('Analytics: Set user ID: \$userId');
  }

  static void setUserProperties(Map<String, Object> properties) {
    print('Analytics: Set user properties: \$properties');
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
    Logger.log('⚠️  Plugin removal is manual for now.');
    Logger.log('   Delete the plugin files from your project.');
  }
}
