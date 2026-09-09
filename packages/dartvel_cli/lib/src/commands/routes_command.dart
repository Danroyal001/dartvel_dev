import 'package:args/command_runner.dart';
import '../build/render_backends.dart';
import '../generators/routes_generator.dart';
import '../utils/logger.dart';

class RoutesCommand extends Command<void> {
  @override
  final String name = 'routes';

  @override
  final String description = 'Generate routes and client artifacts.';

  RoutesCommand() {
    argParser.addOption(
      'render',
      help: 'The rendering backends this build links (gui, terminal, or '
          'both). `dartvel build` passes what it resolved from the -cli/-tui '
          'suffix and dartvel.terminal; run by hand it defaults to gui.',
    );
  }

  @override
  Future<void> run() async {
    await generate(
      renderBackends: parseRenderBackends(argResults?['render'] as String?),
    );
    Logger.log('Generated routes and client artifacts.');
  }
}
