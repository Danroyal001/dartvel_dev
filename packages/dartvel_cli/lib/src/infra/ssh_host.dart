/// The SSH adapter behind `dartvel infra`: a [DVInfraHost] that reads and
/// changes a host through the system `ssh` client.
///
/// Three rules, each of which is a failure that looks like success when it
/// is broken:
///
///  * nothing connects to a host whose key the project's known_hosts file
///    does not pin, and every connection runs with strict checking against
///    that file alone, so a first connection cannot quietly trust whatever
///    answers;
///  * a secret value travels on stdin and nowhere else -- not in the command
///    line, which `ps` shows, and not in a heredoc, which a shell may spill
///    to a temporary file -- and is encrypted by `systemd-creds` on arrival;
///  * an observation line that cannot be read fails the observation, because
///    skipping it reports a host with less on it than it has.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/dartvel.dart' hide Platform;

/// What one `ssh` invocation returned.
class DVSshOutput {
  const DVSshOutput(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Runs [executable] with [arguments], writing [stdin] to it when given.
typedef DVSshRun = Future<DVSshOutput> Function(
  String executable,
  List<String> arguments, {
  List<int>? stdin,
});

/// The host is not pinned in the project's known_hosts file.
class DVSshHostNotPinned implements Exception {
  const DVSshHostNotPinned(this.host, this.port, this.knownHostsPath);

  final String host;
  final int port;
  final String knownHostsPath;

  @override
  String toString() {
    final String name = port == 22 ? host : '[$host]:$port';
    return '$name is not pinned in $knownHostsPath, so nothing connects to '
        'it. Fetch its key with `ssh-keyscan -p $port $host`, compare the '
        'fingerprint (`ssh-keygen -lf`) with the one the host itself shows '
        'on its console or its provider\'s dashboard, and add the line to '
        'known_hosts. A key accepted on first sight is whatever answered.';
  }
}

/// A step, or the observation, exited non-zero on the host.
class DVSshStepFailed implements Exception {
  const DVSshStepFailed(this.what, this.exitCode, this.stderr);

  final String what;
  final int exitCode;
  final String stderr;

  @override
  String toString() {
    final List<String> lines = stderr
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.isNotEmpty)
        .toList();
    final String tail = lines.length <= 5
        ? lines.join(' / ')
        : lines.sublist(lines.length - 5).join(' / ');
    return '$what exited $exitCode${tail.isEmpty ? '' : ': $tail'}';
  }
}

/// Whether the known_hosts [text] pins [host] on [port].
///
/// Plain and comma-separated names, `[host]:port` for a port other than 22,
/// and hashed `|1|salt|hash` entries. `@revoked` for the host unpins it;
/// `@cert-authority`, negations and wildcards never pin one -- a pattern is
/// a trust decision about hosts nobody has seen yet.
bool dvKnownHostsPins(String text, String host, int port) {
  final String name = port == 22 ? host : '[$host]:$port';
  bool pinned = false;
  for (final String raw in const LineSplitter().convert(text)) {
    final String line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    List<String> fields = line.split(RegExp(r'\s+'));
    String? marker;
    if (fields.first.startsWith('@')) {
      marker = fields.first;
      fields = fields.sublist(1);
    }
    if (fields.length < 3) continue;
    if (!_matchesHostField(fields.first, name)) continue;
    if (marker == '@revoked') return false;
    if (marker != null) continue;
    pinned = true;
  }
  return pinned;
}

bool _matchesHostField(String field, String name) {
  if (field.startsWith('|1|')) {
    final List<String> parts = field.split('|');
    if (parts.length != 4) return false;
    try {
      final List<int> salt = base64.decode(parts[2]);
      final String mac = base64.encode(
        Hmac(sha1, salt).convert(utf8.encode(name)).bytes,
      );
      return mac == parts[3];
    } on FormatException {
      return false;
    }
  }
  for (final String entry in field.split(',')) {
    if (entry.startsWith('!') || entry.contains('*') || entry.contains('?')) {
      continue;
    }
    if (entry == name) return true;
  }
  return false;
}

String _q(String s) => "'${s.replaceAll("'", r"'\''")}'";

/// The script inside a remote command built by [DVSshInfraHost], for tests
/// that check it parses.
String dvSshScriptOf(String remote) {
  String r = remote;
  if (r.startsWith('sudo -n ')) r = r.substring('sudo -n '.length);
  if (!r.startsWith("sh -c '") || !r.endsWith("'")) {
    throw FormatException('not a remote script: $remote');
  }
  r = r.substring("sh -c '".length, r.length - 1);
  return r.replaceAll(r"'\''", "'");
}

final RegExp _unitName = RegExp(r'^[A-Za-z0-9@._-]+\.(service|timer)$');
final RegExp _packageName = RegExp(r'^[a-z0-9][a-z0-9+.-]*$');
final RegExp _credentialName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
final RegExp _safePath = RegExp(r'^/[A-Za-z0-9._/-]+$');

/// A host reached over SSH.
class DVSshInfraHost implements DVInfraHost {
  /// Throws [DVSshHostNotPinned] when [knownHostsText] does not pin [host]
  /// on the manifest's port. Nothing runs before that check.
  DVSshInfraHost({
    required String host,
    required this.desired,
    required this.knownHostsPath,
    required String knownHostsText,
    required this.run,
    String Function()? salt,
  })  : _host = host,
        _salt = salt ?? _randomSalt {
    final DVInfraSsh ssh = desired.manifest.ssh;
    if (!dvKnownHostsPins(knownHostsText, host, ssh.port)) {
      throw DVSshHostNotPinned(host, ssh.port, knownHostsPath);
    }
  }

