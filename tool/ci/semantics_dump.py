"""Dump each route's semantics tree as JSON, for the static HTML step.

Flutter web renders to a canvas and emits real DOM only for the semantics
tree. That tree is the structure the application declares -- the same one a
screen reader is given -- so it is what the crawler-visible HTML should be
built from, rather than string literals scraped out of the page source.

Usage:
  semantics_dump.py <chrome> <base-url> <out-dir> <route> [route ...]
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

import websocket

# Walks flt-semantics-host and reports role, heading level, label, href and
# children. Runs in the page because that is where the tree is.
EXTRACT = r"""
(() => {
  const host = document.querySelector('flt-semantics-host');
  if (!host) return '[]';

  const labelOf = (el) => {
    const aria = el.getAttribute('aria-label');
    if (aria) return aria;
    // Flutter puts plain text in a span, or directly in the element for a
    // link. Only this element's own text, not its descendants'.
    let text = '';
    for (const child of el.childNodes) {
      if (child.nodeType === Node.TEXT_NODE) text += child.textContent;
      else if (child.tagName === 'SPAN') text += child.textContent;
    }
    return text.trim();
  };

  const walk = (el) => {
    const out = [];
    for (const child of el.children) {
      const tag = child.tagName.toLowerCase();
      if (tag === 'flt-semantics-scroll-overflow') continue;
      // Flutter emits a heading as a real h1..h6 element rather than as
      // role="heading", so the tag itself carries the level. An earlier
      // version of this walker accepted only <a> and <flt-semantics> and
      // skipped every heading on the page.
      const heading = /^h([1-6])$/.exec(tag);
      const allowed = tag === 'a' || tag === 'flt-semantics' || heading;
      if (!allowed) continue;
      const aria = child.getAttribute('aria-level');
      const node = {
        role: child.getAttribute('role') || (tag === 'a' ? 'link' : null),
        level: heading ? parseInt(heading[1], 10)
                       : (aria ? parseInt(aria, 10) : null),
        label: labelOf(child),
        href: child.getAttribute('href'),
        children: walk(child),
      };
      // A node with no text, no destination and no children says nothing.
      if (!node.label && !node.href && node.children.length === 0) continue;
      out.push(node);
    }
    return out;
  };

  return JSON.stringify(walk(host));
})()
"""


def main():
    chrome_path, base, out_dir = sys.argv[1:4]
    routes = sys.argv[4:]
    os.makedirs(out_dir, exist_ok=True)

    chrome = subprocess.Popen(
        [chrome_path, '--headless=new', '--no-sandbox', '--disable-gpu',
         '--disable-dev-shm-usage', '--user-data-dir=/tmp/dartvel-prerender',
         '--remote-debugging-port=9251', '--remote-allow-origins=*',
         '--window-size=1440,2400', 'about:blank'],
        stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    try:
        deadline = time.time() + 60
        page = None
        while time.time() < deadline:
            try:
                tabs = json.load(
                    urllib.request.urlopen('http://127.0.0.1:9251/json'))
                page = next(t for t in tabs if t['type'] == 'page')
                break
            except Exception:
                time.sleep(0.5)
        if page is None:
            raise SystemExit('the browser never accepted a connection')

        ws = websocket.create_connection(page['webSocketDebuggerUrl'],
                                         timeout=120)
        counter = [0]

        def send(method, **params):
            counter[0] += 1
            ws.send(json.dumps(
                {'id': counter[0], 'method': method, 'params': params}))
            while True:
                message = json.loads(ws.recv())
                if message.get('id') == counter[0]:
                    return message.get('result', {})

        def evaluate(expression):
            return send('Runtime.evaluate', expression=expression,
                        returnByValue=True, awaitPromise=True
                        )['result'].get('value')

        written = 0
        for route in routes:
            send('Page.navigate', url=base.rstrip('/') + route)
            # Poll for the tree rather than sleeping a flat interval: a page
            # that is ready early should not cost the whole budget, and one
            # that never builds a tree must be reported rather than written
            # out empty.
            tree = '[]'
            deadline = time.time() + 30
            while time.time() < deadline:
                time.sleep(0.5)
                tree = evaluate(EXTRACT) or '[]'
                if tree != '[]':
                    break
            name = 'index' if route == '/' else route.strip('/').replace('/', '_')
            with open(os.path.join(out_dir, name + '.json'), 'w') as handle:
                handle.write(tree)
            nodes = len(json.loads(tree))
            print('%-28s %s top-level nodes' % (route, nodes))
            if nodes:
                written += 1

        if written == 0:
            raise SystemExit(
                'no route produced a semantics tree; the pages would ship '
                'with no crawler-visible content at all')
    finally:
        chrome.terminate()


if __name__ == '__main__':
    main()
