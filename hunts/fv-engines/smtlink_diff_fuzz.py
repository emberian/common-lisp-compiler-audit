#!/usr/bin/env python3
"""Differential fuzzer: exact ACL2 ground semantics vs SMTLink active *SMT-functions* + Z3 5.4.1."""

from fractions import Fraction
import itertools
import random
import sys

SMT_DIR = "/Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/z3_interface"
sys.path.insert(0, SMT_DIR)

import z3  # noqa: E402
from ACL2_to_Z3 import ACL22SMT  # noqa: E402


def acl2_truthy(v):
    return not (v == ("bool", False))


def acl2_num(v):
    kind, val = v
    return val if kind == "rat" else Fraction(0)


def eval_acl2(expr):
    op = expr[0]
    if op in ("bool", "rat"):
        return expr
    if op == "equal":
        return ("bool", eval_acl2(expr[1]) == eval_acl2(expr[2]))
    if op == "<":
        return ("bool", acl2_num(eval_acl2(expr[1])) < acl2_num(eval_acl2(expr[2])))
    if op == "+":
        return ("rat", acl2_num(eval_acl2(expr[1])) + acl2_num(eval_acl2(expr[2])))
    if op == "*":
        return ("rat", acl2_num(eval_acl2(expr[1])) * acl2_num(eval_acl2(expr[2])))
    if op == "/":
        d = acl2_num(eval_acl2(expr[1]))
        return ("rat", Fraction(0) if d == 0 else Fraction(1) / d)
    if op == "-":
        return ("rat", -acl2_num(eval_acl2(expr[1])))
    if op == "not":
        return ("bool", not acl2_truthy(eval_acl2(expr[1])))
    if op == "implies":
        return ("bool", (not acl2_truthy(eval_acl2(expr[1]))) or acl2_truthy(eval_acl2(expr[2])))
    if op == "if":
        return eval_acl2(expr[2]) if acl2_truthy(eval_acl2(expr[1])) else eval_acl2(expr[3])
    raise ValueError(f"Unknown op: {op}")


def eval_smt_py(smt, expr):
    op = expr[0]
    if op == "bool":
        return expr[1]
    if op == "rat":
        v = expr[1]
        return v.numerator if v.denominator == 1 else z3.Q(v.numerator, v.denominator)
    if op == "equal":
        return smt.equal(eval_smt_py(smt, expr[1]), eval_smt_py(smt, expr[2]))
    if op == "<":
        return smt.lt(eval_smt_py(smt, expr[1]), eval_smt_py(smt, expr[2]))
    if op == "+":
        return smt.plus(eval_smt_py(smt, expr[1]), eval_smt_py(smt, expr[2]))
    if op == "*":
        return smt.times(eval_smt_py(smt, expr[1]), eval_smt_py(smt, expr[2]))
    if op == "/":
        return smt.reciprocal(eval_smt_py(smt, expr[1]))
    if op == "-":
        return smt.negate(eval_smt_py(smt, expr[1]))
    if op == "not":
        return smt.notx(eval_smt_py(smt, expr[1]))
    if op == "implies":
        return smt.implies(eval_smt_py(smt, expr[1]), eval_smt_py(smt, expr[2]))
    if op == "if":
        return smt.ifx(eval_smt_py(smt, expr[1]), eval_smt_py(smt, expr[2]), eval_smt_py(smt, expr[3]))
    raise ValueError(f"Unknown op: {op}")


def z3_proves(py_expr):
    if isinstance(py_expr, bool):
        return py_expr
    s = z3.Solver()
    s.add(z3.Not(py_expr))
    return s.check() == z3.unsat


ATOMS = [
    ("bool", False),
    ("bool", True),
    ("rat", Fraction(0)),
    ("rat", Fraction(1)),
    ("rat", Fraction(-1)),
    ("rat", Fraction(2)),
    ("rat", Fraction(1, 2)),
]


def gen_expr(rng, depth):
    if depth <= 0 or rng.random() < 0.35:
        return rng.choice(ATOMS)
    op = rng.choice(["equal", "<", "+", "*", "/", "-", "not", "implies", "if"])
    if op in ("not", "/", "-"):
        return (op, gen_expr(rng, depth - 1))
    if op == "if":
        return ("if", gen_expr(rng, depth - 1), gen_expr(rng, depth - 1), gen_expr(rng, depth - 1))
    return (op, gen_expr(rng, depth - 1), gen_expr(rng, depth - 1))


def main():
    rng = random.Random(20261113)
    smt = ACL22SMT()
    unsound = {}
    errors = {}

    # Exhaustive binary/unary operator checks over ATOMS
    for a, b in itertools.product(ATOMS, ATOMS):
        candidates = [
            ("equal", a, b),
            ("<", a, b),
            ("equal", ("+", a, b), ("rat", Fraction(0))),
            ("equal", ("+", a, b), ("bool", False)),
            ("equal", ("*", a, b), ("rat", Fraction(0))),
            ("equal", ("*", a, b), ("bool", False)),
            ("equal", ("-", a), ("rat", Fraction(0))),
            ("equal", ("-", a), ("rat", Fraction(-1))),
            ("equal", ("/", a), ("rat", Fraction(1))),
        ]
        for expr in candidates:
            if eval_acl2(expr) != ("bool", False):
                continue
            try:
                if z3_proves(eval_smt_py(smt, expr)):
                    key = (expr[0], expr[1][0], expr[2][0] if len(expr) > 2 else None)
                    unsound.setdefault(key, expr)
            except Exception as exc:
                errors.setdefault((expr[0], type(exc).__name__), (expr, str(exc)[:60]))

    # Randomized AST differential fuzzing (5000 terms)
    for _ in range(5000):
        expr = gen_expr(rng, 3)
        if eval_acl2(expr) != ("bool", False):
            continue
        try:
            if z3_proves(eval_smt_py(smt, expr)):
                key = ("rand", expr[0], expr[1][0])
                unsound.setdefault(key, expr)
        except Exception as exc:
            errors.setdefault(("rand", expr[0], type(exc).__name__), (expr, str(exc)[:60]))

    print(f"Active *SMT-functions* unsoundness classes (ACL2=NIL, Z3=proved): {len(unsound)}")
    for k, ex in sorted(unsound.items(), key=lambda kv: str(kv[0])):
        print(f"  [{k}] {ex}")
    print(f"Active *SMT-functions* runtime exceptions: {len(errors)}")
    for k, (ex, msg) in sorted(errors.items(), key=lambda kv: str(kv[0])):
        print(f"  [ERR {k}] {msg} :: {ex}")


if __name__ == "__main__":
    main()
