/// One command in the CLI reference, as the command table declares it.
///
/// Plain data, so the reference the site shows is generated from the CLI and
/// nothing on the page is typed out by hand.
class const DocsCliCommand({
  required final String name,
  required final String description,
  final List<String> aliases = const <String>[],

  /// The option lines `--help` prints, without the help flag itself.
  final List<String> options = const <String>[],
  final List<DocsCliCommand> subcommands = const <DocsCliCommand>[],
});
