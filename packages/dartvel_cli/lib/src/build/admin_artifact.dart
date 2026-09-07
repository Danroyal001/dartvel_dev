/// The dashboard the backend serves at the admin mount.
///
/// Everything around this existed already: `dvAdminMount` decides whether a
/// build has an admin and where it is mounted, `dvAdminFor` decides whether
/// a request may see it and answers a hidden one with the same nothing a
/// nonexistent route gets, and the web server serves files out of the admin
/// root. Nothing ever wrote a file into that root, so a project that turned
/// the admin on got a 404 from a mount that was working correctly.
///
/// Three decisions are worth stating, because each of them is a constraint
/// rather than a preference.
///
/// It is a static page, not a second Flutter application. The backend
/// serving it may be a container with no route to the internet and no
/// Flutter toolchain anywhere near it, and a build step that needs one would
/// mean the dashboard exists only where somebody built it.
///
/// It loads nothing from another host. A dashboard that half-renders because
/// a CDN is unreachable is worse than one that was never offered, and this
/// page is the one somebody opens when something is already wrong.
///
/// Every reference in it is relative. The mount path is a default the
/// project is expected to change to something private, and an asset
/// referenced from the root would break the moment somebody took that
/// advice.
library;

import 'dart:convert';

/// The files to write under the admin root, by path relative to it.
///
/// [graph] is `DartvelProjectGraph.toJson()` -- the whole application, not
/// one build target. There is one dashboard per application and it manages
/// every platform that application ships to, so nothing here is per-target
/// and the graph has no target in it to be.
Map<String, String> dvAdminArtifact({
  required Map<String, Object?> graph,
  required String appName,
  required String buildId,
}) {
  return <String, String>{
    'index.html': _html(appName: appName, buildId: buildId),
    'admin.css': _css,
    'admin.js': _js,
    // Written back byte for byte rather than reshaped. A builder that
    // rearranged it would be a second definition of the graph, and the two
    // would disagree the first time either changed.
    'graph.json': const JsonEncoder.withIndent('  ').convert(graph),
  };
}

