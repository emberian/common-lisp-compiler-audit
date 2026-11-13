#!/usr/bin/env python3
"""Run the ACL2 primitive campaign without changing the shared CL harness."""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import subprocess

from forms_acl2 import LOCAL_BITOPS, make_corpus


HARNESS_DIR = Path(__file__).resolve().parent
DEFAULT_ACL2 = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
HOST_COMMANDS = {
    "sbcl": [os.environ.get("SBCL_INSTALLED", "/opt/homebrew/bin/sbcl"),
             "--noinform", "--disable-debugger", "--script"],
    "ccl": [os.environ.get("CCL", "/Users/ember/dev/ccl/darm64cl"),
            "-n", "--batch", "--load"],
}


def _write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def _write_jsonl(path, rows):
    with path.open("w", encoding="utf-8") as stream:
        for row in rows:
            stream.write(json.dumps(row) + "\n")


def _public_test(test):
    return {key: value for key, value in test.items() if key != "ast"}


def _function_name(index):
    return f"audit-acl2-{index:04d}"


def _acl2_source(tests):
    chunks = ["(set-compile-fns t)", LOCAL_BITOPS]
    for index, test in enumerate(tests):
        name = _function_name(index)
        test_id = test["id"]
        chunks.extend((
            f"(defun {name} () {test['form']})",
            f"(verify-guards {name})",
            f'(cw "AUDIT-BEGIN|{test_id}|compiled~%")',
            f'(cw "AUDIT-RESULT|{test_id}|compiled|~x0~%" ({name}))',
            f'(cw "AUDIT-BEGIN|{test_id}|direct~%")',
            f'(cw "AUDIT-RESULT|{test_id}|direct|~x0~%" {test["form"]})',
        ))
    chunks.append("(quit)")
    return "\n\n".join(chunks) + "\n"


