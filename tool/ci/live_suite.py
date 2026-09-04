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
import os
import shutil
import subprocess
import sys
import tempfile

def _kill_tree(pid: int) -> None:
    """Ends the tester as well as the tool that started it.

    `flutter` is a launcher: killing it leaves flutter_tester running, and a
    tester that is still running is exactly the thing being timed out.
    """
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/F", "/T", "/PID", str(pid)],
            capture_output=True,
            check=False,
        )
        return
    subprocess.run(["pkill", "-9", "-P", str(pid)], capture_output=True, check=False)
    try:
        os.kill(pid, 9)
    except ProcessLookupError:
        pass
    subprocess.run(["pkill", "-9", "-f", "flutter_tester"], capture_output=True, check=False)


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

    # Written to a file rather than to a pipe. `flutter` spawns the tester,
    # and killing the parent leaves the child holding the pipe open, so
    # anything reading it waits for a process nobody is waiting for -- which
    # is how the cap that exists to stop this suite hanging the job hung the
    # job.
    with tempfile.TemporaryDirectory() as workspace:
        out_path = os.path.join(workspace, "machine.jsonl")
        err_path = os.path.join(workspace, "stderr.txt")
        hung = False
        with open(out_path, "w") as out, open(err_path, "w") as err:
            process = subprocess.Popen(
                [executable] + command[1:] + ["--machine"],
                stdout=out,
                stderr=err,
            )
            try:
                process.wait(timeout=600)
            except subprocess.TimeoutExpired:
                hung = True
                _kill_tree(process.pid)
                try:
                    process.wait(timeout=60)
                except subprocess.TimeoutExpired:
                    pass
        with open(out_path, errors="replace") as out:
            stdout = out.read()
        with open(err_path, errors="replace") as err:
            stderr = err.read()

    names: dict[int, str] = {}
    failures: list[str] = []
    passed = 0
    skipped = 0
    verdict: bool | None = None

    for line in (stdout or '').splitlines():
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
    if (stderr or '').strip():
        print(stderr.strip())

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
    if hung:
        print(
            "::warning::every test passed and the tester never exited: "
            "something native is still holding the process open after the "
            "suite. Worth fixing, and not the tests failing."
        )
    elif process.returncode != 0:
        print(
            "::warning::every test passed and the tester exited "
            f"{process.returncode}: something native is still holding the "
            "process open after the suite. Worth fixing, and not the tests "
            "failing."
        )
    return 0

if __name__ == "__main__":
    sys.exit(main())
