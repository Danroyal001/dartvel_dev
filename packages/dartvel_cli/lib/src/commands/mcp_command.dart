import 'dart:io';

import 'package:args/command_runner.dart';

import '../mcp/framework_mcp_server.dart';

/// `dartvel mcp` — serves Dartvel's own tools to a coding agent over MCP.
///
/// The transport is stdio, so the process speaks newline-delimited JSON-RPC on
/// stdin and stdout and must print nothing else to stdout: a stray log line is
/// a parse error to the client.
class McpCommand extends Command<void> {
  @override
  final String name = 'mcp';

  @override
  final String description =
      "Serve Dartvel's project-graph inspectors to a coding agent over MCP.";

  @override
  String get invocation => 'dartvel mcp';

  @override
  Future<void> run() async {
    // Diagnostics go to stderr. stdout belongs to the protocol.
    stderr.writeln(
      'dartvel mcp: serving the project graph for ${Directory.current.path}',
    );
    await DartvelFrameworkMcpServer(root: Directory.current.path).serve();
  }
}
