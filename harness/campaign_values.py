#!/usr/bin/env python3
"""Cross-Lisp campaign for lexical control and multiple values."""

import argparse
from collections import Counter
import json
from pathlib import Path

from forms_values import (
    BOUNDARIES, DECLARATIONS, eval_term, features, generated_terms, render_results,
    render_term,
)
from lisprun import run
from semantics import AuditError


IMPLEMENTATIONS = ("sbcl-head", "sbcl-installed", "ccl")


def make_test(family, index, form, args=None, declarations=DECLARATIONS):
    """Build a runner-compatible test and calculate its independent expectation."""
    if args is None:
        args = {"x": 0, "count": 0}
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


def _directed_specs():
    var_x = ("var", "x")
    return [
        ("let", ("let", (("a", 1), ("b", var_x)),
                 ("values", ("var", "a"), ("var", "b")))),
        ("let-shadow", ("let", (("x", 1), ("y", var_x)),
                        ("values", ("var", "x"), ("var", "y")))),
        ("let-star", ("let*", (("a", var_x), ("b", ("add", ("var", "a"), 1))),
                      ("values", ("var", "a"), ("var", "b")))),
        ("let-star-shadow", ("let*", (("x", 1), ("y", var_x)),
                             ("values", ("var", "x"), ("var", "y")))),
        ("lambda-application",
         ("call", ("lambda", ("a", "b"), ("values", ("var", "b"), ("var", "a"))),
          var_x, 17)),
        ("lambda-nested",
         ("call", ("lambda", ("a",),
                   ("call", ("lambda", ("b",), ("add", ("var", "a"), ("var", "b"))),
                    ("var", "a"))), var_x)),
        ("closure-capture",
         ("let*", (("c", var_x),
                   ("f", ("lambda", ("a",), ("add", ("var", "a"), ("var", "c"))))),
          ("let", (("c", 1000),), ("funcall", ("var", "f"), 5)))),
        ("closure-primary-value",
         ("let", (("f", ("lambda", ("a",), ("values", ("var", "a"), var_x))),),
          ("funcall", ("var", "f"), 7))),
        ("funcall", ("funcall", ("lambda", ("a", "b"), ("sub", ("var", "a"),
                                                               ("var", "b"))),
                     var_x, 3)),
        ("progn-values", ("progn", ("values", 1, 2), ("values", var_x, 3))),
        ("block-return", ("block", "NIL",
                          ("if", ("lt", var_x, 0), ("return", ("values", var_x, 1)),
                           ("values", var_x, 2)), 99)),
        ("block-return-from", ("block", "outer",
                               ("block", "inner", ("return-from", "outer", var_x), 1), 2)),
        ("tagbody-go", ("progn",
                        ("tagbody", ("tag", "start"),
                         ("if", ("lt", var_x, 0), ("go", "negative"), ("go", "other")),
                         ("tag", "negative"), ("values", 1, 2), ("go", "done"),
                         ("tag", "other"), ("values", 3, 4), ("tag", "done")),
                        ("values", var_x, 5))),
        ("tagbody-nested-go", ("progn",
                               ("tagbody", ("tag", "a"),
                                ("if", ("eq", var_x, 0), ("go", "b"), "NIL"),
                                ("values", var_x), ("tag", "b")), var_x)),
        ("values-zero", ("values",)),
        ("values-one", ("values", var_x)),
        ("values-many", ("values", var_x, 0, -1, "T", "NIL")),
        ("multiple-value-bind",
         ("multiple-value-bind", ("a", "b", "c"), ("values", var_x, 2),
          ("values", ("var", "a"), ("var", "b"), ("var", "c")))),
        ("multiple-value-bind-progn",
         ("multiple-value-bind", ("a", "b"), ("floor", var_x, 3),
          ("values", ("var", "b")), ("values", ("var", "a"), ("var", "b")))),
        ("mv-let", ("mv-let", ("a", "b", "c"), ("values", var_x, 2),
                    ("values", ("var", "c"), ("var", "b"), ("var", "a")))),
        ("mv-let-division", ("mv-let", ("q", "r"), ("truncate", var_x, 3),
                             ("values", ("var", "r"), ("var", "q")))),
        ("nth-value", ("nth-value", 1, ("values", var_x, 2, 3))),
        ("nth-value-missing", ("nth-value", 4, ("values", var_x, 2))),
        ("nth-value-division", ("nth-value", 1, ("floor", var_x, 3))),
        ("and-values", ("and", "T", var_x, ("values", 7, 8))),
        ("and-short-circuit", ("and", "NIL", ("truncate", 1, 0))),
        ("or-values", ("or", "NIL", var_x, ("values", 7, 8))),
        ("or-multiple-values", ("or", "NIL", "NIL", ("values", 7, 8))),
        ("or-short-circuit", ("or", "T", ("truncate", 1, 0))),
        ("not", ("not", ("eq", var_x, 0))),
        ("implies", ("implies", ("lt", var_x, 0), ("eq", var_x, 0))),
        ("iff", ("iff", ("lt", var_x, 0), ("not", ("eq", var_x, 0)))),
    ]


