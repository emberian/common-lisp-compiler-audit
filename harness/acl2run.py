#!/usr/bin/env python3
"""Differential ACL2 logical/raw evaluation on one or more saved images.

Programmatic entry points:
  smoke_tests() -> list of test dictionaries
  write_script(tests, script_path) -> Path
  run(tests, implementation, workdir, timeout=120) -> image result
  run_script(tests, script_path, implementation, timeout=120, image=None)
  compare(image_results, test_ids=None) -> differential report
  differential(tests=None, implementations=None, workdir=None) -> report

A test has an ``id`` and ACL2 ``form``.  Optional integer ``args`` and an ACL2
``declarations`` string are wrapped in a LET, so existing harness tests can be
adapted without changing their forms.  Each test becomes an admitted zero-ary
ACL2 function.  Values are compared using their readably printed representation.
"""

from collections.abc import Mapping
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import tempfile


IMAGES = {
    "sbcl": os.environ.get(
        "ACL2_SBCL", "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
    ),
    "ccl": os.environ.get(
        "ACL2_CCL", "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"
    ),
}
TIMEOUT_SECONDS = 120
MARKER = "ACL2RUN "
SMOKE_TESTS = (
    {"id": "zp-nil", "form": "(zp nil)", "expected": "T"},
    {"id": "zp-rational", "form": "(zp 1/3)", "expected": "T"},
    {"id": "zp-string", "form": '(zp "x")', "expected": "T"},
    {"id": "car-nil", "form": "(car nil)", "expected": "NIL"},
    {"id": "car-rational", "form": "(car 1/3)", "expected": "NIL"},
    {"id": "cdr-nil", "form": "(cdr nil)", "expected": "NIL"},
    {"id": "cdr-symbol", "form": "(cdr 'a)", "expected": "NIL"},
    {
        "id": "unary-truncate-positive",
        "form": "(acl2run-unary-truncate 17/3)",
        "expected": "(5 2/3)",
    },
    {
        "id": "unary-truncate-negative",
        "form": "(acl2run-unary-truncate -17/3)",
        "expected": "(-5 -2/3)",
    },
    {
        "id": "mask-ash-negative",
        "form": "(mask-signed 8 (ash -3 2))",
        "expected": "-12",
    },
    {
        "id": "mask-ash-positive",
        "form": "(mask-signed 8 (ash 3 2))",
        "expected": "12",
    },
    {
        "id": "mask-ash-wrap",
        "form": "(mask-signed 4 (ash 3 3))",
        "expected": "-8",
    },
    {"id": "mask-zero", "form": "(mask-signed 0 (ash 3 100))", "expected": "0"},
)

HELPER_EVENTS = r'''(defun acl2run-unary-truncate (x)
  (declare (xargs :guard (real/rationalp x)))
  (mv (truncate x 1) (rem x 1)))

(defun mask-signed (width value)
  (declare (xargs :guard (and (unsigned-byte-p 16 width)
                              (integerp value))))
  (if (zp width)
      0
      (let ((unsigned (mod value (expt 2 width))))
        (if (logbitp (1- width) value)
            (- unsigned (expt 2 width))
            unsigned))))
'''

