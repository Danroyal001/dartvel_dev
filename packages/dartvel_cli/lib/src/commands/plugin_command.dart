import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../utils/logger.dart';

class PluginCommand extends Command<void> {
  @override
  final String name = 'plugin';

  @override
  final String description = 'Add plugins to your Dartvel project.';

  PluginCommand() {
    addSubcommand(PluginAddCommand());
  }
}

class PluginAddCommand extends Command<void> {
  @override
  final String name = 'add';

  @override
  final String description = 'Add a specific plugin.';

  PluginAddCommand() {
    argParser.addOption('name', abbr: 'n', help: 'Name of the plugin (e.g. auth)');
  }

  @override
  Future<void> run() async {
    final name = argResults?.rest.firstOrNull ?? argResults?['name'];
    if (name == null) {
      Logger.error('Please specify a plugin name: dartvel plugin add <name>');
      exit(1);
    }

    switch (name) {
      case 'auth':
        await _addAuthPlugin();
        break;
      default:
        Logger.error('Unknown plugin: $name');
        exit(1);
    }
  }

  Future<void> _addAuthPlugin() async {
    Logger.log('Adding auth plugin...');
    final root = Directory.current.path;
    
    // Scaffold login page
    final loginPage = File(p.join(root, 'lib/pages/login.page.dart'));
    if (!loginPage.existsSync()) {
      loginPage.createSync(recursive: true);
      loginPage.writeAsStringSync(r'''
import 'package:flutter/material.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

class LoginPage extends DartvelPage {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // TODO: Implement login
          },
          child: const Text('Login'),
        ),
      ),
    );
  }
}
''');
      Logger.log('Created lib/pages/login.page.dart');
    }

    // Scaffold auth backend
    final authBackend = File(p.join(root, 'lib/backend/functions/auth.dart'));
    if (!authBackend.existsSync()) {
      authBackend.createSync(recursive: true);
      authBackend.writeAsStringSync(r'''
import 'package:dartvel_core/dartvel.dart';

Future<Response> handler(Request req) async {
  if (req.method == 'POST') {
    final body = await req.formData();
    final username = body['username'];
    final password = body['password'];
    
    // TODO: Validate credentials
    if (username == 'admin' && password == 'admin') {
      return Res.json({'token': '12345'});
    }
    return Res.json({'error': 'Invalid credentials'}, status: 401);
  }
  return Res.json({'message': 'Auth endpoint'});
}
''');
      Logger.log('Created lib/backend/functions/auth.dart');
    }
    
    Logger.log('Auth plugin added successfully.');
  }
}