def directed_corpus():
    tests = []
    for family, form in _directed_specs():
        for x in (-17, -1, 0, 1, 17):
            tests.append(make_test(family, len(tests), form, {"x": x, "count": 0}))
    return tests


def unary_division_corpus():
    tests = []
    for x in (-1000, -65, -64, -63, -17, -2, -1, 0, 1, 2, 17, 63, 64, 65, 1000):
        for op in ("truncate", "floor", "round", "ceiling"):
            form = ("mv-list", (op, ("var", "x")))
            tests.append(make_test("unary-division", len(tests), form,
                                   {"x": x, "count": 0}))
    return tests


def generated_corpus(seed=0, count=400, max_depth=4):
    tests = []
    rng_values = BOUNDARIES
    for index, form in enumerate(generated_terms(seed, count, max_depth)):
        selector = (index * 1103515245 + seed) % len(rng_values)
        count_value = ((index * 37 + seed) % 41) - 20
        args = {"x": rng_values[selector], "count": count_value}
        tests.append(make_test("generated-values", index, form, args))
    return tests


def make_corpus(seed=0, generated=400, max_depth=4):
    return directed_corpus() + unary_division_corpus() + generated_corpus(
        seed, generated, max_depth
    )


def add_negative_controls(tests, count=4):
    """Add deliberately wrong expectations; every one must be reported as a mismatch."""
    if count <= 0:
        return []
    preferred = ("let", "closure-capture", "tagbody-go", "multiple-value-bind",
                 "mv-let", "implies", "unary-division")
    selected = []
    for family in preferred:
        match = next((test for test in tests if test["family"] == family), None)
        if match is not None:
            selected.append(match)
        if len(selected) == count:
            break
    controls = []
    for index, original in enumerate(selected):
        control = dict(original)
        control["id"] = f"negative-control-{index}"
        control["family"] = "negative-control"
        control["negative_control"] = True
        control["control_of"] = original["id"]
        control["expected"] = "(1)" if original["expected"] == "(0)" else "(0)"
        controls.append(control)
    return controls


def tuple_tree(value):
    return tuple(tuple_tree(item) for item in value) if isinstance(value, list) else value


def replace_test(test, form, preserve_expected=False):
    updated = dict(test)
    updated["ast"] = form
    updated["form"] = render_term(form)
    if not preserve_expected:
        try:
            updated["expected"] = render_results(eval_term(form, test["args"]))
        except AuditError:
            updated["expected"] = "(:ERROR)"
    return updated


