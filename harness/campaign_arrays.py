#!/usr/bin/env python3
import argparse
from collections import Counter
import json
from pathlib import Path
import subprocess

from forms_arrays import (
    DottedPair,
    STOBJ_DEFINITION,
    array_definition,
    array_invocation,
    directed_array_cases,
    evaluate_array_case,
    evaluate_stobj_case,
    externalize,
    random_array_cases,
    render_value,
    stobj_cases,
    stobj_definition,
    stobj_invocation,
)


DEFAULT_ACL2 = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"


class SExpressionParser:
    def __init__(self, text, position=0):
        self.text = text
        self.position = position

    def _space(self):
        while self.position < len(self.text) and self.text[self.position].isspace():
            self.position += 1

    def parse(self):
        self._space()
        if self.position >= len(self.text):
            raise ValueError("cannot parse an empty ACL2 value")
        char = self.text[self.position]
        if char == "'":
            self.position += 1
            return self.parse()
        if char == '"':
            return self._string()
        if char == "(":
            return self._list()
        if char == ")":
            raise ValueError(f"unexpected ')' at position {self.position}")
        token = self._token()
        if token.lstrip("+-").isdigit() and token not in ("+", "-"):
            return int(token)
        return token

    def _string(self):
        self.position += 1
        result = []
        while self.position < len(self.text):
            char = self.text[self.position]
            self.position += 1
            if char == '"':
                return "".join(result)
            if char == "\\":
                if self.position >= len(self.text):
                    break
                char = self.text[self.position]
                self.position += 1
            result.append(char)
        raise ValueError("unterminated ACL2 string")

    def _token(self):
        start = self.position
        while (self.position < len(self.text) and
               not self.text[self.position].isspace() and
               self.text[self.position] not in "()'\""):
            self.position += 1
        token = self.text[start:self.position]
        if not token:
            raise ValueError(f"missing token at position {start}")
        return token

    def _list(self):
        self.position += 1
        items = []
        while True:
            self._space()
            if self.position >= len(self.text):
                raise ValueError("unterminated ACL2 list")
            if self.text[self.position] == ")":
                self.position += 1
                return items
            if self.text[self.position] == ".":
                after_dot = self.position + 1
                if after_dot >= len(self.text) or self.text[after_dot].isspace():
                    if not items:
                        raise ValueError("dotted pair has no car")
                    self.position += 1
                    cdr = self.parse()
                    self._space()
                    if self.position >= len(self.text) or self.text[self.position] != ")":
                        raise ValueError("dotted pair must end after its cdr")
                    self.position += 1
                    tail = DottedPair(items[-1], cdr)
                    result = items[:-1] + [tail]
                    for item in reversed(result):
                        tail = item if isinstance(item, DottedPair) else DottedPair(item, tail)
                    return result[0] if len(result) == 1 else result
            items.append(self.parse())


def parse_one(text, position=0):
    parser = SExpressionParser(text, position)
    value = parser.parse()
    return value, parser.position


def write_script(array_cases, state_cases, path):
    parts = ['(in-package "ACL2")']
    for case in array_cases:
        parts.extend((array_definition(case), array_invocation(case)))
    if state_cases:
        parts.append(STOBJ_DEFINITION)
        for case in state_cases:
            parts.extend((stobj_definition(case), stobj_invocation(case)))
    parts.append("(quit)")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n\n".join(parts) + "\n", encoding="utf-8")
    return path


def _completed_output(completed):
    return completed.stdout + ("\nstderr:\n" + completed.stderr if completed.stderr else "")


