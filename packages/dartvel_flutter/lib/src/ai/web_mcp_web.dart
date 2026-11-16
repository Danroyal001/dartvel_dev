/// WebMCP in the browser: `document.modelContext.registerTool(tool, {signal})`.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'web_mcp.dart';

/// One abort controller per registered tool, by name: aborting withdraws it,
/// which is how the draft unregisters.
final Map<String, web.AbortController> _registered = <String, web.AbortController>{};

int dvWebMcpRegister(List<DVWebMcpTool> tools) {
  final JSObject document = web.document as JSObject;
  final JSAny? context = document['modelContext'];
  if (context == null || context.isUndefinedOrNull) return 0;
  final JSObject modelContext = context as JSObject;
  if (!modelContext.has('registerTool')) return 0;
  int count = 0;
  for (final DVWebMcpTool tool in tools) {
    _registered.remove(tool.name)?.abort();
    final web.AbortController controller = web.AbortController();
    final JSObject descriptor = JSObject()
      ..['name'] = tool.name.toJS
      ..['description'] = tool.description.toJS
      ..['inputSchema'] = tool.inputSchema.jsify()
      ..['execute'] = ((JSAny? input) {
        final Object? decoded = input.dartify();
        final Map<String, Object?> arguments = decoded is Map
            ? decoded.map((Object? key, Object? value) => MapEntry<String, Object?>('$key', value))
            : <String, Object?>{};
        return tool.execute(arguments).then((Object? result) => result.jsify()).toJS;
      }).toJS;
    final JSObject options = JSObject()..['signal'] = controller.signal;
    try {
      modelContext.callMethod('registerTool'.toJS, descriptor, options);
      _registered[tool.name] = controller;
      count += 1;
    } catch (_) {
      // A browser whose draft differs refuses a descriptor; the page still
      // works for the person, and the other tools are still offered.
    }
  }
  return count;
}

void dvWebMcpUnregisterAll() {
  for (final web.AbortController controller in _registered.values) {
    controller.abort();
  }
  _registered.clear();
}
