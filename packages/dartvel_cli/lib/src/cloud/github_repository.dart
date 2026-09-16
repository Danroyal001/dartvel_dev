/// The GitHub repository a git remote names, and the API that answers for it.
///
/// A cloud build runs on the repository's own Actions, so the repository is
/// read from the remote rather than configured a second time. The API base is
/// derived from the host -- api.github.com for github.com, `/api/v3` on a
/// GitHub Enterprise Server -- and `GITHUB_API_URL` overrides both, which is
/// the variable Actions itself sets and how a self-hosted install is named.
library;

class DVGitHubRepository {
  const DVGitHubRepository({
    required this.host,
    required this.owner,
    required this.name,
    required this.apiBase,
  });

  final String host;
  final String owner;
  final String name;
  final Uri apiBase;

  String get slug => '$owner/$name';

  /// The repository [remote] names, or null when it is not a URL on a host.
  static DVGitHubRepository? fromRemote(
    String remote, {
    Map<String, String> environment = const <String, String>{},
  }) {
    final String url = remote.trim();
    String? host;
    String? path;
    final RegExpMatch? scp =
        RegExp(r'^(?:[^@/\s]+@)?([^:/\s]+):(?!//)(.+)$').firstMatch(url);
    if (RegExp(r'^[a-z+]+://').hasMatch(url)) {
      final Uri? uri = Uri.tryParse(url);
      if (uri == null || uri.host.isEmpty) return null;
      host = uri.host;
      path = uri.path;
    } else if (scp != null) {
      host = scp.group(1);
      path = scp.group(2);
    }
    if (host == null || path == null) return null;
    final List<String> parts = path
        .replaceAll(RegExp(r'\.git/?$'), '')
        .split('/')
        .where((String s) => s.isNotEmpty)
        .toList();
    if (parts.length != 2) return null;

    final String? override = environment['GITHUB_API_URL'];
    final Uri apiBase = override != null && override.trim().isNotEmpty
        ? Uri.parse(override.trim().replaceAll(RegExp(r'/+$'), ''))
        : host == 'github.com'
            ? Uri.parse('https://api.github.com')
            : Uri.parse('https://$host/api/v3');
    return DVGitHubRepository(
      host: host,
      owner: parts[0],
      name: parts[1],
      apiBase: apiBase,
    );
  }
}
