#!/usr/bin/env python3
import argparse
import json
import random
import subprocess
from collections import Counter
from fractions import Fraction
from pathlib import Path

from forms_rationals import (
    RationalError,
    as_rational,
    decode_args,
    encode_tree,
    eval_term,
    format_rational,
    parse_value,
    render_results,
    render_term,
    tuple_tree,
)
from lisprun import COMMANDS


IMPLEMENTATIONS = ("sbcl-head", "sbcl-installed", "ccl")
DECLARATIONS = ("(declare (optimize (speed 3) (safety 1)) "
                "(type rational x y z) (type integer n))")
DIRECTED_VALUES = tuple(Fraction(value) for value in (
    0, 1, -1, 2, -2, "1/2", "-1/2", "7/2", "-7/2", "22/7", "-22/7",
    "355/113", "-355/113", 10**40 + 1, -(10**40 + 1),
    Fraction(10**40 + 1, 113), Fraction(-(10**40 + 1), 113),
))
DIRECTED_PAIRS = (
    (Fraction(0), Fraction(1)),
    (Fraction(1), Fraction(2)),
    (Fraction(-7, 2), Fraction(2)),
    (Fraction(7, 2), Fraction(-2)),
    (Fraction(-22, 7), Fraction(1, 3)),
    (Fraction(355, 113), Fraction(-113, 355)),
    (Fraction(10**40 + 1), Fraction(-3)),
    (Fraction(0), Fraction(-5, 7)),
)
DIRECTED_TRIPLES = (
    (Fraction(0), Fraction(0), Fraction(0)),
    (Fraction(-1, 2), Fraction(0), Fraction(1, 2)),
    (Fraction(1, 3), Fraction(1, 3), Fraction(2, 3)),
    (Fraction(2, 3), Fraction(1, 3), Fraction(1, 3)),
    (Fraction(-2), Fraction(-1, 2), Fraction(-1, 3)),
    (Fraction(1), Fraction(2), Fraction(2)),
)


def make_args(x=0, y=1, z=-1, n=0):
    return {"x": as_rational(x), "y": as_rational(y),
            "z": as_rational(z), "n": as_rational(n)}


def make_test(family, index, form, args):
    env = decode_args(args)
    expected = render_results(eval_term(form, env))
    return {
        "id": f"{family}-{index}",
        "family": family,
        "form": render_term(form),
        "ast": encode_tree(form),
        "args": {name: format_rational(value) for name, value in args.items()},
        "declarations": DECLARATIONS,
        "expected": expected,
    }


def guarded(value):
    return ("if", ("=", value, 0), 1, value)


