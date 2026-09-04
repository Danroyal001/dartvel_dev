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


class Run:
    """What one run of a suite reported."""

    def __init__(self) -> None:
        self.passed = 0
        self.skipped = 0
        self.failures: list[str] = []
        self.lines: list[str] = []
        self.verdict: bool | None = None
        self.hung = False
        self.returncode = 0
        self.stderr = ""
        self.tester_left = False

    @property
    def died_partway(self) -> bool:
        """Whether the tester ended without finishing what it started.

        Two shapes, both meaning the process went away mid-run rather than a
        test failing. It can leave no verdict at all; or the harness notices
        first, says so in its own words -- 'Shell subprocess ended cleanly.
        Did main() call exit()?' -- and marks everything left as failed, which
        arrives looking exactly like a suite in which fourteen things broke
        at once.
        """
        if self.verdict is None and not self.hung and self.passed > 0:
            return True
        return self.tester_left


def main() -> int:
    command = sys.argv[1:]
    if not command:
        print("usage: live_suite.py <flutter> test <path> ...", file=sys.stderr)
        return 2

    # Run once; run again only if the tester went away mid-suite. On a macOS
    # runner the panel service occasionally takes the process with it, which
    # marks every test after that one as failed and says nothing true about
    # any of them. Two deaths in a row is a failure -- this retries an
    # accident, not a fault.
    run = _run(command)
    if run.died_partway:
        print(
            "  the tester went away mid-run, so the results after it say "
            "nothing; running the suite again"
        )
        run = _run(command)
        if run.died_partway:
            for line in run.lines:
                print(line)
            print("::error::the tester went away mid-run twice")
            return 1

    for line in run.lines:
        print(line)
    print(f"\n{run.passed} passed, {len(run.failures)} failed, {run.skipped} skipped")
    if run.stderr.strip():
        print(run.stderr.strip())

    if run.failures:
        for name in run.failures:
            print(f"::error::{name} failed")
        return 1
    if run.verdict is False:
        print("::error::the reporter says the run did not succeed")
        return 1
    if run.verdict is None and run.passed == 0:
        print("::error::the suite produced no results before it was stopped")
        return 1
    if run.hung:
        print(
            "::warning::every test passed and the tester never exited: "
            "something native is still holding the process open after the "
            "suite. Worth fixing, and not the tests failing."
        )
    elif run.returncode != 0:
        print(
            "::warning::every test passed and the tester exited "
            f"{run.returncode}: something native is still holding the "
            "process open after the suite. Worth fixing, and not the tests "
            "failing."
        )
    return 0


def _run(command: list[str]) -> Run:
    result = Run()

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
    errors: dict[int, list[str]] = {}

    for line in (stdout or "").splitlines():
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
                result.skipped += 1
                result.lines.append(f"  skipped  {name}")
            elif event.get("result") == "success":
                result.passed += 1
                result.lines.append(f"  ok       {name}")
            else:
                result.failures.append(name)
                result.lines.append(f"  FAILED   {name}")
                for detail in errors.get(event.get("testID"), []):
                    result.lines.append(f"           {detail}")
        elif kind == "error":
            # Kept against the test it belongs to and printed with it: an
            # error printed on its own, before the result it explains, is a
            # line nobody connects to anything.
            detail_lines = [
                d for d in str(event.get("error", "")).splitlines() if d.strip()
            ]
            trace = str(event.get("stackTrace", "")).splitlines()
            if trace:
                detail_lines.append(trace[0].strip())
            if any("Shell subprocess ended" in d for d in detail_lines):
                result.tester_left = True
            errors.setdefault(event.get("testID"), []).extend(detail_lines[:6])
            if event.get("testID") is None:
                for d in detail_lines[:6]:
                    result.lines.append(f"  error: {d}")
        elif kind == "done":
            result.verdict = event.get("success")

    if "Shell subprocess ended" in (stderr or ""):
        result.tester_left = True
    result.hung = hung
    result.returncode = process.returncode or 0
    result.stderr = stderr or ""
    return result



if __name__ == "__main__":
    sys.exit(main())
