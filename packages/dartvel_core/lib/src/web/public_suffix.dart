/// The registrable domain of a host ("eTLD+1"), by the Public Suffix List.
///
/// What decides how far a cookie's `Domain` may reach: a browser refuses a
/// cookie for a public suffix -- `co.uk`, `github.io` -- so a session that
/// spans an application's hosts is set on the registrable domain they share,
/// never on "the last two labels". Both sections of the list count, ICANN
/// and private, because browsers apply both. The list is generated into
/// `public_suffix_list.dart` by `tool/update_public_suffix_list.dart`.
///
/// Pure Dart with no `dart:io`.
library;

import 'host_routing.dart' show dvNormaliseHost;
import 'public_suffix_list.dart';

/// The list's rules, parsed once on first use.
final class _Rules {
  _Rules._(this.exact, this.wildcards, this.exceptions);

  final Set<String> exact;

  /// `*.ck` is kept as `ck`: the suffixes it stands for are one label below.
  final Set<String> wildcards;

  /// `!www.ck` is kept as `www.ck`.
  final Set<String> exceptions;

  static final _Rules instance = () {
    final Set<String> exact = <String>{};
    final Set<String> wildcards = <String>{};
    final Set<String> exceptions = <String>{};
    for (final String rule in dvPublicSuffixRules.split('\n')) {
      if (rule.isEmpty) continue;
      if (rule.startsWith('!')) {
        exceptions.add(rule.substring(1));
      } else if (rule.startsWith('*.')) {
        wildcards.add(rule.substring(2));
      } else {
        exact.add(rule);
      }
    }
    return _Rules._(exact, wildcards, exceptions);
  }();

  /// How many labels of [labels] (from the right) are the public suffix.
  int suffixLength(List<String> labels) {
    int longest = 1; // The default rule "*": an unlisted TLD is a suffix.
    for (int i = labels.length - 1; i >= 0; i--) {
      final String candidate = labels.sublist(i).join('.');
      final int length = labels.length - i;
      if (exceptions.contains(candidate)) {
        // An exception rule wins, and its suffix is one label shorter.
        return length - 1;
      }
      if (exact.contains(candidate) && length > longest) longest = length;
      if (i > 0 && wildcards.contains(candidate) && length + 1 > longest) {
        longest = length + 1;
      }
    }
    return longest;
  }
}

final RegExp _label = RegExp(r'^[a-z0-9_](?:[a-z0-9_-]{0,61}[a-z0-9_])?$');

List<String>? _labels(String host) {
  final String? name = dvNormaliseHost(host);
  if (name == null || name.contains(':')) return null; // IPv6.
  if (RegExp(r'^[0-9.]+$').hasMatch(name)) return null; // IPv4.
  final List<String> labels = name.split('.');
  if (!labels.every(_label.hasMatch)) return null;
  return labels;
}

/// The registrable domain of [host]: its public suffix plus one label.
///
/// Null for a host that has none -- a public suffix itself, an IP address,
/// `localhost` or anything that is not a host name -- because nothing may
/// set a cookie shared across it. [host] is normalised first (case, port,
/// trailing dot).
String? dvRegistrableDomain(String host) {
  final List<String>? labels = _labels(host);
  if (labels == null) return null;
  final int suffix = _Rules.instance.suffixLength(labels);
  if (labels.length <= suffix) return null;
  return labels.sublist(labels.length - suffix - 1).join('.');
}

/// Whether [domain] is a public suffix: a name under which unrelated
/// parties register, and for which no cookie may be set.
bool dvIsPublicSuffix(String domain) {
  final List<String>? labels = _labels(domain);
  if (labels == null) return false;
  return _Rules.instance.suffixLength(labels) >= labels.length;
}