RAW_PROBE = r'''(defun acl2run-json-string (string)
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for ch across string
          for code = (char-code ch)
          do (cond ((char= ch #\") (write-string "\\\"" out))
                   ((char= ch #\\) (write-string "\\\\" out))
                   ((< code 32) (format out "\\u~4,'0x" code))
                   (t (write-char ch out))))
    (write-char #\" out)))

(defun acl2run-emit (id phase status &key (value nil valuep) message)
  (format t "~&ACL2RUN {\"id\":~a,\"phase\":~a,\"status\":~a"
          (acl2run-json-string id)
          (acl2run-json-string phase)
          (acl2run-json-string status))
  (when valuep
    (format t ",\"value\":~a"
            (acl2run-json-string
             (write-to-string value :escape t :readably t :pretty nil
                              :circle t :case :upcase :base 10))))
  (when message
    (format t ",\"message\":~a" (acl2run-json-string message)))
  (format t "}~%")
  (finish-output))

(defun acl2run-logical (id fn)
  (handler-case
      (let ((*ev-shortcut-okp* nil))
        (multiple-value-bind (erp val latches)
            (ev-fncall-rec-logical
             fn nil nil (w *the-live-state*) (user-stobj-alist *the-live-state*)
             1000000 nil t nil nil nil nil)
          (declare (ignore latches))
          (if erp
              (acl2run-emit id "logical" "logical_error"
                            :message (write-to-string val :escape t))
              (acl2run-emit id "logical" "value" :value val))))
    (error (condition)
      (acl2run-emit id "logical" "logical_error"
                    :message (princ-to-string condition)))))

(defun acl2run-guard-violated-p (fn)
  (handler-case
      (let ((*ev-shortcut-okp* nil))
        (multiple-value-bind (erp val latches)
            (ev-fncall-rec-logical
             fn nil nil (w *the-live-state*) (user-stobj-alist *the-live-state*)
             1000000 nil nil nil nil nil nil)
          (declare (ignore latches))
          (if (and erp (search "guard" (write-to-string val :escape t)
                               :test #'char-equal))
              t
              nil)))
    (error () :error)))

(defun acl2run-raw (id fn)
  (handler-case
      (let ((values (multiple-value-list (funcall (symbol-function fn)))))
        (acl2run-emit id "raw" "value"
                      :value (if (null (cdr values)) (car values) values)))
    (error (condition)
      (acl2run-emit id "raw"
                    (if (eq (acl2run-guard-violated-p fn) t)
                        "raw_guard_crash"
                        "raw_error")
                    :message (princ-to-string condition)))))

(defun acl2run-compile-and-raw (id fn)
  (handler-case
      (multiple-value-bind (compiled warnings-p failure-p)
          (compile fn)
        (declare (ignore compiled warnings-p))
        (cond (failure-p
               (acl2run-emit id "compile" "host_compilation_failure"
                             :message "COMPILE returned failure-p")
               (acl2run-emit id "raw" "skipped"))
              (t
               (acl2run-emit id "compile" "compiled")
               (acl2run-raw id fn))))
    (error (condition)
      (acl2run-emit id "compile" "host_compilation_failure"
                    :message (princ-to-string condition))
      (acl2run-emit id "raw" "skipped"))))

(defun acl2run-run-case (id fn)
  (if (not (function-symbolp fn (w *the-live-state*)))
      (acl2run-emit id "event" "event_failure"
                    :message "DEFUN was not admitted into the ACL2 world")
      (progn
        (acl2run-emit id "event" "admitted")
        (acl2run-logical id fn)
        (acl2run-compile-and-raw id fn))))

(defun acl2run-run-case-logical (id fn)
  ;; For deliberately guard-violating call terms: raw execution of code
  ;; that assumes its guards is undefined behavior (memory faults), so
  ;; only the logical phase runs; compile/raw are recorded as skipped.
  (if (not (function-symbolp fn (w *the-live-state*)))
      (acl2run-emit id "event" "event_failure"
                    :message "DEFUN was not admitted into the ACL2 world")
      (progn
        (acl2run-emit id "event" "admitted")
        (acl2run-logical id fn)
        (acl2run-emit id "compile" "skipped")
        (acl2run-emit id "raw" "skipped"))))
'''


def smoke_tests():
    return [dict(test) for test in SMOKE_TESTS]


