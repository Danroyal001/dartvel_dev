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

    browser = subprocess.Popen(
        [firefox, "--profile", profile, "--headless", "--marionette",
         "--window-size=1280,900", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    try:
        client = Marionette()
        client.send("WebDriver:NewSession", {"capabilities": {}})
        client.send("WebDriver:Navigate", {"url": url})

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

        # A moment more for the first frame after layout settles.
        time.sleep(2)
        shot = client.send("WebDriver:TakeScreenshot", {"full": True})
        open(out, "wb").write(base64.b64decode((shot or {})["value"]))
        print("wrote %s (body laid out: %s)" % (out, drawn))
        if not drawn:
            raise SystemExit("the page never laid out a body taller than 100px")
    finally:
        browser.terminate()


if __name__ == "__main__":
    main()