def run_acl2(array_cases, state_cases, workdir, acl2=DEFAULT_ACL2, timeout=600):
    workdir = Path(workdir)
    script = write_script(array_cases, state_cases, workdir / "arrays.lisp")
    try:
        completed = subprocess.run(
            [acl2], input="\n".join(script.read_text().splitlines()) + "\n",
            cwd=workdir, capture_output=True, text=True, timeout=timeout, check=False,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        (workdir / "acl2.out").write_text(stdout + stderr, encoding="utf-8")
        raise RuntimeError(f"ACL2 timed out after {timeout} seconds; see {workdir / 'acl2.out'}") from exc
    output = _completed_output(completed)
    (workdir / "acl2.out").write_text(output, encoding="utf-8")
    if completed.returncode:
        raise RuntimeError(f"ACL2 exited with status {completed.returncode}; see {workdir / 'acl2.out'}")
    arrays = _extract_results(output, ":ARRAY-AUDIT", 3)
    stobjs = _extract_results(output, ":STOBJ-AUDIT", 3)
    expected_array_ids = {case.id for case in array_cases}
    expected_stobj_ids = {case.id for case in state_cases}
    if set(arrays) != expected_array_ids or set(stobjs) != expected_stobj_ids:
        missing = sorted((expected_array_ids - set(arrays)) |
                         (expected_stobj_ids - set(stobjs)))
        raise RuntimeError(f"ACL2 output is missing results for {missing}; see {workdir / 'acl2.out'}")
    return arrays, stobjs


def _extract_results(output, marker, arity):
    results = {}
    position = 0
    needle = "(" + marker
    while True:
        start = output.find(needle, position)
        if start < 0:
            break
        value, position = parse_one(output, start)
        if not isinstance(value, list) or len(value) != arity:
            raise ValueError(f"malformed {marker} result: {value!r}")
        case_id = value[1]
        if case_id in results:
            raise ValueError(f"duplicate {marker} result for {case_id}")
        results[case_id] = value[2:]
    return results


def first_difference(expected, actual):
    if not isinstance(actual, list) or len(expected) != len(actual):
        return None
    for index, (left, right) in enumerate(zip(expected, actual)):
        if left != right:
            return index
    return None


def audit_results(array_cases, state_cases, array_results, stobj_results):
    mismatches = []
    for case in array_cases:
        expected = externalize(evaluate_array_case(case))
        actual = array_results[case.id][0]
        if actual != expected:
            index = first_difference(expected, actual)
            operation = case.operations[index] if index is not None else None
            mismatches.append({
                "kind": "array",
                "mode": "raw",
                "id": case.id,
                "family": case.family,
                "case": case.as_dict(),
                "observation_index": index,
                "operation": operation,
                "expected": render_value(expected),
                "actual": render_value(actual),
                "expected_observation": render_value(expected[index]) if index is not None else None,
                "actual_observation": render_value(actual[index]) if index is not None else None,
            })
    for case in state_cases:
        expected = externalize(evaluate_stobj_case(case))
        actual = stobj_results[case.id][0]
        if actual != expected:
            index = first_difference(expected, actual)
            mismatches.append({
                "kind": "stobj",
                "mode": "raw",
                "id": case.id,
                "family": "stobj",
                "case": case.as_dict(),
                "observation_index": index,
                "operation": case.operations[index] if index is not None else None,
                "expected": render_value(expected),
                "actual": render_value(actual),
                "expected_observation": render_value(expected[index]) if index is not None else None,
                "actual_observation": render_value(actual[index]) if index is not None else None,
            })
    return mismatches


def run_campaign(array_cases, state_cases, workdir, acl2=DEFAULT_ACL2, timeout=600):
    workdir = Path(workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    corpus = {"arrays": [case.as_dict() for case in array_cases],
              "stobjs": [case.as_dict() for case in state_cases]}
    (workdir / "corpus.json").write_text(json.dumps(corpus, indent=2), encoding="utf-8")
    array_results, stobj_results = run_acl2(
        array_cases, state_cases, workdir, acl2=acl2, timeout=timeout)
    mismatches = audit_results(array_cases, state_cases, array_results, stobj_results)
    with (workdir / "mismatches.jsonl").open("w", encoding="utf-8") as stream:
        for mismatch in mismatches:
            stream.write(json.dumps(mismatch) + "\n")
    operation_coverage = Counter(
        operation[0] for case in array_cases for operation in case.operations)
    new_array = [m for m in mismatches if m["kind"] == "array" and
                 m["mode"] == "raw" and (not m["operation"] or
                 m["operation"][0] != "maybe-flush-and-compress1")]
    summary = {
        "acl2": acl2,
        "array_cases": len(array_cases),
        "stobj_cases": len(state_cases),
        "array_operations": dict(sorted(operation_coverage.items())),
        "raw_array_discrepancies": sum(
            m["kind"] == "array" and m["mode"] == "raw" for m in mismatches),
        "known_maybe_flush_discrepancies": sum(
            m["kind"] == "array" and m["mode"] == "raw" and m["operation"] and
            m["operation"][0] == "maybe-flush-and-compress1" for m in mismatches),
        "new_array_discrepancies": len(new_array),
        "stobj_discrepancies": sum(m["kind"] == "stobj" for m in mismatches),
        "mismatches": str(workdir / "mismatches.jsonl"),
    }
    (workdir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary, mismatches


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--random", type=int, default=200,
                        help="random one-dimensional cases, excluding maybe-flush")
    parser.add_argument("--stobj-random", type=int, default=40)
    parser.add_argument("--no-stobj", action="store_true")
    parser.add_argument("--directed-only", action="store_true")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--acl2", default=DEFAULT_ACL2)
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--workdir", default="audit-arrays-work")
    args = parser.parse_args()
    arrays = directed_array_cases()
    if not args.directed_only:
        arrays += random_array_cases(args.seed, args.random)
    if args.limit:
        arrays = arrays[:args.limit]
    stobjs = [] if args.no_stobj else stobj_cases(
        args.seed, 0 if args.directed_only else args.stobj_random)
    summary, _ = run_campaign(arrays, stobjs, args.workdir,
                              acl2=args.acl2, timeout=args.timeout)
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
