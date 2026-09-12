/// Rewrites the Homebrew formula for a release.
///
///     dart tool/ci/homebrew_formula.dart <version> <SHA256SUMS> <formula.rb>
///
/// The tap installs prebuilt binaries, so the formula carries a URL and a
/// digest per platform. Both come from the release itself: the digests are the
/// file the release publishes, so the formula and SHA256SUMS cannot disagree
/// about the same binary, and an asset the release does not carry is refused
/// here rather than becoming a 404 at `brew install`.
///
/// Written into the repository because the last release did this from a
/// throwaway script, and the next one had nothing to run.
library;

import 'dart:io';

int main(List<String> arguments) => exitCode = _run(arguments);

int _run(List<String> arguments) {
  if (arguments.length != 3) {
    stderr.writeln('usage: homebrew_formula.dart <version> <SHA256SUMS> <formula.rb>');
    return 2;
  }
  final String version = arguments[0];
  final File sums = File(arguments[1]);
  final File formula = File(arguments[2]);
  if (!sums.existsSync()) {
    stderr.writeln('${sums.path} is not there');
    return 1;
  }
  if (!formula.existsSync()) {
    stderr.writeln('${formula.path} is not there');
    return 1;
  }

  // "<digest>  dartvel-linux-x64", the shasum format.
  final Map<String, String> digests = <String, String>{
    for (final String line in sums.readAsLinesSync())
      if (RegExp(r'^([0-9a-f]{64})\s+\*?(\S+)$').firstMatch(line.trim())
          case final RegExpMatch m)
        m.group(2)!: m.group(1)!,
  };
  if (digests.isEmpty) {
    stderr.writeln('${sums.path} lists no digests');
    return 1;
  }

  final List<String> lines = formula.readAsLinesSync();
  final List<String> out = <String>[];
  final List<String> missing = <String>[];
  var urls = 0;
  String? pending;
  for (final String line in lines) {
    final RegExpMatch? url =
        RegExp(r'^(\s*)url "(.*/releases/download/)v[^/]+/([^"]+)"').firstMatch(line);
    if (url != null) {
      final String asset = url.group(3)!;
      out.add('${url.group(1)}url "${url.group(2)}v$version/$asset"');
      pending = asset;
      urls++;
      continue;
    }
    final RegExpMatch? sha = RegExp(r'^(\s*)sha256 "([0-9a-f]{64}|:no_check)"').firstMatch(line);
    if (sha != null && pending != null) {
      final String? digest = digests[pending];
      if (digest == null) {
        missing.add(pending);
        out.add(line);
      } else {
        out.add('${sha.group(1)}sha256 "$digest"');
      }
      pending = null;
      continue;
    }
    out.add(RegExp(r'^\s*version "').hasMatch(line)
        ? line.replaceFirst(RegExp(r'version "[^"]*"'), 'version "$version"')
        : line);
  }

  if (urls == 0) {
    stderr.writeln('no release URLs in ${formula.path}; nothing was rewritten');
    return 1;
  }
  if (missing.isNotEmpty) {
    // Loud: a formula left pointing at an asset the release does not carry
    // installs nothing and says only "404".
    stderr.writeln('the release publishes no digest for: ${missing.join(', ')}');
    return 1;
  }
  formula.writeAsStringSync('${out.join('\n')}\n');
  stdout.writeln('$version: rewrote $urls binaries in ${formula.path}');
  return 0;
}
