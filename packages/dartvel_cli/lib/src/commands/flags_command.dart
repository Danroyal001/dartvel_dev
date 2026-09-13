import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:file/local.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../generators/flag_generator.dart';

/// `dartvel flags list`, as the command prints it.
///
/// Separated from the command so it can be tested without a CommandRunner or
/// captured stdout, the way `dartvel explain` is.
Future<String> dvFlagsList({
  required String root,
  required String pkgName,
}) async {
  final List<DiscoveredFlag> flags =
      await FlagGenerator.discover(root: root, pkgName: pkgName);
  if (flags.isEmpty) {
    return 'No flags are declared. Declare them as static const fields of a '
        'private @DVFlags() class; `dartvel routes` generates `Flags` from it.';
  }

  final List<List<String>> rows = <List<String>>[
    <String>['FLAG', 'TYPE', 'DEFAULT', 'OWNER', 'EXPIRES', 'SETTLE'],
    for (final DiscoveredFlag flag in flags)
      <String>[
        flag.name,
        flag.type,
        flag.initializer,
        flag.owner,
        _date(flag.expires),
        flag.settle ?? 'immediately',
      ],
  ];
  return '${_table(rows)}\n\n${flags.length} '
      'flag${flags.length == 1 ? '' : 's'} declared.';
}

/// `dartvel flags prune`, as the command prints it: the flags past their
/// expiry at [now], each with every line of application code that still
/// reads it.
///
/// The reads are the point. Deleting a flag means deleting the branches it
/// guards, and a list of due names without the code that uses them is a list
/// of reasons to leave the flags in.
Future<String> dvFlagsPrune({
  required String root,
  required String pkgName,
  required DateTime now,
}) async {
  final List<DiscoveredFlag> flags =
      await FlagGenerator.discover(root: root, pkgName: pkgName);
  final List<DiscoveredFlag> due = <DiscoveredFlag>[
    for (final DiscoveredFlag flag in flags)
      if (flag.expires.isBefore(now)) flag,
  ];
  if (due.isEmpty) {
    return 'No flags are past their expiry.';
  }

  // The declarations themselves are not reads, and neither is generated
  // output, which names every flag by construction.
  final Set<String> declarations = <String>{
    for (final DiscoveredFlag flag in flags)
      flag.importPath.replaceFirst('package:$pkgName/', 'lib/'),
  };
  final List<(String, List<String>)> sources = <(String, List<String>)>[];
  for (final File file in _applicationFiles(root)) {
    final String relative =
        p.relative(file.path, from: root).replaceAll('\\', '/');
    if (declarations.contains(relative)) continue;
    sources.add((relative, await file.readAsLines()));
  }

  final StringBuffer out = StringBuffer()
    ..writeln('${due.length} flag${due.length == 1 ? ' is' : 's are'} past '
        'expiry:')
    ..writeln();
  for (final DiscoveredFlag flag in due) {
    final RegExp read = RegExp('\\bFlags\\.${RegExp.escape(flag.name)}\\b');
    final List<String> reads = <String>[
      for (final (String path, List<String> lines) in sources)
        for (int i = 0; i < lines.length; i++)
          if (read.hasMatch(lines[i])) '$path:${i + 1}',
    ];
    out.writeln('  ${flag.name}  (owner ${flag.owner}, expired '
        '${_date(flag.expires)})');
    if (reads.isEmpty) {
      out.writeln('    no remaining reads — delete the declaration and run '
          '`dartvel routes`');
    } else {
      for (final String at in reads) {
        out.writeln('    $at');
      }
    }
    out.writeln();
  }
  return out.toString().trimRight();
}

List<File> _applicationFiles(String root) {
  const LocalFileSystem fs = LocalFileSystem();
  final List<File> files = <File>[];
  for (final entity in Glob('lib/**.dart')
      .listFileSystemSync(fs, root: root, followLinks: false)) {
    if (entity is! File) continue;
    final String path = entity.path.replaceAll('\\', '/');
    if (path.contains('/lib/dartvel_client/')) continue;
    files.add(File(entity.path));
  }
  files.sort((File a, File b) => a.path.compareTo(b.path));
  return files;
}

String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _table(List<List<String>> rows) {
  final List<int> widths = List<int>.filled(rows.first.length, 0);
  for (final List<String> row in rows) {
    for (int i = 0; i < row.length; i++) {
      if (row[i].length > widths[i]) widths[i] = row[i].length;
    }
  }
  return <String>[
    for (final List<String> row in rows)
      <String>[
        for (int i = 0; i < row.length; i++) row[i].padRight(widths[i]),
      ].join('  ').trimRight(),
  ].join('\n');
}

/// The project's package name, from its pubspec.
String _packageName(String root) {
  final File pubspec = File(p.join(root, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw UsageException(
      'No pubspec.yaml in $root.',
      'Run `dartvel flags` from the root of a Dartvel project.',
    );
  }
  final RegExpMatch? name = RegExp(r'^name:\s*([A-Za-z0-9_]+)', multiLine: true)
      .firstMatch(pubspec.readAsStringSync());
  if (name == null) {
    throw UsageException('pubspec.yaml in $root has no name.', '');
  }
  return name.group(1)!;
}

/// `dartvel flags`: the declared flags, and the ones that are due.
///
/// `set`, `rollout`, `off` and `override` change rules a deployment serves,
/// which needs the rule publisher and is not here yet; `list` and `prune`
/// read only the project.
class FlagsCommand extends Command<void> {
  FlagsCommand() {
    addSubcommand(_FlagsListCommand());
    addSubcommand(_FlagsPruneCommand());
  }

  @override
  final String name = 'flags';

  @override
  String get description =>
      'List the declared feature flags, and the ones past their expiry.';
}

class _FlagsListCommand extends Command<void> {
  @override
  final String name = 'list';

  @override
  String get description =>
      'Every declared flag, with its type, default, owner and expiry.';

  @override
  Future<void> run() async {
    final String root = Directory.current.path;
    stdout.writeln(
        await dvFlagsList(root: root, pkgName: _packageName(root)));
  }
}

class _FlagsPruneCommand extends Command<void> {
  @override
  final String name = 'prune';

  @override
  String get description =>
      'Flags past their expiry, with the code that still reads each one.';

  @override
  Future<void> run() async {
    final String root = Directory.current.path;
    stdout.writeln(await dvFlagsPrune(
      root: root,
      pkgName: _packageName(root),
      now: DateTime.now().toUtc(),
    ));
  }
}