def directed_corpus():
    tests = []

    def add(family, form, args):
        tests.append(make_test(family, len(tests), form, args))

    for x, y in DIRECTED_PAIRS:
        args = make_args(x=x, y=y, z=x + y)
        for form in (
            ("+", ("var", "x"), ("var", "y")),
            ("+", ("var", "x"), ("var", "y"), ("var", "z")),
            ("-", ("var", "x")),
            ("-", ("var", "x"), ("var", "y")),
            ("-", ("var", "x"), ("var", "y"), ("var", "z")),
            ("*", ("var", "x"), ("var", "y")),
            ("*", ("var", "x"), ("var", "y"), ("var", "z")),
            ("/", guarded(("var", "x"))),
            ("/", ("var", "x"), guarded(("var", "y"))),
            ("/", ("var", "x"), guarded(("var", "y")), guarded(("var", "z"))),
        ):
            add("arithmetic", form, args)
        for op in ("floor", "ceiling", "truncate", "round"):
            add("division", (op, ("var", "x")), args)
            add("division", (op, ("var", "x"), guarded(("var", "y"))), args)
        for op in ("mod", "rem"):
            add("remainder", (op, ("var", "x"), guarded(("var", "y"))), args)

    for value in DIRECTED_VALUES:
        args = make_args(x=value)
        for op in ("numerator", "denominator", "signum", "abs"):
            add("parts-sign-abs", (op, ("var", "x")), args)

    for x, y, z in DIRECTED_TRIPLES:
        args = make_args(x=x, y=y, z=z)
        for op in ("=", "/=", "<", ">", "<=", ">="):
            add("comparisons", (op, ("var", "x")), args)
            add("comparisons", (op, ("var", "x"), ("var", "y")), args)
            add("comparisons", (op, ("var", "x"), ("var", "y"), ("var", "z")), args)
        for op in ("max", "min"):
            add("max-min", (op, ("var", "x")), args)
            add("max-min", (op, ("var", "x"), ("var", "y")), args)
            add("max-min", (op, ("var", "x"), ("var", "y"), ("var", "z")), args)

    for base in (0, 1, -1, 2, "-2/3", "355/113"):
        for exponent in (-4, -1, 0, 1, 2, 5):
            args = make_args(x=base, n=exponent)
            base_form = ("var", "x")
            if as_rational(base) == 0 and exponent < 0:
                base_form = guarded(base_form)
            add("expt", ("expt", base_form, ("var", "n")), args)

    args = make_args(x="-7/2", y=0, z="5/3", n=1)
    for form in (
        ("values",),
        ("values", ("var", "x")),
        ("values", ("var", "x"), ("var", "y"), ("var", "z")),
        ("mv-list", ("values", ("var", "x"), ("var", "z"))),
        ("nth-value", 0, ("floor", ("var", "x"), ("var", "z"))),
        ("nth-value", 1, ("floor", ("var", "x"), ("var", "z"))),
        ("nth-value", 3, ("values", ("var", "x"), ("var", "z"))),
        ("let", "q", ("/", ("var", "x"), guarded(("var", "z"))),
         ("values", ("var", "q"), ("numerator", ("var", "q")),
          ("denominator", ("var", "q")))),
        ("/", ("var", "x"), guarded(("var", "y"))),
        ("expt", guarded(("var", "y")), -2),
    ):
        add("values-control-guards", form, args)
    return tests


def random_rational(rng):
    numerators = (0, 1, -1, 2, -2, 7, -7, 22, -22, 355, -355,
                  10**20 + 1, -(10**20 + 1), 10**40 + 1)
    denominators = (1, 2, 3, 4, 5, 7, 8, 16, 113, 127)
    numerator = rng.choice(numerators) if rng.randrange(3) else rng.randrange(-1000, 1001)
    denominator = rng.choice(denominators)
    if rng.randrange(2):
        numerator = -numerator
    return Fraction(numerator, denominator)


def gen_boolean(rng, depth):
    op = rng.choice(("=", "/=", "<", ">", "<=", ">="))
    terms = [gen_rational(rng, depth) for _ in range(rng.randrange(1, 4))]
    return tuple([op] + terms)


def gen_integer(rng):
    if rng.randrange(3):
        return ("var", "n")
    return rng.randrange(-6, 7)


