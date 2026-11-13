#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

from constraints import integer_boundary_cases, shift_cases
from generate import generated_tests
from lisprun import run
from semantics import AuditError, eval_term, render_results, render_term

IMPLEMENTATIONS = ("sbcl-head", "sbcl-installed", "ccl")

def make_test(family, index, form, args, declarations):
    try:
        expected = render_results(eval_term(form, args))
    except AuditError:
        expected = "(:ERROR)"
    return {
        "id": f"{family}-{index}",
        "family": family,
        "form": render_term(form),
        "ast": form,
        "args": args,
        "declarations": declarations,
        "expected": expected,
    }

def shift_corpus(seed, count):
    tests = []
    widths = (1, 31, 32, 62, 63, 64, 65, 127, 128)
    declarations = "(declare (type (signed-byte 128) x) (type fixnum count))"
    for case in shift_cases(seed=seed, count=count):
        for width in widths:
            form = ("mask-signed", width, ("ash", ("var", "x"), ("var", "count")))
            args = {"x": case["x"], "count": case["count"]}
            tests.append(make_test("shift-mask", len(tests), form, args, declarations))
    return tests

def division_corpus():
    tests = []
    declarations = "(declare (type fixnum x) (type fixnum count))"
    for x in (-1000, -65, -64, -63, -17, -2, -1, 0, 1, 2, 17, 63, 64, 65, 1000):
        for op in ("truncate", "floor", "round", "ceiling"):
            form = ("mv-list", (op, ("var", "x")))
            tests.append(make_test("unary-division", len(tests), form,
                                   {"x": x, "count": 0}, declarations))
    return tests

def integer_length_corpus():
    tests = []
    declarations = "(declare (type (integer 0 18446744073709551616) x) (type fixnum count))"
    for x in (0, 1, 2, 3, 1 << 63, (1 << 64) - 1, 1 << 64):
        for bound in (0, 1, 2, 31, 32, 62, 63, 64, 65, 127):
            for op in ("lt", "eq"):
                form = (op, ("integer-length", ("var", "x")), bound)
                tests.append(make_test("integer-length-range", len(tests), form,
                                       {"x": x, "count": 0}, declarations))
    return tests

def nested_corpus(seed):
    tests = []
    declarations = "(declare (type (signed-byte 128) x) (type fixnum count))"
    for case in shift_cases(seed=seed + 17, count=12):
        args = {"x": case["x"], "count": case["count"]}
        shift = ("mask-signed", 64, ("ash", ("var", "x"), ("var", "count")))
        form = ("if", ("lt", ("integer-length", ("var", "x")), 64),
                shift,
                ("mv-list", ("truncate", ("var", "x"))))
        tests.append(make_test("nested-control", len(tests), form, args, declarations))
    return tests

def values_corpus():
    tests = []
    declarations = "(declare (type fixnum x) (type fixnum count))"
    for x in (-17, -1, 0, 1, 17):
        args = {"x": x, "count": 0}
        forms = [
            ("mv-list", ("values", ("var", "x"), 0)),
            ("mv-list", ("nth-value", 1, ("truncate", ("var", "x")))),
            ("let", "q", ("truncate", ("var", "x")),
             ("mv-list", ("values", ("var", "q"), 0))),
        ]
        for form in forms:
            tests.append(make_test("multiple-values", len(tests), form, args, declarations))
    return tests

def make_corpus(seed=0, shift_count=12, generated_count=0):
    return (shift_corpus(seed, shift_count) + division_corpus() +
            integer_length_corpus() + nested_corpus(seed) + values_corpus() +
            generated_tests(seed, generated_count, make_test))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--shift-count", type=int, default=12)
    parser.add_argument("--generated", type=int, default=0)
    parser.add_argument("--corpus")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--workdir", default="audit-work")
    parser.add_argument("--interpreted", action="store_true")
    parser.add_argument("--implementations", default=",".join(IMPLEMENTATIONS))
    args = parser.parse_args()
    workdir = Path(args.workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    tests = (json.loads(Path(args.corpus).read_text()) if args.corpus
             else make_corpus(args.seed, args.shift_count, args.generated))
    if args.limit:
        tests = tests[:args.limit]
    (workdir / "corpus.json").write_text(json.dumps(tests, indent=2))
    mismatches = []
    for implementation in args.implementations.split(","):
        results = run(tests, implementation, workdir, interpreted=args.interpreted)
        for test in tests:
            actual = results[test["id"]]
            if actual.upper() != test["expected"].upper():
                mismatches.append({"implementation": implementation,
                                   "test": test, "actual": actual})
    output = workdir / "mismatches.jsonl"
    with output.open("w") as stream:
        for mismatch in mismatches:
            stream.write(json.dumps(mismatch) + "\n")
    print(json.dumps({"tests": len(tests), "implementations": len(args.implementations.split(",")),
                      "mismatches": len(mismatches), "output": str(output)}))

if __name__ == "__main__":
    main()
