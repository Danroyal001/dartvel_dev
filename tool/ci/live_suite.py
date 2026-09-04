"""Runs a native live suite and reports what the tests said.

The macOS and Windows binding suites exercise real AppKit panels and Win32
dialogs. Both have reached the state where every test passes and the tester
process then does not exit -- AppKit and the shell hold onto things after a
panel has been answered, and the harness waits for a process that is not
coming back. Judged on the exit code alone, a suite in which nothing failed
goes red, which says the wrong thing about the code under test and hides the
run in which something really does fail.

So the verdict comes from the reporter, which is the thing that actually
knows: any test failing fails the step. A process that then would not exit is
printed as a warning, loudly, because it is worth fixing and worth seeing --
it just is not the tests failing.
"""

import json
import shutil
import subprocess
import sys

def main() -> int:
    command = sys.argv[1:]
    if not command:
        print("usage: live_suite.py <flutter> test <path> ...", file=sys.stderr)
        return 2

    # Resolved rather than handed over as written. On Windows `flutter` is a
    # batch file, and CreateProcess is given the name exactly: without the
    # extension it finds nothing and reports a missing file, which reads as
    # "flutter is not installed" on a runner that has just used it.
    executable = shutil.which(command[0]) or command[0]

    process = subprocess.run(
        [executable] + command[1:] + ["--machine"],
        capture_output=True,
        text=True,
        timeout=1800,
    )

    names: dict[int, str] = {}
    failures: list[str] = []
    passed = 0
    skipped = 0
    verdict: bool | None = None

    for line in process.stdout.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = event.get("type")
        if kind == "testStart":
            test = event.get("test", {})
            names[test.get("id")] = test.get("name", "")
        elif kind == "testDone":
            name = names.get(event.get("testID"), "")
            if name.startswith("loading ") or event.get("hidden"):
                continue
            if event.get("skipped"):
                skipped += 1
                print(f"  skipped  {name}")
            elif event.get("result") == "success":
                passed += 1
                print(f"  ok       {name}")
            else:
                failures.append(name)
                print(f"  FAILED   {name}")
        elif kind == "error":
            print(f"  error: {event.get('error')}")
            if event.get("stackTrace"):
                print(f"    {event['stackTrace'].splitlines()[0]}")
        elif kind == "done":
            verdict = event.get("success")

    print(f"\n{passed} passed, {len(failures)} failed, {skipped} skipped")
    if process.stderr.strip():
        print(process.stderr.strip())

    if failures:
        for name in failures:
            print(f"::error::{name} failed")
        return 1
    if verdict is False:
        print("::error::the reporter says the run did not succeed")
        return 1
    if verdict is None:
        # No verdict at all means the tester died before finishing, which is
        # a real failure however few tests had failed by then.
        print("::error::the suite produced no verdict; the tester did not finish")
        return 1
    if process.returncode != 0:
        print(
            "::warning::every test passed and the tester exited "
            f"{process.returncode}: something native is still holding the "
            "process open after the suite. Worth fixing, and not the tests "
            "failing."
        )
    return 0

if __name__ == "__main__":
    sys.exit(main())