def gen_rational(rng, depth):
    if depth <= 0:
        choice = rng.randrange(5)
        if choice == 0:
            return ("var", "x")
        if choice == 1:
            return ("var", "y")
        if choice == 2:
            return ("var", "z")
        return random_rational(rng)

    next_depth = depth - 1
    choice = rng.randrange(14)
    if choice == 0:
        return ("+", gen_rational(rng, next_depth), gen_rational(rng, next_depth))
    if choice == 1:
        args = [gen_rational(rng, next_depth) for _ in range(rng.randrange(1, 4))]
        return tuple(["-"] + args)
    if choice == 2:
        return ("*", gen_rational(rng, next_depth), gen_rational(rng, next_depth))
    if choice == 3:
        args = [gen_rational(rng, next_depth) for _ in range(rng.randrange(1, 4))]
        if len(args) == 1:
            args[0] = guarded(args[0])
        else:
            args[1:] = [guarded(value) for value in args[1:]]
        return tuple(["/"] + args)
    if choice == 4:
        op = rng.choice(("floor", "ceiling", "truncate", "round"))
        args = [gen_rational(rng, next_depth)]
        if rng.randrange(2):
            args.append(guarded(gen_rational(rng, next_depth)))
        return tuple([op] + args)
    if choice == 5:
        return (rng.choice(("mod", "rem")), gen_rational(rng, next_depth),
                guarded(gen_rational(rng, next_depth)))
    if choice == 6:
        return (rng.choice(("numerator", "denominator")), gen_rational(rng, next_depth))
    if choice == 7:
        return ("expt", guarded(gen_rational(rng, next_depth)), gen_integer(rng))
    if choice == 8:
        return (rng.choice(("signum", "abs")), gen_rational(rng, next_depth))
    if choice == 9:
        args = [gen_rational(rng, next_depth) for _ in range(rng.randrange(1, 4))]
        return tuple([rng.choice(("max", "min"))] + args)
    if choice == 10:
        return ("if", gen_boolean(rng, next_depth), gen_rational(rng, next_depth),
                gen_rational(rng, next_depth))
    if choice == 11:
        return ("let", "q", gen_rational(rng, next_depth), gen_rational(rng, next_depth))
    return gen_rational(rng, 0)


def gen_form(rng, depth):
    choice = rng.randrange(8)
    if choice == 0:
        return ("values", gen_rational(rng, depth), gen_rational(rng, depth))
    if choice == 1:
        return ("mv-list", gen_rational(rng, depth))
    if choice == 2:
        return ("nth-value", rng.randrange(3), gen_rational(rng, depth))
    if choice == 3:
        return gen_boolean(rng, depth)
    return gen_rational(rng, depth)


def generated_tests(seed, count, start):
    rng = random.Random(seed)
    tests = []
    for index in range(count):
        if index == 0 and count:
            args = make_args(x="-22/7", y=0, z="-1/2", n=-3)
        else:
            args = make_args(x=random_rational(rng), y=random_rational(rng),
                             z=random_rational(rng), n=rng.randrange(-6, 7))
        form = gen_form(rng, rng.randrange(1, 5))
        tests.append(make_test("generated", start + index, form, args))
    return tests


def make_corpus(seed=0, generated_count=120):
    directed = directed_corpus()
    return directed + generated_tests(seed, generated_count, len(directed))


def _lisp_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _test_source(test, interpreted):
    test_id = str(test["id"])
    if any(character in test_id for character in "\t\n\r"):
        raise ValueError(f"test id {test_id!r} cannot contain tabs or newlines")
    if set(test["args"]) != {"x", "y", "z", "n"}:
        raise ValueError(f"test {test_id!r} must supply x, y, z, and n")
    arguments = [format_rational(test["args"][name]) for name in ("x", "y", "z", "n")]
    operator = "eval" if interpreted else "compile nil"
    tab = "\t"
    expression = f"""'(lambda (x y z n)
             {test['declarations']}
             {test['form']})"""
    return f"""(handler-case
    (format t "~a{tab}~s~%" {_lisp_string(test_id)}
            (multiple-value-list
             (funcall ({operator} {expression}) {' '.join(arguments)})))
  (error ()
    (format t "~a{tab}(:error)~%" {_lisp_string(test_id)})))
"""


def write_script(tests, script_path, interpreted=False):
    tests = list(tests)
    ids = [str(test["id"]) for test in tests]
    if len(ids) != len(set(ids)):
        raise ValueError("test ids must be unique when printed")
    path = Path(script_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(_test_source(test, interpreted) for test in tests), encoding="utf-8")
    return path


def _output_text(output):
    if output is None:
        return ""
    return output.decode("utf-8", errors="replace") if isinstance(output, bytes) else output


