import 'package:args/command_runner.dart';
import 'init_command.dart';

/// Alias for 'dartvel new'
class CreateCommand extends Command<void> {
  @override
  final String name = 'create';

  @override
  final String description = 'Create a new Dartvel project (alias for new)';

  final InitCommand _initCommand = InitCommand();

  CreateCommand() {
    // Copy argParser from InitCommand
    argParser.addOption('template',
        abbr: 't', defaultsTo: 'default', help: 'Project template to use');
  }

  @override
  Future<void> run() async {
    // Delegate to InitCommand
    return _initCommand.run();
  }
}