  final String _host;
  final DVInfraDesiredState desired;

  /// Absolute. The only file ssh consults for the host's key.
  final String knownHostsPath;

  /// How `ssh` is run; a fake in tests.
  final DVSshRun run;
  final String Function() _salt;

  static String _randomSalt() {
    final Random random = Random.secure();
    return List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  String get name => _host;

  String get _app => desired.appName;

  List<String> _args(String remote) {
    final DVInfraSsh ssh = desired.manifest.ssh;
    return <String>[
      '-o', 'BatchMode=yes',
      '-o', 'StrictHostKeyChecking=yes',
      '-o', 'UserKnownHostsFile=$knownHostsPath',
      '-o', 'GlobalKnownHostsFile=/dev/null',
      '-o', 'UpdateHostKeys=no',
      '-o', 'ConnectTimeout=20',
      '-p', '${ssh.port}',
      '-l', ssh.user,
      '--',
      _host,
      remote,
    ];
  }

  Future<String> _exec(String what, String script, {List<int>? stdin}) async {
    final String prefix = desired.manifest.ssh.user == 'root' ? '' : 'sudo -n ';
    final DVSshOutput out = await run(
      'ssh',
      _args('${prefix}sh -c ${_q(script)}'),
      stdin: stdin,
    );
    if (out.exitCode != 0) {
      throw DVSshStepFailed(what, out.exitCode, out.stderr);
    }
    return out.stdout;
  }

  @override
  Future<void> apply(
    DVInfraStep step,
    DVInfraResource? resource, {
    String? secretValue,
  }) async {
    final String what = '${step.action.name} ${step.id}';
    switch ((step.action, step.kind)) {
      case (DVInfraAction.install, DVInfraResourceKind.package):
        _require(_packageName, step.id, 'package');
        final String record = '/var/lib/dartvel-infra/$_app/packages';
        await _exec(what, '''
set -eu
export DEBIAN_FRONTEND=noninteractive
p=${_q(step.id)}
if ! dpkg-query -W -f='\${db:Status-Status}' "\$p" 2>/dev/null | grep -qx installed; then
  apt-get update -q
  apt-get install -y -q --no-install-recommends "\$p"
fi
install -d -m 0755 ${_q(record)}
dpkg-query -W -f='\${Version}' "\$p" > ${_q(record)}/"\$p"
''');
      case (DVInfraAction.create, DVInfraResourceKind.user):
        _require(RegExp(r'^[a-z][a-z0-9_]{0,31}$'), step.id, 'user');
        await _exec(what, '''
set -eu
u=${_q(step.id)}
id -u "\$u" >/dev/null 2>&1 || useradd --system --user-group --home-dir "/var/lib/\$u" --no-create-home --shell /usr/sbin/nologin "\$u"
''');
      case (DVInfraAction.write, DVInfraResourceKind.file) ||
            (DVInfraAction.write, DVInfraResourceKind.unit) ||
            (DVInfraAction.write, DVInfraResourceKind.firewall):
        final DVInfraResource r = _resource(resource, step);
        final String? content = r.content;
        final String? path = r.path;
        if (content == null || path == null || r.mode == null || r.owner == null) {
          throw StateError('$what has no content, path, mode or owner to write');
        }
        _require(_safePath, path, 'path');
        final bool unit = step.kind == DVInfraResourceKind.unit;
        final bool firewall = step.kind == DVInfraResourceKind.firewall;
        await _exec(
          what,
          '''
set -eu
target=${_q(path)}
dir=\$(dirname "\$target")
install -d -m 0755 "\$dir"
tmp=\$(mktemp "\$dir/.dartvel.XXXXXX")
trap 'rm -f "\$tmp"' EXIT
cat > "\$tmp"
chmod ${r.mode} "\$tmp"
chown ${_q(r.owner!)} "\$tmp"
${firewall ? 'nft -c -f "\$tmp"' : ':'}
mv -f "\$tmp" "\$target"
trap - EXIT
${unit ? 'systemctl daemon-reload' : ':'}
${firewall ? 'nft -f "\$target"' : ':'}
''',
          stdin: utf8.encode(content),
        );
      case (DVInfraAction.deliver, DVInfraResourceKind.credential):
        _require(_credentialName, step.id, 'credential');
        final DVInfraResource r = _resource(resource, step);
        final String? value = secretValue;
        if (value == null) {
          throw StateError('$what has no value to deliver; nothing was sent');
        }
        final String path = r.path ?? dvInfraCredentialPath(_app, step.id);
        _require(_safePath, path, 'path');
        final String salt = _salt();
        final String mac = dvInfraCredentialMac(salt, value);
        await _exec(
          what,
          '''
set -eu
umask 077
install -d -m 0700 /etc/credstore.encrypted
target=${_q(path)}
tmp=\$(mktemp /etc/credstore.encrypted/.dartvel.XXXXXX)
side=\$(mktemp /etc/credstore.encrypted/.dartvel.XXXXXX)
trap 'rm -f "\$tmp" "\$side"' EXIT
systemd-creds encrypt --name=${_q(step.id)} - "\$tmp"
printf '%s %s\\n' $salt $mac > "\$side"
mv -f "\$tmp" "\$target"
mv -f "\$side" "\$target.dvmac"
trap - EXIT
''',
          stdin: utf8.encode(value),
        );
      case (DVInfraAction.enable, DVInfraResourceKind.unit):
        _require(_unitName, step.id, 'unit');
        await _exec(what, 'set -eu\nsystemctl enable ${_q(step.id)}\n');
      case (DVInfraAction.start, DVInfraResourceKind.unit):
        _require(_unitName, step.id, 'unit');
        await _exec(what, 'set -eu\nsystemctl start ${_q(step.id)}\n');
      case (DVInfraAction.restart, DVInfraResourceKind.unit):
        _require(_unitName, step.id, 'unit');
        await _exec(what, 'set -eu\nsystemctl restart ${_q(step.id)}\n');
      case (DVInfraAction.remove, DVInfraResourceKind.unit):
        _require(_unitName, step.id, 'unit');
        final String path = '/etc/systemd/system/${step.id}';
        await _exec(what, '''
set -eu
u=${_q(step.id)}
f=${_q(path)}
if [ -f "\$f" ] && ! grep -qF ${_q(dvInfraMarker(_app))} "\$f"; then
  echo "\$f is not managed by dartvel infra; not removed" >&2
  exit 3
fi
systemctl disable --now "\$u" 2>/dev/null || true
rm -f "\$f"
systemctl daemon-reload
''');
      case (DVInfraAction.remove, DVInfraResourceKind.file):
        final String path = step.id;
        _require(_safePath, path, 'path');
        if (path.split('/').contains('..') ||
            !(path.startsWith('/etc/caddy/') ||
                path.startsWith('/usr/local/lib/dartvel/$_app/'))) {
          throw StateError('$what: $path is outside what the provisioner writes');
        }
        await _exec(what, '''
set -eu
f=${_q(path)}
[ -f "\$f" ] || exit 0
if ! grep -qF ${_q(dvInfraMarker(_app))} "\$f"; then
  echo "\$f is not managed by dartvel infra; not removed" >&2
  exit 3
fi
rm -f "\$f"
''');
      case (DVInfraAction.remove, DVInfraResourceKind.credential):
        _require(_credentialName, step.id, 'credential');
        final String path = dvInfraCredentialPath(_app, step.id);
        await _exec(what, 'set -eu\nrm -f ${_q(path)} ${_q('$path.dvmac')}\n');
      default:
        throw StateError(
          '${step.action.name} does not apply to a ${step.kind.name}; '
          'the provisioner does not do that',
        );
    }
  }

  static DVInfraResource _resource(DVInfraResource? r, DVInfraStep step) {
    if (r == null || r.kind != step.kind || r.id != step.id) {
      throw StateError('${step.action.name} ${step.id} has no matching resource');
    }
    return r;
  }

  static void _require(RegExp pattern, String value, String what) {
    if (!pattern.hasMatch(value) || value.contains('..')) {
      throw StateError('"$value" is not a $what name the provisioner uses');
    }
  }

  @override
  Future<DVInfraObservation> observe() async {
    final String out = await _exec('observe', dvInfraObserveScript(desired));
    return dvParseInfraObservation(_host, out);
  }
}

/// The script that reports a host, one line per fact.
String dvInfraObserveScript(DVInfraDesiredState desired) {
  final String app = desired.appName;
  final String marker = _q(dvInfraMarker(app));
  final StringBuffer b = StringBuffer()
    ..writeln('set -u')
    ..writeln(
      'if [ -x ${_q('/opt/$app/server')} ]; then echo "release yes"; '
      'else echo "release no"; fi',
    )
    ..writeln('row() {')
    ..writeln('  [ -f "\$2" ] || return 0')
    ..writeln('  s=\$(sha256sum < "\$2" | cut -d" " -f1)')
    ..writeln('  echo "\$1 \$2 \$s \$(stat -c "%a %U" "\$2")"')
    ..writeln('}')
    ..writeln('unitrow() {')
    ..writeln('  e=\$(systemctl is-enabled "\$1" 2>/dev/null) || true')
    ..writeln('  a=\$(systemctl is-active "\$1" 2>/dev/null) || true')
    ..writeln('  f="/etc/systemd/system/\$1"')
    ..writeln('  if [ -f "\$f" ] && grep -qF $marker "\$f"; then')
    ..writeln('    s=\$(sha256sum < "\$f" | cut -d" " -f1)')
    ..writeln('    echo "unit \$1 \$s \$(stat -c "%a %U" "\$f") \${e:-unknown} \${a:-unknown}"')
    ..writeln('  else')
    ..writeln('    echo "unit \$1 - - - \${e:-unknown} \${a:-unknown}"')
    ..writeln('  fi')
    ..writeln('}');

  final List<String> declaredFiles = <String>[];
  final List<String> declaredUnits = <String>[];
  for (final DVInfraResource r in desired.resources) {
    switch (r.kind) {
      case DVInfraResourceKind.package:
        b
          ..writeln('v=\$(dpkg-query -W -f=\'\${db:Status-Status} \${Version}\' ${_q(r.id)} 2>/dev/null) || v=')
          ..writeln('case "\$v" in installed\\ *)')
          ..writeln('  rec=\$(cat ${_q('/var/lib/dartvel-infra/$app/packages/${r.id}')} 2>/dev/null) || rec=')
          ..writeln('  echo "pkg ${r.id} \${v#installed } \${rec:--}";;')
          ..writeln('esac');
      case DVInfraResourceKind.user:
        b.writeln('if id -u ${_q(r.id)} >/dev/null 2>&1; then echo "user ${r.id}"; fi');
      case DVInfraResourceKind.file:
        declaredFiles.add(r.path!);
        b.writeln('row file ${_q(r.path!)}');
      case DVInfraResourceKind.firewall:
        b
          ..writeln('row fw ${_q(r.path!)}')
          ..writeln('echo "fwlive \$(nft list ruleset 2>/dev/null | base64 -w0)"');
      case DVInfraResourceKind.unit:
        declaredUnits.add(r.id);
        b.writeln('unitrow ${_q(r.id)}');
      case DVInfraResourceKind.credential:
        break;
    }
  }

  // Managed files and units no longer declared, so a plan can remove them.
  b
    ..writeln('for f in \$(grep -rlF $marker /etc/caddy ${_q('/usr/local/lib/dartvel/$app')} 2>/dev/null); do')
    ..writeln('  case " ${declaredFiles.join(' ')} " in *" \$f "*) ;; *) row file "\$f";; esac')
    ..writeln('done')
    ..writeln('for f in \$(grep -lF $marker /etc/systemd/system/*.service /etc/systemd/system/*.timer 2>/dev/null); do')
    ..writeln('  u=\$(basename "\$f")')
    ..writeln('  case " ${declaredUnits.join(' ')} " in *" \$u "*) ;; *) unitrow "\$u";; esac')
    ..writeln('done')
    ..writeln('for f in /etc/credstore.encrypted/$app.*; do')
    ..writeln('  [ -e "\$f" ] || continue')
    ..writeln('  case "\$f" in *.dvmac) continue;; esac')
    ..writeln('  n=\${f#/etc/credstore.encrypted/$app.}')
    ..writeln('  if [ -r "\$f.dvmac" ]; then echo "cred \$n \$(cat "\$f.dvmac")"; else echo "cred \$n - -"; fi')
    ..writeln('done');

  for (final String domain in desired.manifest.tls?.domains ?? const <String>[]) {
    final String d = _q(domain);
    b
      ..writeln('c=\$(ls /var/lib/caddy/.local/share/caddy/certificates/*/$d/$d.crt 2>/dev/null | head -n1)')
      ..writeln('e=-')
      ..writeln('if [ -n "\$c" ]; then e=\$(date -d "\$(openssl x509 -enddate -noout -in "\$c" | cut -d= -f2)" +%s 2>/dev/null) || e=-; fi')
      ..writeln('n=\$(journalctl -u caddy --since=-24h -o cat 2>/dev/null | grep -F $d | grep -ciE "could not get certificate|failed to obtain|renew.*error") || n=0')
      ..writeln('if [ "\${n:-0}" -gt 0 ]; then fail=yes; else fail=no; fi')
      ..writeln('echo "cert $domain \${e:--} \$fail"');
  }

  b
    ..writeln('r=\$(cat ${_q('/var/lib/dartvel-infra/$app/last-verified-restore')} 2>/dev/null) || r=')
    ..writeln('echo "restore \${r:--}"');
  return b.toString();
}

final RegExp _sha = RegExp(r'^[0-9a-f]{64}$');
final RegExp _digits = RegExp(r'^\d+$');

/// Reads the report [dvInfraObserveScript] prints.
DVInfraObservation dvParseInfraObservation(String host, String report) {
  bool release = false;
  final List<DVObservedResource> resources = <DVObservedResource>[];
  final Map<String, DVObservedCertificate> certificates =
      <String, DVObservedCertificate>{};
  DateTime? restore;
  DVInfraFirewallRules? live;
  List<String>? fwRow;

  String? dash(String v) => v == '-' ? null : v;
  String mode(String m) => m.padLeft(4, '0');
  DateTime epoch(String v) =>
      DateTime.fromMillisecondsSinceEpoch(int.parse(v) * 1000, isUtc: true);
  Never bad(String line) =>
      throw FormatException('cannot read the host report line "$line"');

  for (final String raw in const LineSplitter().convert(report)) {
    final String line = raw.trim();
    if (line.isEmpty) continue;
    final List<String> t = line.split(RegExp(r'\s+'));
    switch (t.first) {
      case 'release' when t.length == 2 && (t[1] == 'yes' || t[1] == 'no'):
        release = t[1] == 'yes';
      case 'pkg' when t.length == 4:
        resources.add(DVObservedResource(
          kind: DVInfraResourceKind.package,
          id: t[1],
          installedVersion: t[2],
          recordedVersion: dash(t[3]),
        ));
      case 'user' when t.length == 2:
        resources.add(DVObservedResource(kind: DVInfraResourceKind.user, id: t[1]));
      case 'file' when t.length == 5 && _sha.hasMatch(t[2]) && _digits.hasMatch(t[3]):
        resources.add(DVObservedResource(
          kind: DVInfraResourceKind.file,
          id: t[1],
          sha256: t[2],
          mode: mode(t[3]),
          owner: t[4],
        ));
      case 'fw' when t.length == 5 && _sha.hasMatch(t[2]) && _digits.hasMatch(t[3]):
        fwRow = t;
      case 'fwlive' when t.length <= 2:
        try {
          live = dvParseNftRuleset(
            t.length == 1 ? '' : utf8.decode(base64.decode(t[1])),
          );
        } on FormatException {
          bad(line);
        }
      case 'unit' when t.length == 7:
        final bool packaged = t[2] == '-' && t[3] == '-' && t[4] == '-';
        if (!packaged && !(_sha.hasMatch(t[2]) && _digits.hasMatch(t[3]))) bad(line);
        resources.add(DVObservedResource(
          kind: DVInfraResourceKind.unit,
          id: t[1],
          sha256: packaged ? null : t[2],
          mode: packaged ? null : mode(t[3]),
          owner: packaged ? null : t[4],
          enabled: t[5] == 'enabled',
          active: t[6] == 'active',
        ));
      case 'cred' when t.length == 4:
        resources.add(DVObservedResource(
          kind: DVInfraResourceKind.credential,
          id: t[1],
          credentialSalt: dash(t[2]),
          credentialMac: dash(t[3]),
        ));
      case 'cert' when t.length == 4 &&
            (t[2] == '-' || _digits.hasMatch(t[2])) &&
            (t[3] == 'yes' || t[3] == 'no'):
        certificates[t[1]] = DVObservedCertificate(
          notAfter: t[2] == '-' ? null : epoch(t[2]),
          renewalFailing: t[3] == 'yes',
        );
      case 'restore' when t.length == 2 && (t[1] == '-' || _digits.hasMatch(t[1])):
        restore = t[1] == '-' ? null : epoch(t[1]);
      default:
        bad(line);
    }
  }

  if (fwRow != null) {
    resources.add(DVObservedResource(
      kind: DVInfraResourceKind.firewall,
      id: fwRow[1],
      sha256: fwRow[2],
      mode: mode(fwRow[3]),
      owner: fwRow[4],
      firewall: live,
    ));
  }

  return DVInfraObservation(
    host: host,
    resources: resources,
    releasePresent: release,
    certificates: certificates,
    lastVerifiedRestore: restore,
  );
}

/// What a live `nft list ruleset` lets in on the input hook.
///
/// Every base chain on the hook sees a packet; a drop in any is final and an
/// accept is not. So the policy is drop when any input chain drops by policy,
/// and a port is open when every such chain accepts it. An accept rule this
/// cannot read is treated as accepting everything: an unreadable opening is
/// still an opening, and ignoring it would report a closed host.
DVInfraFirewallRules dvParseNftRuleset(String text) {
  final List<({Set<int> tcp, Set<int> udp, bool all})> dropping =
      <({Set<int> tcp, Set<int> udp, bool all})>[];

  bool inChain = false;
  bool input = false;
  String policy = 'accept';
  Set<int> tcp = <int>{};
  Set<int> udp = <int>{};
  bool all = false;

  final RegExp hook = RegExp(r'type filter hook input\b.*\bpolicy (accept|drop);');
  final RegExp port = RegExp(r'^(tcp|udp) dport (\{[^}]*\}|[0-9-]+) accept$');
  const Set<String> benign = <String>{
    'ct state established,related accept',
    'ct state related,established accept',
    'iifname "lo" accept',
    'iif "lo" accept',
    'meta l4proto { icmp, ipv6-icmp } accept',
    'meta l4proto { icmp, icmpv6 } accept',
    'ip protocol icmp accept',
    'ip6 nexthdr ipv6-icmp accept',
    'meta l4proto ipv6-icmp accept',
  };

  Set<int> ports(String spec) {
    final Set<int> out = <int>{};
    for (final String part
        in spec.replaceAll(RegExp(r'[{}]'), '').split(',').map((String s) => s.trim())) {
      if (part.isEmpty) continue;
      final List<String> range = part.split('-');
      final int? from = int.tryParse(range.first);
      final int? to = int.tryParse(range.last);
      if (from == null || to == null || range.length > 2 || from > to || to > 65535) {
        throw FormatException('not a port: $part');
      }
      for (int p = from; p <= to; p++) {
        out.add(p);
      }
    }
    return out;
  }

  for (final String raw in const LineSplitter().convert(text)) {
    final String line = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (line.startsWith('chain ') && line.endsWith('{')) {
      inChain = true;
      input = false;
      policy = 'accept';
      tcp = <int>{};
      udp = <int>{};
      all = false;
      continue;
    }
    if (!inChain) continue;
    if (line == '}') {
      if (input && policy == 'drop') {
        dropping.add((tcp: tcp, udp: udp, all: all));
      }
      inChain = false;
      continue;
    }
    final Match? h = hook.firstMatch(line);
    if (h != null) {
      input = true;
      policy = h.group(1)!;
      continue;
    }
    if (!line.endsWith('accept')) continue;
    if (benign.contains(line)) continue;
    final Match? m = port.firstMatch(line);
    if (m == null) {
      all = true;
      continue;
    }
    (m.group(1) == 'tcp' ? tcp : udp).addAll(ports(m.group(2)!));
  }

  final List<({Set<int> tcp, Set<int> udp, bool all})> restricting =
      dropping.where((({Set<int> tcp, Set<int> udp, bool all}) c) => !c.all).toList();
  if (restricting.isEmpty) {
    return const DVInfraFirewallRules(policy: 'accept', tcpPorts: <int>{});
  }
  Set<int> tcpOpen = restricting.first.tcp;
  Set<int> udpOpen = restricting.first.udp;
  for (final ({Set<int> tcp, Set<int> udp, bool all}) c in restricting.skip(1)) {
    tcpOpen = tcpOpen.intersection(c.tcp);
    udpOpen = udpOpen.intersection(c.udp);
  }
  return DVInfraFirewallRules(policy: 'drop', tcpPorts: tcpOpen, udpPorts: udpOpen);
}
