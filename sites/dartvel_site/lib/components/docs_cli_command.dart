/// One command in the CLI reference, as the command table declares it.
///
/// Plain data, so the reference the site shows is generated from the CLI and
/// nothing on the page is typed out by hand.
class DocsCliCommand {
  const DocsCliCommand({
    required this.name,
    required this.description,
    this.aliases = const <String>[],
    this.options = const <String>[],
    this.subcommands = const <DocsCliCommand>[],
  });

  final String name;
  final String description;
  final List<String> aliases;

  /// The option lines `--help` prints, without the help flag itself.
  final List<String> options;
  final List<DocsCliCommand> subcommands;
}
