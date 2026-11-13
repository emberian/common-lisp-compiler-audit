#!/usr/bin/env python3
import argparse
from collections import Counter
import json
from pathlib import Path

from forms_lists import (
    NIL,
    T,
    AuditError,
    cons_value,
    eval_form,
    make_corpus,
    render_form,
    render_result,
)
from lisprun import run


IMPLEMENTATIONS = ("sbcl-head", "sbcl-installed", "ccl")


def tuple_tree(value):
    if isinstance(value, list):
        return tuple(tuple_tree(item) for item in value)
    return value


def load_corpus(path):
    tests = json.loads(Path(path).read_text())
    for test in tests:
        test["ast"] = tuple_tree(test["ast"])
    return tests


def replace_test(test, form):
    try:
        expected = render_result(eval_form(form))
        rendered = render_form(form)
    except (AuditError, TypeError, ValueError):
        return None
    updated = dict(test)
    updated["ast"] = form
    updated["form"] = rendered
    updated["expected"] = expected
    return updated


def _quoted_values(value):
    yield NIL
    yield T
    yield 0
    if type(value) is int:
        if value != 1:
            yield 1
        if value > 0:
            yield value - 1
        elif value < 0:
            yield -1
            yield value + 1
    if isinstance(value, tuple) and len(value) == 3 and value[0] == "pair":
        head, tail = value[1], value[2]
        yield head
        yield tail
        yield cons_value(NIL, tail)
        yield cons_value(head, NIL)


def candidates(test):
    form = test["ast"]
    output = []
    if type(form) is int:
        for value in _quoted_values(form):
            if type(value) is int:
                output.append(value)
    if not isinstance(form, tuple) or not form:
        return output
    operation = form[0]
    args = form[1:]
    if operation == "quote" and len(args) == 1:
        output.extend(("quote", value) for value in _quoted_values(args[0]))
    if operation in ("if", "let") and len(args) >= 3:
        output.extend(args[-2:])
    for index, child in enumerate(args, 1):
        if isinstance(child, tuple):
            output.append(child)
        if type(child) is int:
            for value in _quoted_values(child):
                if type(value) is int:
                    modified = list(form)
                    modified[index] = value
                    output.append(tuple(modified))
    minimum = {"list": 0, "append": 0, "list*": 1}.get(operation)
    if minimum is not None and len(args) > minimum:
        for index in range(len(args)):
            output.append((operation, *args[:index], *args[index + 1:]))
    unique = []
    seen = set()
    for candidate in output:
        key = repr(candidate)
        if key != repr(form) and key not in seen:
            seen.add(key)
            updated = replace_test(test, candidate)
            if updated is not None:
                unique.append(updated)
    return unique


def complexity(form):
    if form is NIL:
        return 0
    if type(form) is int:
        return 1 + abs(form)
    if form == T:
        return 1
    if isinstance(form, tuple):
        return 1 + sum(complexity(item) for item in form)
    return 1


def actual_result(test, implementation, workdir, interpreted=False):
    return run([test], implementation, workdir, interpreted=interpreted)[test["id"]]


def is_mismatch(test, implementation, workdir, interpreted=False):
    actual = actual_result(test, implementation, workdir, interpreted)
    return actual.upper() != test["expected"].upper()


def minimize(test, implementation, workdir, interpreted=False):
    current = test
    changed = True
    while changed:
        changed = False
        for candidate in candidates(current):
            if complexity(candidate["ast"]) >= complexity(current["ast"]):
                continue
            if is_mismatch(candidate, implementation, workdir, interpreted):
                current = candidate
                changed = True
                break
    current["actual"] = actual_result(current, implementation, workdir, interpreted)
    return current


def operator_coverage(tests):
    counts = Counter()

    def walk(form):
        if not isinstance(form, tuple) or not form:
            return
        if form[0] == "quote":
            return
        counts[form[0]] += 1
        for child in form[1:]:
            walk(child)

    for test in tests:
        walk(test["ast"])
    return dict(sorted(counts.items()))


def run_in_batches(tests, implementation, workdir, batch_size, interpreted=False):
    results = {}
    for start in range(0, len(tests), batch_size):
        batch = tests[start:start + batch_size]
        results.update(run(batch, implementation, workdir, interpreted=interpreted))
    return results


def run_campaign(
    tests,
    workdir,
    implementations=IMPLEMENTATIONS,
    batch_size=100,
    interpreted=False,
    shrink=True,
):
    workdir = Path(workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    (workdir / "corpus.json").write_text(json.dumps(tests, indent=2))
    mismatches = []
    checks = 0
    for implementation in implementations:
        results = run_in_batches(
            tests, implementation, workdir, batch_size, interpreted=interpreted
        )
        (workdir / f"results-{implementation}.json").write_text(
            json.dumps(results, indent=2, sort_keys=True)
        )
        for test in tests:
            actual = results[test["id"]]
            checks += 1
            if actual.upper() != test["expected"].upper():
                mismatches.append({
                    "implementation": implementation,
                    "test": test,
                    "actual": actual,
                })
    with (workdir / "mismatches.jsonl").open("w") as stream:
        for mismatch in mismatches:
            stream.write(json.dumps(mismatch) + "\n")

    minimized = []
    if shrink:
        for mismatch in mismatches:
            test = minimize(
                mismatch["test"], mismatch["implementation"], workdir / "shrink",
                interpreted=interpreted,
            )
            minimized.append({
                "implementation": mismatch["implementation"],
                "original_id": mismatch["test"]["id"],
                "test": test,
                "actual": test["actual"],
            })
    with (workdir / "minimized.jsonl").open("w") as stream:
        for mismatch in minimized:
            stream.write(json.dumps(mismatch) + "\n")

    return {
        "tests": len(tests),
        "checks": checks,
        "implementations": list(implementations),
        "mismatches": len(mismatches),
        "minimized": len(minimized),
        "operators": operator_coverage(tests),
        "workdir": str(workdir),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--count", type=int, default=400)
    parser.add_argument("--max-depth", type=int, default=3)
    parser.add_argument("--corpus")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--workdir", default="audit-lists")
    parser.add_argument("--batch-size", type=int, default=100)
    parser.add_argument("--interpreted", action="store_true")
    parser.add_argument("--implementations", default=",".join(IMPLEMENTATIONS))
    parser.add_argument("--no-shrink", action="store_true")
    args = parser.parse_args()
    if args.count < 0 or args.max_depth < 1 or args.batch_size < 1:
        parser.error("count and batch-size must be positive; max-depth must be at least 1")
    tests = load_corpus(args.corpus) if args.corpus else make_corpus(
        args.seed, args.count, args.max_depth
    )
    if args.limit:
        tests = tests[:args.limit]
    implementations = tuple(args.implementations.split(","))
    summary = run_campaign(
        tests,
        args.workdir,
        implementations=implementations,
        batch_size=args.batch_size,
        interpreted=args.interpreted,
        shrink=not args.no_shrink,
    )
    print(json.dumps(summary, sort_keys=True))


if __name__ == "__main__":
    main()