def _run_process(command, workdir, output_path, stdin_path=None, timeout=240):
    stdin = stdin_path.open("r", encoding="utf-8") if stdin_path else None
    try:
        completed = subprocess.run(
            command,
            stdin=stdin,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            cwd=HARNESS_DIR,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        output_path.write_text(stdout + stderr, encoding="utf-8")
        raise RuntimeError(f"command timed out after {timeout}s; see {output_path}") from exc
    except OSError as exc:
        raise RuntimeError(f"could not execute {command[0]!r}: {exc}") from exc
    finally:
        if stdin:
            stdin.close()
    output_path.write_text(completed.stdout + completed.stderr, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(
            f"{command[0]} exited with status {completed.returncode}; see {output_path}"
        )
    return completed.stdout


def _parse_acl2(output, tests):
    expected_keys = {(test["id"], mode) for test in tests
                     for mode in ("direct", "compiled")}
    results = {}
    errors = set()
    current = None
    for line in output.splitlines():
        begin = line.find("AUDIT-BEGIN|")
        result = line.find("AUDIT-RESULT|")
        if begin >= 0:
            _, test_id, mode = line[begin:].strip().split("|", 2)
            current = (test_id, mode)
        elif result >= 0:
            _, test_id, mode, value = line[result:].strip().split("|", 3)
            key = (test_id, mode)
            if key in results:
                raise RuntimeError(f"duplicate ACL2 result for {key}")
            results[key] = value
            current = None
        elif "ACL2 Error" in line and current is not None:
            errors.add(current)
    answer = {}
    for key in expected_keys:
        if key in results:
            answer[key] = results[key]
        elif key in errors:
            answer[key] = ":ERROR"
        else:
            answer[key] = ":NOT-RUN"
    return answer


def run_acl2(tests, acl2, workdir, timeout):
    script = workdir / "acl2-campaign.lisp"
    script.write_text(_acl2_source(tests), encoding="utf-8")
    output = _run_process([acl2], workdir, workdir / "acl2-output.log",
                          stdin_path=script, timeout=timeout)
    return _parse_acl2(output, tests)


def _host_source(tests):
    chunks = []
    for test in tests:
        if test["host_form"] is None:
            continue
        test_id = test["id"]
        form = test["host_form"]
        expressions = {
            "eval": f"(eval '{form})",
            "compiled": f"(funcall (compile nil '(lambda () {form})))",
        }
        for mode, expression in expressions.items():
            chunks.append(f"""(handler-case
  (let ((value {expression}))
    (format t "HOST-RESULT|{test_id}|{mode}|~s~%" value))
  (error ()
    (format t "HOST-RESULT|{test_id}|{mode}|:ERROR~%")))""")
    chunks.append("(quit)")
    return "\n\n".join(chunks) + "\n"


def _parse_host(output, tests, mode):
    expected = {test["id"] for test in tests if test["host_form"] is not None}
    results = {}
    prefix = "HOST-RESULT|"
    for line in output.splitlines():
        if not line.startswith(prefix):
            continue
        _, test_id, actual_mode, value = line.strip().split("|", 3)
        if actual_mode == mode:
            if test_id in results:
                raise RuntimeError(f"duplicate host result for {test_id}")
            results[test_id] = value
    missing = expected - results.keys()
    if missing:
        raise RuntimeError(f"host output is missing results for {sorted(missing)}")
    return results


def run_host(tests, host, workdir, timeout):
    script = workdir / f"host-{host}.lisp"
    script.write_text(_host_source(tests), encoding="utf-8")
    output = _run_process(HOST_COMMANDS[host] + [str(script)], workdir,
                          workdir / f"host-{host}-output.log", timeout=timeout)
    return {mode: _parse_host(output, tests, mode) for mode in ("eval", "compiled")}


def _same(left, right):
    return left.strip().upper() == right.strip().upper()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--acl2", default=DEFAULT_ACL2)
    parser.add_argument("--hosts", default="sbcl,ccl",
                        help="comma-separated host implementations, or an empty string")
    parser.add_argument("--workdir", default=str(HARNESS_DIR / "audit-acl2-work"))
    parser.add_argument("--family", action="append",
                        help="run only this family; may be repeated")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()

    workdir = Path(args.workdir).resolve()
    try:
        workdir.relative_to(HARNESS_DIR)
    except ValueError:
        parser.error(f"--workdir must be inside {HARNESS_DIR}")
    workdir.mkdir(parents=True, exist_ok=True)

    tests = make_corpus()
    if args.family:
        selected = set(args.family)
        tests = [test for test in tests if test["family"] in selected]
    if args.limit:
        tests = tests[:args.limit]
    if not tests:
        parser.error("the selected corpus is empty")
    _write_json(workdir / "corpus.json", [_public_test(test) for test in tests])

    acl2_results = run_acl2(tests, args.acl2, workdir, args.timeout)
    mismatches = []
    result_rows = []
    for test in tests:
        row = _public_test(test)
        row["direct"] = acl2_results[(test["id"], "direct")]
        row["compiled"] = acl2_results[(test["id"], "compiled")]
        result_rows.append(row)
        for mode in ("direct", "compiled"):
            expected = test[f"expected_{mode}"]
            actual = row[mode]
            if not _same(actual, expected):
                mismatches.append({
                    "id": test["id"], "family": test["family"], "form": test["form"],
                    "mode": mode, "logical": test["logical"],
                    "expected": expected, "actual": actual,
                })
    _write_jsonl(workdir / "results.jsonl", result_rows)
    _write_jsonl(workdir / "mismatches.jsonl", mismatches)

    hosts = [host for host in args.hosts.split(",") if host]
    unknown = set(hosts) - HOST_COMMANDS.keys()
    if unknown:
        parser.error(f"unknown hosts: {', '.join(sorted(unknown))}")
    host_rows = []
    host_summary = {}
    for host in hosts:
        outcomes = run_host(tests, host, workdir, args.timeout)
        for mode, results in outcomes.items():
            counts = Counter()
            for test in tests:
                if test["host_form"] is None:
                    continue
                actual = results[test["id"]]
                if actual == ":ERROR":
                    relation = "error"
                elif _same(actual, test["logical"]):
                    relation = "agrees"
                else:
                    relation = "differs"
                counts[relation] += 1
                host_rows.append({
                    "host": host, "mode": mode, "id": test["id"],
                    "family": test["family"], "acl2_form": test["form"],
                    "host_form": test["host_form"], "acl2_logical": test["logical"],
                    "host_actual": actual, "relation": relation,
                })
            host_summary[f"{host}-{mode}"] = dict(counts)
    _write_jsonl(workdir / "host-comparisons.jsonl", host_rows)

    summary = {
        "tests": len(tests),
        "families": dict(Counter(test["family"] for test in tests)),
        "acl2_mismatches": len(mismatches),
        "host_comparisons": host_summary,
        "loghead_logtail": "standard local ACL2 definitions; absent from the trimmed image",
        "output": str(workdir),
    }
    print(json.dumps(summary, indent=2))
    return 1 if mismatches else 0


if __name__ == "__main__":
    raise SystemExit(main())