def run(tests, implementation, workdir, interpreted=False, timeout=180):
    if implementation not in COMMANDS:
        raise ValueError(f"unknown implementation {implementation!r}")
    tests = list(tests)
    workdir = Path(workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    script = write_script(tests, workdir / f"rationals-{implementation}.lisp", interpreted)
    command = COMMANDS[implementation] + [str(script)]
    try:
        completed = subprocess.run(command, capture_output=True, text=True,
                                   timeout=timeout, check=False)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError(
            f"{implementation} timed out after {timeout} seconds while running {script}\n"
            f"stdout:\n{_output_text(exc.stdout)}\nstderr:\n{_output_text(exc.stderr)}"
        ) from exc
    except OSError as exc:
        raise RuntimeError(f"could not run {implementation} command {command[0]!r}: {exc}") from exc
    if completed.returncode:
        raise RuntimeError(
            f"{implementation} exited with status {completed.returncode} while running {script}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )

    tests_by_id = {str(test["id"]): test for test in tests}
    results = {}
    for line in completed.stdout.splitlines():
        printed_id, separator, result = line.partition("\t")
        if not separator or printed_id not in tests_by_id:
            continue
        if printed_id in results:
            raise RuntimeError(f"{implementation} printed duplicate results for {printed_id!r}")
        results[printed_id] = result
    missing = [test_id for test_id in tests_by_id if test_id not in results]
    if missing:
        raise RuntimeError(
            f"{implementation} output is missing test ids: {', '.join(map(repr, missing))}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return {test["id"]: results[str(test["id"])] for test in tests}


def matches(expected, actual):
    if expected.upper() == "(:ERROR)" or actual.upper() == "(:ERROR)":
        return expected.upper() == actual.upper()
    try:
        return parse_value(expected) == parse_value(actual)
    except RationalError:
        return expected.upper() == actual.upper()


def updated_test(test, form=None, args=None):
    form = tuple_tree(test["ast"] if form is None else form)
    args = dict(test["args"] if args is None else args)
    try:
        expected = render_results(eval_term(form, decode_args(args)))
        rendered = render_term(form)
    except RationalError:
        return None
    updated = dict(test)
    updated.update(ast=encode_tree(form), form=rendered, args=args, expected=expected)
    return updated


def _literal_candidates(value):
    try:
        value = as_rational(value)
    except RationalError:
        return []

    def complexity(number):
        return (abs(number.numerator).bit_length() + number.denominator.bit_length() +
                (number.numerator < 0) + (number.denominator != 1))

    magnitude = abs(value.numerator) // value.denominator
    truncated = Fraction(-magnitude if value < 0 else magnitude)
    candidates = (Fraction(0), Fraction(1), Fraction(-1), truncated,
                  Fraction(value.numerator), Fraction(1, value.denominator))
    result = []
    for candidate in candidates:
        if (candidate != value and complexity(candidate) < complexity(value) and
                candidate not in result):
            result.append(candidate)
    return result


def form_candidates(test):
    form = tuple_tree(test["ast"])
    if not isinstance(form, tuple) or not form:
        return []
    op = form[0]
    candidates = []
    if op == "if" and len(form) == 4:
        candidates.extend((form[2], form[3]))
    if op == "let" and len(form) == 4:
        candidates.extend((form[2], form[3]))
    if len(form) > 2 and op in ("+", "*", "-", "/", "values", "=", "/=",
                                "<", ">", "<=", ">=", "max", "min"):
        candidates.append(tuple([op] + list(form[1:-1])))
    if len(form) == 3 and op in ("floor", "ceiling", "truncate", "round"):
        candidates.append((op, form[1]))
    for index, child in enumerate(form[1:], 1):
        if isinstance(child, tuple):
            candidates.append(child)
            if child and child[0] == "var" and child[1] in test["args"]:
                value = as_rational(test["args"][child[1]])
                candidates.append(value)
                modified = list(form)
                modified[index] = value
                candidates.append(tuple(modified))
            for grandchild in child[1:]:
                modified = list(form)
                modified[index] = grandchild
                candidates.append(tuple(modified))
        for literal in _literal_candidates(child):
            modified = list(form)
            modified[index] = literal
            candidates.append(tuple(modified))
    output = []
    seen = set()
    for candidate in candidates:
        updated = updated_test(test, form=candidate)
        if updated is not None and updated["form"] != test["form"] and updated["form"] not in seen:
            seen.add(updated["form"])
            output.append(updated)
    return output


def argument_candidates(test):
    output = []
    for name in ("x", "y", "z", "n"):
        for value in _literal_candidates(test["args"][name]):
            args = dict(test["args"])
            args[name] = format_rational(value)
            updated = updated_test(test, args=args)
            if updated is not None:
                output.append(updated)
    return output


def is_mismatch(test, implementation, workdir, interpreted, timeout):
    actual = run([test], implementation, workdir, interpreted, timeout)[test["id"]]
    return not matches(test["expected"], actual)


def minimize(test, implementation, workdir, interpreted=False, timeout=180):
    current = test
    changed = True
    while changed:
        changed = False
        for candidate in form_candidates(current) + argument_candidates(current):
            if is_mismatch(candidate, implementation, workdir, interpreted, timeout):
                current = candidate
                changed = True
                break
    actual = run([current], implementation, workdir, interpreted, timeout)[current["id"]]
    return current, actual


def _parse_implementations(text):
    implementations = tuple(item.strip() for item in text.split(",") if item.strip())
    if not implementations or len(implementations) != len(set(implementations)):
        raise ValueError("implementations must be a nonempty, duplicate-free comma-separated list")
    unknown = set(implementations) - set(IMPLEMENTATIONS)
    if unknown:
        raise ValueError(f"unknown implementations: {', '.join(sorted(unknown))}")
    return implementations


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--generated", type=int, default=120)
    parser.add_argument("--corpus")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--workdir", default="audit-work-rationals")
    parser.add_argument("--interpreted", action="store_true")
    parser.add_argument("--implementations", default=",".join(IMPLEMENTATIONS))
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--no-shrink", action="store_true")
    args = parser.parse_args()
    if args.generated < 0 or args.limit < 0 or args.timeout <= 0:
        parser.error("--generated and --limit must be nonnegative; --timeout must be positive")
    try:
        implementations = _parse_implementations(args.implementations)
    except ValueError as exc:
        parser.error(str(exc))
    workdir = Path(args.workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    tests = (json.loads(Path(args.corpus).read_text()) if args.corpus
             else make_corpus(args.seed, args.generated))
    if args.limit:
        tests = tests[:args.limit]
    (workdir / "corpus.json").write_text(json.dumps(tests, indent=2))

    mismatches = []
    per_implementation = {}
    for implementation in implementations:
        results = run(tests, implementation, workdir, args.interpreted, args.timeout)
        before = len(mismatches)
        for test in tests:
            actual = results[test["id"]]
            if not matches(test["expected"], actual):
                mismatches.append({"implementation": implementation, "original_test": test,
                                   "actual": actual})
        per_implementation[implementation] = {
            "tests": len(tests), "mismatches": len(mismatches) - before,
        }

    minimized_records = []
    for record in mismatches:
        test = record["original_test"]
        if args.no_shrink:
            minimized, minimal_actual = test, record["actual"]
        else:
            minimized, minimal_actual = minimize(
                test, record["implementation"], workdir, args.interpreted, args.timeout
            )
        minimized_records.append({
            "implementation": record["implementation"],
            "original_test": test,
            "actual": record["actual"],
            "test": minimized,
            "minimal_actual": minimal_actual,
        })
    output = workdir / "mismatches.jsonl"
    with output.open("w") as stream:
        for record in minimized_records:
            stream.write(json.dumps(record) + "\n")
    summary = {
        "result": "pass" if not mismatches else "discrepancies",
        "tests": len(tests),
        "implementations": list(implementations),
        "checks": len(tests) * len(implementations),
        "families": dict(sorted(Counter(test["family"] for test in tests).items())),
        "expected_errors": sum(test["expected"].upper() == "(:ERROR)" for test in tests),
        "per_implementation": per_implementation,
        "mismatches": len(mismatches),
        "shrunk": 0 if args.no_shrink else len(minimized_records),
        "output": str(output),
    }
    (workdir / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