def _lisp_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _validated_tests(tests):
    tests = list(tests)
    ids = set()
    for test in tests:
        test_id = test.get("id")
        form = test.get("form")
        if not isinstance(test_id, str) or not test_id:
            raise ValueError("every ACL2 test must have a nonempty string id")
        if any(ord(ch) < 32 for ch in test_id):
            raise ValueError(f"test id {test_id!r} cannot contain control characters")
        if test_id in ids:
            raise ValueError(f"duplicate ACL2 test id {test_id!r}")
        if not isinstance(form, str) or not form.strip():
            raise ValueError(f"test {test_id!r} must have a nonempty ACL2 form")
        ids.add(test_id)
    return tests


def _function_name(index):
    return f"ACL2RUN-CASE-{index:04d}"


def _test_body(test):
    test_id = test["id"]
    args = test.get("args", {})
    if not isinstance(args, Mapping):
        raise TypeError(f"test {test_id!r} args must be a mapping")
    bindings = []
    names = []
    for name, value in args.items():
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*", name):
            raise ValueError(f"test {test_id!r} has invalid ACL2 variable {name!r}")
        if type(value) is not int:
            raise TypeError(f"test {test_id!r} argument {name!r} must be an exact int")
        names.append(name.upper())
        bindings.append(f"({name.upper()} {value})")
    declarations = test.get("declarations", "")
    if declarations and not bindings:
        bindings.append("(|ACL2RUN-IGNORED| nil)")
        names.append("|ACL2RUN-IGNORED|")
    if not bindings:
        return test["form"]
    ignorable = f"(declare (ignorable {' '.join(names)}))"
    declaration_text = f"    {ignorable}\n"
    if declarations:
        declaration_text += f"    {declarations}\n"
    binding_text = " ".join(bindings)
    return f"(let ({binding_text})\n{declaration_text}    {test['form']})"


def script_source(tests):
    tests = _validated_tests(tests)
    chunks = [
        '(in-package "ACL2")\n',
        "; Logical completion needs EC-CALL to run with guard checking off.\n"
        "; Raw calls below bypass *1* functions and still execute actual raw code.\n"
        "(set-guard-checking :none)\n",
        HELPER_EVENTS,
        ":q\n",
        RAW_PROBE,
        "(lp)\n",
    ]
    for index, test in enumerate(tests):
        name = _function_name(index)
        chunks.append(f"(defun {name} ()\n  {_test_body(test)})\n")
        chunks.append(":q\n")
        chunks.append(f"(acl2run-run-case {_lisp_string(test['id'])} '{name})\n")
        chunks.append("(lp)\n")
    chunks.append("(quit)\n")
    return "".join(chunks)