def _candidate_children(form):
    if not isinstance(form, tuple) or not form:
        return []
    op = form[0]
    arguments = form[1:]
    if op in ("let", "let*") and arguments:
        return ([initial for _, initial in arguments[0]] + list(arguments[1:]))
    if op == "lambda":
        return list(arguments[1:])
    if op in ("multiple-value-bind", "mv-let"):
        return list(arguments[1:])
    if op in ("call", "funcall"):
        return list(arguments[1:])
    if op in ("block",):
        return list(arguments[1:])
    if op in ("return-from", "nth-value"):
        return list(arguments[1:])
    if op == "tagbody":
        return [item for item in arguments
                if not (isinstance(item, tuple) and item and item[0] == "tag")]
    if op in ("var", "go", "return"):
        return list(arguments) if op == "return" else []
    return list(arguments)


def candidates(test):
    """Produce deterministic, validity-checked one-step simplifications."""
    form = test["ast"]
    raw = []
    if isinstance(form, tuple) and form:
        raw.extend(child for child in _candidate_children(form) if isinstance(child, tuple))
        if form[0] == "if" and len(form) == 4:
            raw.extend((form[2], form[3]))
        if form[0] in ("let", "let*") and len(form) > 2:
            raw.append(form[-1])
        if form[0] in ("progn", "block") and len(form) > 2:
            raw.append(form[-1])
        if form[0] in ("multiple-value-bind", "mv-let") and len(form) > 3:
            raw.append(form[-1])
        if form[0] in ("values", "and", "or", "progn") and len(form) > 2:
            for index in range(1, len(form)):
                if form[0] != "progn" or index < len(form) - 1:
                    raw.append(form[:index] + form[index + 1:])
        for index, child in enumerate(form[1:], 1):
            if isinstance(child, int) and not isinstance(child, bool):
                for value in (0, 1, -1, child - 1, child + 1):
                    modified = list(form)
                    modified[index] = value
                    raw.append(tuple(modified))
    if isinstance(form, int) and not isinstance(form, bool):
        raw.extend((0, 1, -1))
    if isinstance(form, tuple) and len(form) == 2 and form[0] == "var":
        if form[1] in test["args"]:
            raw.append(test["args"][form[1]])
    raw.extend((0, 1))

    output = []
    seen = {test["form"]}
    preserve = bool(test.get("negative_control"))
    for form_candidate in raw:
        try:
            candidate = replace_test(test, form_candidate, preserve_expected=preserve)
            eval_term(form_candidate, test["args"])
        except (AuditError, KeyError, IndexError, TypeError):
            continue
        if candidate["form"] not in seen:
            seen.add(candidate["form"])
            output.append(candidate)
    return output


def mismatch(test, implementation, workdir):
    actual = run([test], implementation, workdir)[test["id"]]
    return actual.upper() != test["expected"].upper()


def minimize(test, implementation, workdir, max_steps=100):
    """Greedily shrink a mismatch while preserving that exact implementation mismatch."""
    current = dict(test)
    current["ast"] = tuple_tree(current["ast"])
    current = replace_test(current, current["ast"],
                           preserve_expected=bool(current.get("negative_control")))
    for _ in range(max_steps):
        changed = False
        for candidate in candidates(current):
            if mismatch(candidate, implementation, workdir):
                current = candidate
                changed = True
                break
        if not changed:
            break
    return current


def _write_jsonl(path, records):
    with path.open("w", encoding="utf-8") as stream:
        for record in records:
            stream.write(json.dumps(record) + "\n")


def _coverage(tests):
    operators = Counter()
    families = Counter()
    for test in tests:
        if test.get("negative_control"):
            continue
        families[test["family"]] += 1
        operators.update(features(tuple_tree(test["ast"])))
    return {"families": dict(sorted(families.items())),
            "operators": dict(sorted(operators.items()))}


