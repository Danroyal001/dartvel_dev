/// Reading the `.env` format, in one place.
///
/// Separate from the resolver on purpose. The runtime resolves values, the
/// build checks which names would be compiled into the client bundle, and
/// `dartvel deploy` checks which names are set at all -- three callers with
/// three jobs and one file format between them. When they each had their own
/// reader they disagreed: the deploy gate did not know `export KEY=value`, so
/// it failed a deploy over a secret the running process resolves fine.
///
/// No `dart:io` here. The parser is pure string work, which keeps it usable
/// from the analysis in `dartvel_cli` as well as from the server runtime, and
/// keeps this library safe to reach from a web build.
library dartvel.secrets.env_format;

/// Names and values from the contents of a `.env` file.
///
/// Blank lines and `#` comments are skipped. An `export ` prefix is accepted,
/// because people paste these files into a shell and a line the shell honours
/// while the framework ignores it is a secret that is set everywhere except
/// where the code goes looking. Matched quotes around a value are stripped.
///
/// `KEY=` is dropped rather than recorded as the empty string. That is what
/// an unset variable looks like coming through a shell, and a payment client
/// constructed with `''` fails a long way from the cause.
Map<String, String> dvParseEnvContents(String contents) {
  final Map<String, String> out = <String, String>{};
  for (final String raw in contents.split('\n')) {
    String line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.substring(7).trim();

    final int separator = line.indexOf('=');
    if (separator <= 0) continue;

    final String name = line.substring(0, separator).trim();
    String value = line.substring(separator + 1).trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isEmpty) continue;
    out[name] = value;
  }
  return out;
}
