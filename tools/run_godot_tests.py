#!/usr/bin/env python3
"""Run Project EGO's standalone Godot tests after a clean editor scan."""

from __future__ import annotations

import os
import re
import shutil
import signal
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
COMPILE_TIMEOUT_SECONDS = 120
TEST_TIMEOUT_SECONDS = 60
STANDALONE_RE = re.compile(
    r"^\s*extends\s+(?:SceneTree|MainLoop)\s*(?:#.*)?$", re.MULTILINE
)
REQUIRES_PACK_SKIP_RE = re.compile(
    r"^SKIP requires-pack: packs/genesis/data is absent;", re.MULTILINE
)
ERROR_MARKERS = (
    ("parser error", re.compile(r"\b(?:Parse|Parser) Error:", re.IGNORECASE)),
    ("compiler error", re.compile(r"\b(?:Compile|Compiler) Error:", re.IGNORECASE)),
    ("script error", re.compile(r"^\s*SCRIPT ERROR:", re.IGNORECASE | re.MULTILINE)),
    (
        "script load error",
        re.compile(r"^\s*ERROR:.*Failed to load script\b", re.IGNORECASE | re.MULTILINE),
    ),
)
EXPLICIT_FAILURE_MARKERS = (
    re.compile(r"\bFAIL(?:ED)?\b"),
    re.compile(r"\b[1-9]\d*\s+FAILURES?\b"),
)


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: str
    stderr: str
    timed_out: bool = False


def locate_godot() -> str:
    """Resolve GODOT_BIN or locate godot-ci on PATH."""
    requested = os.environ.get("GODOT_BIN")
    if requested:
        resolved = shutil.which(requested)
        if resolved:
            return resolved
        candidate = Path(requested).expanduser()
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate.resolve())
        raise FileNotFoundError(f"GODOT_BIN does not name an executable: {requested}")

    resolved = shutil.which("godot-ci")
    if resolved:
        return resolved
    raise FileNotFoundError("godot-ci was not found on PATH (set GODOT_BIN to override)")


def is_standalone_script(source: str) -> bool:
    """Return whether source declares a standalone SceneTree/MainLoop script."""
    return STANDALONE_RE.search(source) is not None


def discover_standalone_scripts(repository_root: Path) -> tuple[list[Path], list[Path]]:
    """Return deterministically ordered runnable and non-runnable test scripts."""
    candidates = sorted(
        repository_root.joinpath("tests").glob("test_*.gd"),
        key=lambda path: path.as_posix(),
    )
    runnable: list[Path] = []
    covered_by_compile: list[Path] = []
    for path in candidates:
        source = path.read_text(encoding="utf-8")
        (runnable if is_standalone_script(source) else covered_by_compile).append(path)
    return runnable, covered_by_compile


def find_error_markers(stdout: str, stderr: str) -> list[str]:
    """Identify Godot parse/compiler/script errors and explicit test failures."""
    combined = f"{stdout}\n{stderr}"
    findings = [name for name, pattern in ERROR_MARKERS if pattern.search(combined)]
    if any(pattern.search(combined) for pattern in EXPLICIT_FAILURE_MARKERS):
        findings.append("explicit test failure")
    return findings


def is_requires_pack_skip(script: Path, stdout: str, stderr: str) -> bool:
    """Recognize the repository's one clean missing-local-pack result."""
    return (
        script.name == "test_scenario_requires_pack.gd"
        and REQUIRES_PACK_SKIP_RE.search(f"{stdout}\n{stderr}") is not None
    )


def _terminate_process_tree(process: subprocess.Popen[str]) -> None:
    if os.name == "posix":
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        return

    # CREATE_NEW_PROCESS_GROUP does not make Popen.kill recursive on Windows.
    subprocess.run(
        ["taskkill", "/PID", str(process.pid), "/T", "/F"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
        timeout=5,
    )
    if process.poll() is None:
        process.kill()


def run_process(command: Sequence[str], timeout_seconds: int) -> ProcessResult:
    """Run a command at the repository root with a hard process-tree timeout."""
    popen_kwargs: dict[str, object] = {}
    if os.name == "posix":
        popen_kwargs["start_new_session"] = True
    elif os.name == "nt":
        popen_kwargs["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP

    process = subprocess.Popen(
        list(command),
        cwd=REPOSITORY_ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        **popen_kwargs,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
        return ProcessResult(process.returncode, stdout, stderr)
    except subprocess.TimeoutExpired:
        _terminate_process_tree(process)
        stdout, stderr = process.communicate()
        return ProcessResult(process.returncode, stdout, stderr, timed_out=True)


def print_process_output(result: ProcessResult) -> None:
    """Relay captured process output without altering its content."""
    if result.stdout:
        sys.stdout.write(result.stdout)
        sys.stdout.flush()
    if result.stderr:
        sys.stderr.write(result.stderr)
        sys.stderr.flush()


def failure_reasons(result: ProcessResult) -> list[str]:
    reasons: list[str] = []
    if result.timed_out:
        reasons.append("timeout")
    if result.returncode != 0:
        reasons.append(f"exit {result.returncode}")
    reasons.extend(find_error_markers(result.stdout, result.stderr))
    return reasons


def print_summary(compile_status: str, passed: int, skipped: int, failed: int) -> None:
    print(
        f"SUMMARY compile={compile_status} pass={passed} skip={skipped} fail={failed}"
    )


def main() -> int:
    try:
        godot = locate_godot()
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        print_summary("FAIL", 0, 0, 0)
        return 2

    cache = REPOSITORY_ROOT / ".godot"
    if cache.exists():
        shutil.rmtree(cache)

    compile_command = [
        godot,
        "--headless",
        "--path",
        str(REPOSITORY_ROOT),
        "--editor",
        "--quit",
    ]
    print("COMPILE clean editor scan")
    compile_result = run_process(compile_command, COMPILE_TIMEOUT_SECONDS)
    print_process_output(compile_result)
    compile_failures = failure_reasons(compile_result)
    if compile_failures:
        print(f"COMPILE FAIL: {', '.join(compile_failures)}", file=sys.stderr)
        print_summary("FAIL", 0, 0, 0)
        return 1
    print("COMPILE PASS")

    runnable, covered_by_compile = discover_standalone_scripts(REPOSITORY_ROOT)
    for path in covered_by_compile:
        print(f"COMPILE-ONLY {path.relative_to(REPOSITORY_ROOT).as_posix()}")

    passed = 0
    skipped = 0
    failed = 0
    for script in runnable:
        relative = script.relative_to(REPOSITORY_ROOT).as_posix()
        print(f"TEST {relative}")
        result = run_process(
            [godot, "--headless", "--path", str(REPOSITORY_ROOT), "--script", relative],
            TEST_TIMEOUT_SECONDS,
        )
        print_process_output(result)
        reasons = failure_reasons(result)
        if reasons:
            failed += 1
            print(f"TEST FAIL {relative}: {', '.join(reasons)}", file=sys.stderr)
        elif is_requires_pack_skip(script, result.stdout, result.stderr):
            skipped += 1
            print(f"TEST SKIP {relative}")
        else:
            passed += 1
            print(f"TEST PASS {relative}")

    print_summary("PASS", passed, skipped, failed)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