def _minimize_records(records, workdir, max_steps, limit=0):
    minimized = []
    selected = records if limit <= 0 else records[:limit]
    for record in selected:
        implementation = record["implementation"]
        test = record["test"]
        reduced = minimize(test, implementation, workdir / implementation, max_steps)
        actual = run([reduced], implementation, workdir / implementation)[reduced["id"]]
        minimized.append({
            "implementation": implementation,
            "original": {"id": test["id"], "form": test["form"],
                         "expected": test["expected"], "actual": record["actual"]},
            "test": reduced,
            "actual": actual,
        })
        print(json.dumps({"minimized": test["id"], "implementation": implementation,
                          "form": reduced["form"], "actual": actual}))
    return minimized


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--generated", type=int, default=400)
    parser.add_argument("--max-depth", type=int, default=4)
    parser.add_argument("--negative-controls", type=int, default=4)
    parser.add_argument("--corpus")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--workdir", default="audit-values-work")
    parser.add_argument("--interpreted", action="store_true")
    parser.add_argument("--implementations", default=",".join(IMPLEMENTATIONS))
    parser.add_argument("--shrink-controls", action="store_true")
    parser.add_argument("--control-shrink-limit", type=int, default=3)
    parser.add_argument("--max-shrink-steps", type=int, default=100)
    args = parser.parse_args(argv)

    implementations = tuple(args.implementations.split(","))
    workdir = Path(args.workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    ordinary = (json.loads(Path(args.corpus).read_text(encoding="utf-8")) if args.corpus
                else make_corpus(args.seed, args.generated, args.max_depth))
    ordinary = [test for test in ordinary if not test.get("negative_control")]
    if args.limit:
        ordinary = ordinary[:args.limit]
    controls = [] if args.corpus else add_negative_controls(ordinary, args.negative_controls)
    tests = ordinary + controls
    (workdir / "corpus.json").write_text(json.dumps(tests, indent=2), encoding="utf-8")

    mismatches = []
    detected_controls = []
    failed_controls = []
    per_implementation = {}
    for implementation in implementations:
        results = run(tests, implementation, workdir, interpreted=args.interpreted)
        unexpected = detected = 0
        for test in tests:
            actual = results[test["id"]]
            differs = actual.upper() != test["expected"].upper()
            record = {"implementation": implementation, "test": test, "actual": actual}
            if test.get("negative_control"):
                if differs:
                    detected_controls.append(record)
                    detected += 1
                else:
                    failed_controls.append(record)
            elif differs:
                mismatches.append(record)
                unexpected += 1
        per_implementation[implementation] = {
            "tests": len(tests), "mismatches": unexpected,
            "negative_controls_detected": detected,
        }
        print(json.dumps({"implementation": implementation,
                          **per_implementation[implementation]}))

    _write_jsonl(workdir / "mismatches.jsonl", mismatches)
    _write_jsonl(workdir / "negative-controls.jsonl", detected_controls)
    _write_jsonl(workdir / "failed-negative-controls.jsonl", failed_controls)
    minimized = _minimize_records(mismatches, workdir / "minimized",
                                  args.max_shrink_steps)
    minimized_controls = []
    if args.shrink_controls:
        minimized_controls = _minimize_records(
            detected_controls, workdir / "minimized-controls", args.max_shrink_steps,
            args.control_shrink_limit,
        )
    _write_jsonl(workdir / "minimized.jsonl", minimized)
    _write_jsonl(workdir / "minimized-controls.jsonl", minimized_controls)

    unary = [record for record in mismatches if record["test"]["family"] == "unary-division"]
    ccl_unary = [record for record in unary if record["implementation"] == "ccl"]
    summary = {
        "seed": args.seed,
        "generated": args.generated,
        "ordinary_tests": len(ordinary),
        "negative_controls": len(controls),
        "executions": len(tests) * len(implementations),
        "implementations": per_implementation,
        "mismatches": len(mismatches),
        "negative_controls_detected": len(detected_controls),
        "negative_controls_failed": len(failed_controls),
        "ccl_unary_division": {
            "tests": sum(test["family"] == "unary-division" for test in ordinary),
            "mismatches": len(ccl_unary),
        },
        "coverage": _coverage(tests),
        "workdir": str(workdir),
    }
    (workdir / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary))
    controls_expected = len(controls) * len(implementations)
    return 1 if mismatches or failed_controls or len(detected_controls) != controls_expected else 0


if __name__ == "__main__":
    raise SystemExit(main())