def write_script(tests, script_path):
    source = script_source(tests)
    path = Path(script_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(source, encoding="utf-8")
    return path


def _output_text(output):
    if output is None:
        return ""
    if isinstance(output, bytes):
        return output.decode("utf-8", errors="replace")
    return output


def _base_result(implementation, image, script_path):
    return {
        "implementation": implementation,
        "image": str(image),
        "script": str(script_path),
        "status": "ok",
        "results": {},
        "protocol_errors": [],
        "stdout": "",
        "stderr": "",
    }


def _parse_records(result, tests, source):
    test_ids = {test["id"] for test in tests}
    records = {}
    for line in result["stdout"].splitlines():
        _, marker, payload = line.partition(MARKER)
        if not marker:
            continue
        try:
            record = json.loads(payload)
        except json.JSONDecodeError as exc:
            result["protocol_errors"].append(f"invalid JSON record: {exc}: {line!r}")
            continue
        test_id = record.get("id")
        phase = record.get("phase")
        key = (test_id, phase)
        if test_id not in test_ids or phase not in {"event", "logical", "compile", "raw"}:
            result["protocol_errors"].append(f"unexpected record: {record!r}")
        elif key in records:
            result["protocol_errors"].append(f"duplicate record for {key!r}")
        else:
            records[key] = record
    for test in tests:
        test_id = test["id"]
        event = records.get((test_id, "event"))
        if event is None:
            result["protocol_errors"].append(f"missing event record for {test_id!r}")
            continue
        result["results"][test_id] = {
            phase: records[(test_id, phase)]
            for phase in ("event", "logical", "compile", "raw")
            if (test_id, phase) in records
        }
        if event.get("status") != "admitted":
            continue
        for phase in ("logical", "compile"):
            if phase not in result["results"][test_id]:
                result["protocol_errors"].append(
                    f"missing {phase} record for {test_id!r}"
                )
        compile_record = records.get((test_id, "compile"), {})
        if compile_record.get("status") == "compiled" and (test_id, "raw") not in records:
            result["protocol_errors"].append(f"missing raw record for {test_id!r}")
    if result["protocol_errors"]:
        result["status"] = "protocol_error"
    result["script_sha256"] = hashlib.sha256(source.encode("utf-8")).hexdigest()


def run_script(tests, script_path, implementation, timeout=TIMEOUT_SECONDS, image=None):
    tests = _validated_tests(tests)
    script_path = Path(script_path)
    source = script_path.read_text(encoding="utf-8")
    image = Path(image or IMAGES[implementation])
    result = _base_result(implementation, image, script_path)
    try:
        completed = subprocess.run(
            [str(image)],
            input=source,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
            cwd=str(image.parent),
        )
    except subprocess.TimeoutExpired as exc:
        result["status"] = "host_timeout"
        result["stdout"] = _output_text(exc.stdout)
        result["stderr"] = _output_text(exc.stderr)
        result["error"] = f"ACL2 image timed out after {timeout} seconds"
        return result
    except OSError as exc:
        result["status"] = "host_launch_failure"
        result["error"] = f"could not run ACL2 image {str(image)!r}: {exc}"
        return result

    result["returncode"] = completed.returncode
    result["stdout"] = completed.stdout
    result["stderr"] = completed.stderr
    _parse_records(result, tests, source)
    if completed.returncode != 0:
        result["status"] = "host_error"
        result["error"] = f"ACL2 image exited with status {completed.returncode}"
    return result


def run(tests, implementation, workdir, timeout=TIMEOUT_SECONDS):
    workdir = Path(workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    script_path = write_script(tests, workdir / f"acl2run-{implementation}.lisp")
    return run_script(tests, script_path, implementation, timeout=timeout)


def compare(image_results, test_ids=None):
    if test_ids is None:
        test_ids = []
        seen = set()
        for image_result in image_results.values():
            for test_id in image_result.get("results", {}):
                if test_id not in seen:
                    seen.add(test_id)
                    test_ids.append(test_id)
    cases = {}
    summary = {
        "tests": len(test_ids),
        "agreements": 0,
        "logical_semantic_disagreements": 0,
        "raw_guard_crashes": 0,
        "host_compilation_failures": 0,
        "raw_execution_errors": 0,
        "logical_errors": 0,
        "event_failures": 0,
    }
    for test_id in test_ids:
        issues = set()
        values = {"logical": {}, "raw": {}}
        observations = {}
        for implementation, image_result in image_results.items():
            observation = image_result.get("results", {}).get(test_id)
            if observation is None:
                continue
            observations[implementation] = observation
            logical = observation.get("logical", {})
            raw = observation.get("raw", {})
            compile_record = observation.get("compile", {})
            event = observation.get("event", {})
            if event.get("status") == "event_failure":
                issues.add("event_failure")
            if logical.get("status") == "logical_error":
                issues.add("logical_error")
            if compile_record.get("status") == "host_compilation_failure":
                issues.add("host_compilation_failure")
            if raw.get("status") == "raw_guard_crash":
                issues.add("raw_guard_crash")
            if raw.get("status") == "raw_error":
                issues.add("raw_execution_error")
            if logical.get("status") == "value":
                values["logical"][implementation] = logical.get("value")
            if raw.get("status") == "value":
                values["raw"][implementation] = raw.get("value")
            if (
                logical.get("status") == "value"
                and raw.get("status") == "value"
                and logical.get("value") != raw.get("value")
            ):
                issues.add("logical_semantic_disagreement")
        if len(set(values["logical"].values())) > 1:
            issues.add("logical_semantic_disagreement")
        if not issues:
            summary["agreements"] += 1
            status = "agreement"
        else:
            if "logical_semantic_disagreement" in issues:
                summary["logical_semantic_disagreements"] += 1
            if "raw_guard_crash" in issues:
                summary["raw_guard_crashes"] += 1
            if "host_compilation_failure" in issues:
                summary["host_compilation_failures"] += 1
            if "raw_execution_error" in issues:
                summary["raw_execution_errors"] += 1
            if "logical_error" in issues:
                summary["logical_errors"] += 1
            if "event_failure" in issues:
                summary["event_failures"] += 1
            status = next(
                category for category in (
                    "logical_semantic_disagreement",
                    "host_compilation_failure",
                    "event_failure",
                    "logical_error",
                    "raw_execution_error",
                    "raw_guard_crash",
                ) if category in issues
            )
        cases[test_id] = {
            "status": status,
            "issues": sorted(issues),
            "values": values,
            "observations": observations,
        }
    for image_result in image_results.values():
        key = {
            "host_launch_failure": "host_launch_failures",
            "host_timeout": "host_timeouts",
            "host_error": "host_errors",
            "protocol_error": "protocol_errors",
        }.get(image_result["status"])
        if key:
            summary[key] = summary.get(key, 0) + 1
    summary["images_requested"] = len(image_results)
    summary["images_run"] = sum(
        result["status"] not in {"host_launch_failure", "host_timeout"}
        for result in image_results.values()
    )
    summary["cross_host"] = summary["images_run"] > 1
    return {"summary": summary, "cases": cases}


def differential(tests=None, implementations=None, workdir=None, timeout=TIMEOUT_SECONDS):
    tests = smoke_tests() if tests is None else _validated_tests(tests)
    implementations = tuple(implementations or IMAGES)
    if workdir is None:
        with tempfile.TemporaryDirectory(prefix="acl2run-") as directory:
            return differential(tests, implementations, directory, timeout)
    workdir = Path(workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    script_path = write_script(tests, workdir / "acl2run-events.lisp")
    image_results = {
        implementation: run_script(
            tests, script_path, implementation, timeout=timeout
        )
        for implementation in implementations
    }
    report = compare(image_results, [test["id"] for test in tests])
    report.update({
        "script": str(script_path),
        "script_sha256": hashlib.sha256(script_path.read_bytes()).hexdigest(),
        "images": image_results,
    })
    return report


def _without_output(report):
    for image_result in report["images"].values():
        image_result.pop("stdout", None)
        image_result.pop("stderr", None)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument("--implementations", default=",".join(IMAGES))
    parser.add_argument("--corpus", help="JSON list of {id, form, args, declarations}")
    parser.add_argument("--workdir", help="keep the identical event script and transcripts")
    parser.add_argument("--timeout", type=int, default=TIMEOUT_SECONDS)
    parser.add_argument("--show-output", action="store_true")
    args = parser.parse_args()
    tests = json.loads(Path(args.corpus).read_text()) if args.corpus else smoke_tests()
    implementations = tuple(args.implementations.split(","))
    unknown = set(implementations) - set(IMAGES)
    if unknown:
        parser.error(f"unknown implementations: {', '.join(sorted(unknown))}")
    report = differential(tests, implementations, args.workdir, args.timeout)
    if not args.show_output:
        _without_output(report)
    print(json.dumps(report, indent=2, sort_keys=True))
    summary = report["summary"]
    failed = any(summary.get(key) for key in (
        "logical_semantic_disagreements",
        "host_compilation_failures",
        "raw_execution_errors",
        "logical_errors",
        "event_failures",
        "host_launch_failures",
        "host_timeouts",
        "host_errors",
        "protocol_errors",
    ))
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
