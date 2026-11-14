/// Adding the origins a mounted module needs to a Content-Security-Policy
/// the application wrote.
///
/// A module that loads a third party's script -- an analytics tag, an
/// advertising pixel -- cannot work under a page policy that does not list
/// that third party, and the application should not have to find out which
/// origins those are by reading a browser console. The module names them in
/// its own pubspec under `dartvel.module.csp`, and the build adds them to
/// `dartvel.security.pageCsp` with this.
///
/// Only ever additions to a policy that exists. An application with no page
/// policy is sent none, and a directive the policy leaves unrestricted is
/// left unrestricted: writing it with the module's origins alone would refuse
/// everything else the page was loading.
library;

/// A scheme and host, with an optional leading `*.` label, port and path:
/// what a module may ask for. Keywords (`'unsafe-inline'`, `'unsafe-eval'`),
/// bare schemes (`https:`) and `*` are not, since each would widen the
/// policy for the whole page rather than name the module's own third party.
final RegExp _origin = RegExp(
  r'^(https|wss)://(\*\.)?[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+(:\d+)?(/[A-Za-z0-9._~/-]*)?$',
);

/// Whether [source] is an origin a module may add to a policy.
bool dvIsContentSecurityPolicyOrigin(String source) =>
    _origin.hasMatch(source);

/// [policy] with every source in [additions] allowed, by directive name.
///
/// - A directive the policy has gets the sources it does not already list.
///   `'none'` in it gives way to them.
/// - A directive it lacks is written from what `default-src` allowed plus
///   the sources, because a fetch directive that is present no longer falls
///   back to `default-src`.
/// - With no such directive and no `default-src` the policy does not
///   restrict that kind of load, and it is left that way.
/// - A `script-src` source is also added to `script-src-elem` when the
///   policy has one, since that is what a `<script>` element is checked
///   against.
///
/// Throws an [ArgumentError] for a source that is not an origin.
String dvAddContentSecurityPolicySources(
  String policy,
  Map<String, List<String>> additions,
) {
  final Map<String, List<String>> wanted = <String, List<String>>{};
  additions.forEach((String directive, List<String> sources) {
    final String name = directive.trim().toLowerCase();
    if (!RegExp(r'^[a-z-]+-src(-elem|-attr)?$').hasMatch(name)) {
      throw ArgumentError.value(directive, 'additions',
          'is not a Content-Security-Policy fetch directive');
    }
    for (final String source in sources) {
      if (!dvIsContentSecurityPolicyOrigin(source)) {
        throw ArgumentError.value(source, 'additions',
            'is not an origin such as https://cdn.example.com');
      }
      final List<String> list = wanted.putIfAbsent(name, () => <String>[]);
      if (!list.contains(source)) list.add(source);
    }
  });
  if (wanted.isEmpty) return policy;

  // Each directive as written: its name in the case the policy used, and
  // its sources in order.
  final List<(String, List<String>)> directives = <(String, List<String>)>[
    for (final String part in policy.split(';'))
      if (part.trim().isNotEmpty)
        (
          part.trim().split(RegExp(r'\s+')).first,
          part.trim().split(RegExp(r'\s+')).skip(1).toList(),
        ),
  ];
  int indexOf(String name) => directives
      .indexWhere(((String, List<String>) d) => d.$1.toLowerCase() == name);

  void add(int index, List<String> sources) {
    final List<String> listed = directives[index].$2
      ..removeWhere((String s) => s.toLowerCase() == "'none'");
    for (final String source in sources) {
      if (!listed.contains(source)) listed.add(source);
    }
  }

  final int fallback = indexOf('default-src');
  wanted.forEach((String name, List<String> sources) {
    final int at = indexOf(name);
    if (at >= 0) {
      add(at, sources);
    } else if (fallback >= 0) {
      directives.add((name, List<String>.of(directives[fallback].$2)));
      add(directives.length - 1, sources);
    }
    if (name == 'script-src') {
      final int element = indexOf('script-src-elem');
      if (element >= 0) add(element, sources);
    }
  });

  return directives
      .map(((String, List<String>) d) => <String>[d.$1, ...d.$2].join(' '))
      .join('; ');
}
