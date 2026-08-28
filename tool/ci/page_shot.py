"""Photograph a page from a running server.

Chrome's own --screenshot fires on the load event, which is before a Flutter
application has started: the capture is a blank white page and looks exactly
like a build that failed. This drives the browser instead, waits for the
semantics tree to exist, and reports the page's own text so a capture of the
wrong page can be told from a capture of the right one.

Usage:
  page_shot.py <base-url> <path> <out.png> [width] [height]
"""
import base64
import json
import subprocess
import sys
import time
import urllib.request

import websocket


def main():
    base, path, out = sys.argv[1:4]
    width = int(sys.argv[4]) if len(sys.argv) > 4 else 1440
    height = int(sys.argv[5]) if len(sys.argv) > 5 else 900

    profile = '/tmp/dartvel-page-shot'
    subprocess.run(['rm', '-rf', profile], check=False)
    chrome = subprocess.Popen(
        ['google-chrome', '--headless=new', '--no-sandbox', '--disable-gpu',
         '--disable-dev-shm-usage', '--user-data-dir=' + profile,
         '--remote-debugging-port=9271', '--remote-allow-origins=*',
         '--window-size=%d,%d' % (width, height),
         base.rstrip('/') + path],
        stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    try:
        deadline = time.time() + 60
        page = None
        while time.time() < deadline:
            try:
                tabs = json.load(
                    urllib.request.urlopen('http://127.0.0.1:9271/json'))
                page = next(t for t in tabs if t['type'] == 'page')
                break
            except Exception:
                time.sleep(0.5)
        if page is None:
            raise SystemExit('the browser never accepted a connection')

        ws = websocket.create_connection(page['webSocketDebuggerUrl'],
                                         timeout=60)
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
                        returnByValue=True)['result'].get('value')

        # Polled rather than slept: a page that is ready early should not cost
        # the whole budget, and one that never draws must be reported rather
        # than photographed blank.
        drawn = False
        deadline = time.time() + 40
        while time.time() < deadline:
            time.sleep(0.5)
            if (evaluate("document.querySelectorAll('flt-semantics').length")
                    or 0) > 3:
                drawn = True
                break
        time.sleep(2)

        data = send('Page.captureScreenshot', format='png').get('data')
        if not data:
            raise SystemExit('the browser returned no image')
        with open(out, 'wb') as handle:
            handle.write(base64.b64decode(data))

        text = (evaluate("document.body.innerText || ''") or '')[:120]
        print('wrote %s (drawn: %s) %r' % (out, drawn, text))
        if not drawn:
            raise SystemExit('the page never built a semantics tree')
    finally:
        chrome.terminate()


if __name__ == '__main__':
    main()
