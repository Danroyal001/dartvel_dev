import 'package:args/command_runner.dart';
import '../generators/routes_generator.dart';
import '../utils/logger.dart';

class RoutesCommand extends Command<void> {
  @override
  final String name = 'routes';

  @override
  final String description = 'Generate routes and client artifacts.';

  @override
  Future<void> run() async {
    await generate();
    Logger.log('Generated routes and client artifacts.');
  }
}