/// HTML-escapes a value that reaches the page.
///
/// The application name comes from pubspec.yaml, which is not an attacker.
/// This is the page where a mistake matters most, and escaping the one value
/// that reaches the markup costs a function call.
String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String _html({required String appName, required String buildId}) {
  final String name = _escape(appName);
  final String build = _escape(buildId);
  return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<!-- A dashboard is not something to index, and a private mount that turned
     up in a search result would defeat the point of moving it. -->
<meta name="robots" content="noindex, nofollow">
<title>$name &middot; Dartvel</title>
<link rel="stylesheet" href="admin.css">
</head>
<body>
<header>
  <h1>$name</h1>
  <p class="build">build $build</p>
</header>
<nav id="tabs"></nav>
<main id="panel"><p class="empty">Loading.</p></main>
<script src="admin.js"></script>
</body>
</html>
''';
}

const String _css = '''
/* One dashboard for the whole application, in both themes, with no font to
   download: a page served from a machine with no internet has whatever the
   reader's system has. */
:root {
  color-scheme: light dark;
  --ink: #12141a;
  --dim: #5b6272;
  --line: #dfe3ea;
  --ground: #ffffff;
  --panel: #f6f7f9;
}
@media (prefers-color-scheme: dark) {
  :root {
    --ink: #e9ecf2;
    --dim: #9aa2b2;
    --line: #262b36;
    --ground: #0e1016;
    --panel: #161a22;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--ground);
  color: var(--ink);
  font: 14px/1.5 ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto,
      Helvetica, Arial, sans-serif;
}
header { padding: 24px 24px 8px; }
h1 { margin: 0; font-size: 20px; font-weight: 600; }
.build { margin: 4px 0 0; color: var(--dim); font-size: 12px; }
nav {
  display: flex;
  gap: 4px;
  padding: 8px 24px 0;
  border-bottom: 1px solid var(--line);
  flex-wrap: wrap;
}
nav button {
  appearance: none;
  border: 0;
  background: transparent;
  color: var(--dim);
  font: inherit;
  padding: 8px 12px;
  border-bottom: 2px solid transparent;
  cursor: pointer;
}
nav button[aria-current="true"] {
  color: var(--ink);
  border-bottom-color: var(--ink);
}
main { padding: 16px 24px 48px; }
table { border-collapse: collapse; width: 100%; max-width: 960px; }
th, td {
  text-align: left;
  padding: 8px 12px;
  border-bottom: 1px solid var(--line);
  vertical-align: top;
}
th { color: var(--dim); font-weight: 500; font-size: 12px; }
td.file { color: var(--dim); font-family: ui-monospace, monospace; }
.empty { color: var(--dim); }
.count { color: var(--dim); font-size: 12px; margin-left: 6px; }
''';

// Rendering is through textContent throughout. The graph is derived from
// source files and a model or a route can be named anything somebody typed,
// so nothing here builds markup out of a value.
const String _js = r'''
'use strict';

// The four kinds of node the project graph carries, and the columns each is
// worth showing. A kind with no rows still gets a tab, because "no jobs" is
// an answer and a missing tab is not.
var SECTIONS = [
  {key: 'models', title: 'Models', columns: [['name', 'Name'], ['file', 'Declared in']]},
  {key: 'routes', title: 'Routes', columns: [['path', 'Path'], ['file', 'Declared in']]},
  {key: 'functions', title: 'Functions', columns: [['method', 'Method'], ['path', 'Path'], ['file', 'Declared in']]},
  {key: 'jobs', title: 'Jobs', columns: [['name', 'Name'], ['file', 'Declared in']]}
];

function text(tag, value) {
  var node = document.createElement(tag);
  node.textContent = value == null ? '' : String(value);
  return node;
}

function table(section, rows) {
  if (!rows || rows.length === 0) {
    return text('p', 'This application declares no ' + section.title.toLowerCase() + '.');
  }
  var element = document.createElement('table');
  var head = document.createElement('tr');
  for (var c = 0; c < section.columns.length; c++) {
    head.appendChild(text('th', section.columns[c][1]));
  }
  element.appendChild(head);
  for (var r = 0; r < rows.length; r++) {
    var row = document.createElement('tr');
    for (var k = 0; k < section.columns.length; k++) {
      var field = section.columns[k][0];
      var cell = text('td', rows[r][field]);
      if (field === 'file') cell.className = 'file';
      row.appendChild(cell);
    }
    element.appendChild(row);
  }
  return element;
}

function render(graph, active) {
  var tabs = document.getElementById('tabs');
  var panel = document.getElementById('panel');
  tabs.textContent = '';
  panel.textContent = '';

  for (var i = 0; i < SECTIONS.length; i++) {
    (function (section) {
      var rows = graph[section.key] || [];
      var button = text('button', section.title);
      var count = text('span', rows.length);
      count.className = 'count';
      button.appendChild(count);
      button.setAttribute('type', 'button');
      if (section.key === active) button.setAttribute('aria-current', 'true');
      button.addEventListener('click', function () { render(graph, section.key); });
      tabs.appendChild(button);
    })(SECTIONS[i]);
  }

  for (var s = 0; s < SECTIONS.length; s++) {
    if (SECTIONS[s].key !== active) continue;
    panel.appendChild(table(SECTIONS[s], graph[SECTIONS[s].key]));
  }
}

// Relative, so the dashboard keeps working wherever the project mounted it.
fetch('graph.json', {credentials: 'same-origin'})
  .then(function (response) {
    if (!response.ok) throw new Error('graph.json: ' + response.status);
    return response.json();
  })
  .then(function (graph) { render(graph, 'models'); })
  .catch(function (error) {
    var panel = document.getElementById('panel');
    panel.textContent = '';
    // The reason, not a spinner that never stops: this page is the one
    // somebody opens when something is already wrong.
    panel.appendChild(text('p', 'The project graph could not be read. ' + error.message));
  });
''';
