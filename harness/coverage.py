#!/usr/bin/env python3
import argparse
import json
import re
import subprocess
from pathlib import Path
from lisprun import COMMANDS, HELPER

XFORM = re.compile(r"^xform \(([^)]+)\) (.*)$")
ADDRESS = re.compile(r"#<[^>]*>")

def normalize_trace_line(line):
    match = XFORM.match(line)
    if not match:
        return None
    return match.group(1) + " " + ADDRESS.sub("#<>", match.group(2))

def write_trace_script(tests, path):
    with path.open("w") as stream:
        stream.write("(sb-ext:unlock-package \"SB-VM\")\n")
        stream.write(HELPER)
        for test in tests:
            stream.write(f"(format t \"~&AUDIT-ID {test['id']}~%\")\n")
            stream.write("(let ((sb-c::*show-transforms-p* t) (sb-c::*debug-print-transform* t))\n")
            stream.write("  (handler-case\n")
            stream.write(f"    (compile nil '(lambda (x count) {test['declarations']}\n")
            stream.write("                    (declare (optimize (speed 3) (safety 0)))\n")
            stream.write(f"                    {test['form']}))\n")
            stream.write("    (error (condition) (format t \"~s~%\" (list :compile-error (type-of condition))))))\n")

def trace_coverage(tests, workdir):
    workdir.mkdir(parents=True, exist_ok=True)
    script = workdir / "coverage.lisp"
    write_trace_script(tests, script)
    completed = subprocess.run(
        COMMANDS["sbcl-head"] + [str(script)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=600)
    (workdir / "coverage.out").write_text(completed.stdout)
    if completed.returncode:
        raise RuntimeError(f"SBCL trace failed with status {completed.returncode}")
    coverage = {}
    current = None
    for line in completed.stdout.splitlines():
        if line.startswith("AUDIT-ID "):
            current = line.split(maxsplit=1)[1]
            coverage.setdefault(current, [])
        elif current:
            normalized = normalize_trace_line(line)
            if normalized:
                coverage[current].append(normalized)
    return coverage

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus")
    parser.add_argument("--workdir", default="audit-coverage")
    args = parser.parse_args()
    tests = json.loads(Path(args.corpus).read_text())
    coverage = trace_coverage(tests, Path(args.workdir))
    unique = sorted({line for entries in coverage.values() for line in entries})
    (Path(args.workdir) / "coverage.json").write_text(json.dumps(coverage, indent=2))
    print(json.dumps({"tests": len(tests), "covered": len(coverage), "unique_transforms": len(unique)}))

if __name__ == "__main__":
    main()
