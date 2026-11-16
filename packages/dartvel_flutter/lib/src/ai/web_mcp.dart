/// WebMCP: a page offering its tools to the browser's agent.
///
/// WebMCP is a draft of the W3C Web Machine Learning Community Group
/// (`document.modelContext.registerTool`, Draft Community Group Report,
/// https://webmachinelearning.github.io/webmcp/), not a W3C standard. A
/// browser that implements it lets an agent the person uses call a page's
/// tools instead of reading and clicking the page. Dartvel registers each
/// AI-tool backend function there (`web_mcp.g.dart`), through the client
/// function the app itself calls, so the function's policy decides as it
/// does for a button.
///
/// Feature-detected: where the browser has no `document.modelContext`, and on
/// every target that is not the web, registering does nothing.
library;

import 'web_mcp_stub.dart' if (dart.library.js_interop) 'web_mcp_web.dart'
    as platform;

/// One tool a page offers: what the agent reads to decide when to call it,
/// and what runs when it does.
class const DVWebMcpTool({
  required final String name,
  required final String description,
  required final Map<String, Object?> inputSchema,
  required final Future<Object?> Function(Map<String, Object?> input) execute,
});

/// The browser's WebMCP registry, where there is one.
abstract final class DVWebMcp {
  /// Registers [tools] with the browser's agent and returns how many were
  /// registered: none off the web, or where the browser has no WebMCP. A
  /// tool registered earlier under the same name is replaced.
  static int register(List<DVWebMcpTool> tools) => platform.dvWebMcpRegister(tools);

  /// Withdraws every tool this page registered.
  static void unregisterAll() => platform.dvWebMcpUnregisterAll();
}
