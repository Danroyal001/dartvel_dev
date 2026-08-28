"""Load a page in Firefox, wait for it to draw, and photograph it.

`firefox --screenshot` fires on the load event. A Flutter application has
barely started by then: it bootstraps asynchronously after load, so the
capture is a blank white page and looks exactly like an extension that failed
to install.

Marionette is Firefox's own automation protocol, built into the browser, so
this needs no driver binary. Messages are `<byte-length>:<json>` and each is
`[0, id, "Command", params]`.

Usage:
  firefox_shot.py <firefox> <profile> <url> <out.png> [settle-seconds]
"""
import base64
import json
import socket
import subprocess
import sys
import time


class Marionette:
    def __init__(self, host="127.0.0.1", port=2828, timeout=120):
        self._id = 0
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            try:
                self._sock = socket.create_connection((host, port), timeout=60)
                break
            except OSError as error:  # Firefox has not opened the port yet.
                last = error
                time.sleep(0.5)
        else:
            raise SystemExit("marionette never accepted a connection: %s" % last)
        self._buffer = b""
        self._read()  # The handshake it sends unprompted.

    def _read(self):
        while b":" not in self._buffer:
            self._buffer += self._sock.recv(65536)
        length, _, rest = self._buffer.partition(b":")
        size = int(length)
        while len(rest) < size:
            rest += self._sock.recv(65536)
        self._buffer = rest[size:]
        return json.loads(rest[:size])

    def send(self, command, params=None):
        self._id += 1
        body = json.dumps([0, self._id, command, params or {}]).encode()
        self._sock.sendall(b"%d:%s" % (len(body), body))
        message = self._read()
        # [1, id, error, result]
        if len(message) > 2 and message[2]:
            raise SystemExit("%s failed: %s" % (command, message[2]))
        return message[3] if len(message) > 3 else None


def main():
    firefox, profile, url, out = sys.argv[1:5]
    settle = float(sys.argv[5]) if len(sys.argv) > 5 else 12.0

    # Kept, not discarded. With devtools.console.stdout.content the page's
    # own console lands here, and that is the only place a Flutter start-up
    # error appears -- the DOM shows a blank body either way.
    console = open(out + ".console.log", "wb")
    browser = subprocess.Popen(
        # -remote-allow-system-access is required for Marionette's chrome
        # context, which is the only way to reach a moz-extension:// URL.
        # Firefox says so itself when it is missing: "System access is
        # required. Start Firefox with -remote-allow-system-access".
        [firefox, "--profile", profile, "--headless", "--marionette",
         "-remote-allow-system-access",
         "--window-size=1280,900", "about:blank"],
        stdout=console, stderr=subprocess.STDOUT)
    try:
        client = Marionette()
        client.send("WebDriver:NewSession", {"capabilities": {}})

        # moz-extension:// is a privileged URL, and Marionette refuses to
        # navigate to one from content: "Navigation to ... is not allowed in
        # this context". Opening it from the chrome context with the system
        # principal is the way in -- the same thing typing it in the address
        # bar does.
        before = set(client.send("WebDriver:GetWindowHandles") or [])
        client.send("Marionette:SetContext", {"value": "chrome"})
        client.send("WebDriver:ExecuteScript", {
            "script": (
                "const [target] = arguments;"
                "gBrowser.selectedTab = gBrowser.addTab(target, {"
                "  triggeringPrincipal:"
                "    Services.scriptSecurityManager.getSystemPrincipal(),"
                "});"
            ),
            "args": [url],
        })
        client.send("Marionette:SetContext", {"value": "content"})

        # The tab that appeared, rather than whichever handle is first.
        deadline = time.time() + 30
        while time.time() < deadline:
            handles = set(client.send("WebDriver:GetWindowHandles") or [])
            fresh = handles - before
            if fresh:
                client.send("WebDriver:SwitchToWindow",
                            {"handle": sorted(fresh)[0]})
                break
            time.sleep(0.5)
        else:
            raise SystemExit("the extension page never opened a tab")

        # The wait the load event does not give. Polled rather than a flat
        # sleep so a page that is ready early does not cost the whole budget,
        # and so a page that never draws is reported as that rather than as a
        # blank screenshot.
        deadline = time.time() + settle
        drawn = False
        while time.time() < deadline:
            result = client.send("WebDriver:ExecuteScript", {
                "script": "return document.body ? "
                          "document.body.getBoundingClientRect().height : 0;",
                "args": [],
            })
            height = (result or {}).get("value") or 0
            if height > 100:
                drawn = True
                break
            time.sleep(0.5)

        # Always, not only on failure. A page that draws can still be the
        # wrong page: the application's own 404 has text, colour and layout,
        # and passed the capture check while the extension opened a route
        # that did not exist.
        body = client.send("WebDriver:ExecuteScript", {
            "script": "return (document.body ? document.body.innerText : '')"
                      ".slice(0, 300);",
            "args": [],
        })
        print("page text: %r" % ((body or {}).get("value") or ""))

        if not drawn:
            # What the page thinks happened, so a blank capture says why. A
            # picture of nothing is the same picture whether the script was
            # blocked, the bundle 404'd, or the application threw.
            report = client.send("WebDriver:ExecuteScript", {
                "script": (
                    "return JSON.stringify({"
                    "  title: document.title,"
                    "  readyState: document.readyState,"
                    "  bodyHtml: (document.body && document.body.innerHTML || "
                    "    '').slice(0, 400),"
                    "  scripts: Array.from("
                    "    document.querySelectorAll('script')"
                    "  ).map(s => s.src || '(inline)'),"
                    "  flutterLoader: typeof window._flutter,"
                    "  views: document.querySelectorAll("
                    "    'flutter-view, flt-glass-pane, flt-scene-host'"
                    "  ).length,"
                    "  errors: window.__dartvelErrors || null"
                    "});"
                ),
                "args": [],
            })
            print("page state: %s" % (report or {}).get("value"))

            probe = client.send("WebDriver:ExecuteAsyncScript", {
                "script": (
                    "const done = arguments[arguments.length - 1];"
                    "const out = {};"
                    "try {"
                    "  new WebAssembly.Module(new Uint8Array("
                    "    [0,97,115,109,1,0,0,0]));"
                    "  out.wasm = 'ok';"
                    "} catch (e) { out.wasm = 'blocked: ' + e; }"
                    "fetch('canvaskit/canvaskit.js')"
                    "  .then(r => { out.canvaskit = r.status; })"
                    "  .catch(e => { out.canvaskit = 'failed: ' + e; })"
                    "  .then(() => done(JSON.stringify(out)));"
                ),
                "args": [],
            })
            print("capability probe: %s" % (probe or {}).get("value"))

        # A moment more for the first frame after layout settles.
        time.sleep(2)
        shot = client.send("WebDriver:TakeScreenshot", {"full": True})
        open(out, "wb").write(base64.b64decode((shot or {})["value"]))
        print("wrote %s (body laid out: %s)" % (out, drawn))
        if not drawn:
            raise SystemExit("the page never laid out a body taller than 100px")
    finally:
        browser.terminate()
        try:
            browser.wait(timeout=20)
        except subprocess.TimeoutExpired:
            browser.kill()
        console.close()
        text = open(out + ".console.log", errors="replace").read()
        if text.strip():
            print("--- browser console ---")
            print(text[-4000:])


if __name__ == "__main__":
    main()
