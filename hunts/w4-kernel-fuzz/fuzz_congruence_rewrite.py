#!/usr/bin/env python3
"""
Wave-4 Deep Kernel Fuzzer §5.1: Congruence, Patterned Equivalence, RQC & rewrite-lambda-object
==============================================================================================

Implements the witness-guided falsification fuzzer specified in ACL2-KERNEL-DEEP.md §5.1:
  - Finite-domain equivalence lattices (`eqv-m2`, `eqv-m3`, `eqv-m4`, `eqv-m6`,
    `eqv-car2`, `eqv-pair42`) connected via `defequiv` and `defrefinement` chains/diamonds.
  - Multi-argument operators with classic `defcong` AND shallow/deep patterned `:congruence`
    rules (nested `cons` paths, destructor projections, and duplicate pattern variables
    `(op-dup w w a)` testing `pequivs` applicability checks).
  - Equivalence-indexed `:rewrite` rules with `double-rewrite`, `syntaxp`, `bind-free`,
    `:loop-stopper`, and `:backchain-limit-lst`.
  - `:rewrite-quoted-constant` Forms [1], [2], and [3] (unconditional and conditional).
  - `apply$` / `defun$` + `rewrite-lambda-object` across all 3 `rewrite-lambda-modep`
    theory configurations (rewrite+normalize, `clean-up-dirty-lambda-object-body`, disabled).
  - Concrete Python witness pre-filter: EVERY attack goal sent to `saved_acl2` is first
    evaluated over 250+ concrete witness assignments in Python and confirmed FALSE on at
    least one concrete witness before ACL2 sees it. Any `Q.E.D.` is an immediate soundness
    bug; any `HARD ACL2 ERROR` or raw Lisp abort is an immediate kernel crash bug.
"""

from __future__ import annotations

import argparse
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

sys.dont_write_bytecode = True

TIMEOUT_BIN = "/opt/homebrew/bin/timeout"
DEFAULT_SBCL_ACL2 = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
DEFAULT_CCL_ACL2 = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"


# ---------------------------------------------------------------------------
# Concrete ACL2 value model & witness grid in Python
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Cons:
    car: Any
    cdr: Any


def acl2_intp(v: Any) -> bool:
    # In Python bool is a subclass of int; in ACL2 T/NIL are symbols, not integers!
    return isinstance(v, int) and not isinstance(v, bool)


def acl2_ifix(v: Any) -> int:
    return v if acl2_intp(v) else 0


def acl2_consp(v: Any) -> bool:
    return isinstance(v, Cons)


def acl2_car(v: Any) -> Any:
    return v.car if isinstance(v, Cons) else None


def acl2_cdr(v: Any) -> Any:
    return v.cdr if isinstance(v, Cons) else None


def acl2_mod(x: int, n: int) -> int:
    # Python's % with positive n matches ACL2's floor-based (mod x n) for integers.
    return acl2_ifix(x) % n


def proj_m2(v: Any) -> int:
    return acl2_mod(acl2_ifix(v), 2)


def proj_m3(v: Any) -> int:
    return acl2_mod(acl2_ifix(v), 3)


def proj_m4(v: Any) -> int:
    return acl2_mod(acl2_ifix(v), 4)


def proj_m6(v: Any) -> int:
    return acl2_mod(acl2_ifix(v), 6)


def proj_car2(v: Any) -> int:
    return proj_m2(acl2_car(v) if acl2_consp(v) else 0)


def proj_pair42(v: Any) -> Tuple[int, int]:
    if acl2_consp(v):
        return (proj_m4(acl2_car(v)), proj_m2(acl2_cdr(v)))
    return (0, 0)


EQUIV_PROJS: Dict[str, Callable[[Any], Any]] = {
    "equal": lambda v: v,
    "iff": lambda v: (v is not None and v is not False),
    "eqv-m2": proj_m2,
    "eqv-m3": proj_m3,
    "eqv-m4": proj_m4,
    "eqv-m6": proj_m6,
    "eqv-car2": proj_car2,
    "eqv-pair42": proj_pair42,
}


def acl2_equiv(eqv: str, a: Any, b: Any) -> bool:
    return EQUIV_PROJS[eqv](a) == EQUIV_PROJS[eqv](b)


SCALAR_WITNESSES: List[Any] = [
    -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7,
    None, True, "sym-a",
]

PAIR_WITNESSES: List[Any] = [
    Cons(0, 0),
    Cons(1, 0),
    Cons(2, 1),
    Cons(3, 2),
    Cons(4, 1),
    Cons(5, 3),
    Cons(-1, 2),
    Cons(Cons(0, 1), 2),
    Cons(Cons(1, 1), 2),
    Cons(Cons(2, 0), 3),
    Cons(Cons(3, 0), 1),
    None,
    0,
]


def build_witness_envs(rng: random.Random, count: int = 260) -> List[Dict[str, Any]]:
    envs: List[Dict[str, Any]] = []
    all_vals = SCALAR_WITNESSES + PAIR_WITNESSES
    # Deterministic core corner grid
    for x in [-2, -1, 0, 1, 2, 3, 4, 5, None, Cons(1, 0), Cons(2, 1)]:
        for y in [-1, 0, 1, 2, 3, 4, None, Cons(0, 1)]:
            envs.append({
                "x": x,
                "y": y,
                "z": (acl2_ifix(x) + 1) if acl2_intp(x) else 2,
                "w": y if acl2_intp(y) else Cons(3, 1),
                "p": Cons(Cons(x, y), 1),
            })
            if len(envs) >= count // 2:
                break
        if len(envs) >= count // 2:
            break
    while len(envs) < count:
        envs.append({
            "x": rng.choice(all_vals),
            "y": rng.choice(all_vals),
            "z": rng.choice(all_vals),
            "w": rng.choice(all_vals),
            "p": Cons(Cons(rng.choice(SCALAR_WITNESSES), rng.choice(SCALAR_WITNESSES)),
                      rng.choice(SCALAR_WITNESSES)),
        })
    return envs


def acl2_lit(v: Any) -> str:
    if v is None or v is False:
        return "nil"
    if v is True:
        return "t"
    if acl2_intp(v):
        return str(v)
    if isinstance(v, str):
        return f"'{v}"
    if isinstance(v, Cons):
        return f"(cons {acl2_lit(v.car)} {acl2_lit(v.cdr)})"
    raise TypeError(f"Unsupported literal: {v!r}")


# ---------------------------------------------------------------------------
# Expression AST paired with exact Python evaluator & ACL2 printer
# ---------------------------------------------------------------------------

@dataclass
class Expr:
    lisp: str
    eval_fn: Callable[[Dict[str, Any]], Any]


@dataclass
class TheorySpec:
    tid: int
    preamble: str
    falsified_goals: List[Tuple[str, str, Dict[str, Any]]]  # (goal_id, goal_lisp, witness_env)
    hints_variants: List[str]


SHARED_PREAMBLE = """
(in-package "ACL2")
(set-inhibit-warnings "theory" "free" "non-rec" "subsume" "double-rewrite" "rewrite-lambda")

(defun p-m2 (x) (if (equal (rem (ifix x) 2) 0) 0 (if (< (ifix x) 0) (+ (rem (ifix x) 2) 2) (rem (ifix x) 2))))
(defun p-m3 (x) (let ((r (rem (ifix x) 3))) (if (< r 0) (+ r 3) r)))
(defun p-m4 (x) (let ((r (rem (ifix x) 4))) (if (< r 0) (+ r 4) r)))
(defun p-m6 (x) (let ((r (rem (ifix x) 6))) (if (< r 0) (+ r 6) r)))

(defun eqv-m2 (x y) (equal (p-m2 x) (p-m2 y)))
(defun eqv-m3 (x y) (equal (p-m3 x) (p-m3 y)))
(defun eqv-m4 (x y) (equal (p-m4 x) (p-m4 y)))
(defun eqv-m6 (x y) (equal (p-m6 x) (p-m6 y)))

(defun p-car2 (x) (p-m2 (if (consp x) (car x) 0)))
(defun p-pair42 (x)
  (if (consp x)
      (cons (p-m4 (car x)) (p-m2 (cdr x)))
    (cons 0 0)))

(defun eqv-car2 (x y) (equal (p-car2 x) (p-car2 y)))
(defun eqv-pair42 (x y) (equal (p-pair42 x) (p-pair42 y)))

(defequiv eqv-m2)
(defequiv eqv-m3)
(defequiv eqv-m4)
(defequiv eqv-m6)
(defequiv eqv-car2)
(defequiv eqv-pair42)

(defrefinement eqv-m4 eqv-m2)
(defrefinement eqv-m6 eqv-m2)
(defrefinement eqv-m6 eqv-m3)
(defrefinement eqv-pair42 eqv-car2)

(defun bind-const-alist (k)
  (list (cons 'u k)))
"""


def generate_pure_theory(tid: int, rng: random.Random, envs: List[Dict[str, Any]]) -> TheorySpec:
    c1 = rng.randint(0, 5)
    c2 = rng.randint(1, 5)
    c3 = rng.choice([2, 4, 6])  # even offset -> preserves mod 2!
    c4 = rng.choice([0, 2, 4])
    k_bind = rng.choice([0, 2, 4])

    f_add = f"t{tid}-add"
    f_step = f"t{tid}-step"
    f_deep = f"t{tid}-deep"
    f_dup = f"t{tid}-dup"
    f_pair = f"t{tid}-pair"
    f_sel = f"t{tid}-sel"

    # Exact Python semantics matching the ACL2 definitions below:
    def py_add(a: Any, b: Any) -> int:
        return acl2_ifix(a) + acl2_ifix(b) + c1

    def py_step(a: Any) -> int:
        return (2 * acl2_ifix(a)) + c2

    def py_deep(p: Any) -> int:
        # Reads (caar p) mod 2 + (cdr p) mod 2
        caar_v = acl2_car(acl2_car(p)) if (acl2_consp(p) and acl2_consp(acl2_car(p))) else 0
        cdr_v = acl2_cdr(p) if acl2_consp(p) else 0
        return proj_m2(caar_v) + (2 * proj_m2(cdr_v)) + c4

    def py_dup(u: Any, v: Any, a: Any) -> int:
        # Crucially behaves DIFFERENTLY when u == v vs u != v!
        # When u == v: depends only on proj_m2(a).
        # When u != v: depends on exact ifix(a) mod 4!
        # Thus patterned congruence (implies (eqv-m2 a b) (equal (f_dup w w a) (f_dup w w b)))
        # IS SOUND when the first two args match (`w`, `w`), and WOULD BE UNSOUND if
        # `pequivs` failed to check duplicate pattern variable equality on `(f_dup x y a)`!
        if u == v:
            return proj_m2(a) + c3
        return proj_m4(a) + c1

    def py_pair(a: Any, b: Any) -> Cons:
        return Cons(acl2_ifix(a) + c3, acl2_ifix(b) + 2)

    def py_sel(p: Any) -> int:
        return proj_car2(p) + c3

    lines: List[str] = [
        f"(defun {f_add} (a b) (+ (ifix a) (+ (ifix b) {c1})))",
        f"(defun {f_step} (a) (+ (* 2 (ifix a)) {c2}))",
        f"(defun {f_deep} (p)"
        f"  (+ (p-m2 (if (and (consp p) (consp (car p))) (car (car p)) 0))"
        f"     (+ (* 2 (p-m2 (if (consp p) (cdr p) 0))) {c4})))",
        f"(defun {f_dup} (u v a)"
        f"  (if (equal u v) (+ (p-m2 a) {c3}) (+ (p-m4 a) {c1})))",
        f"(defun {f_pair} (a b) (cons (+ (ifix a) {c3}) (+ (ifix b) 2)))",
        f"(defun {f_sel} (p) (+ (p-car2 p) {c3}))",
        # Classic congruences (all mathematically true!)
        f"(defcong eqv-m2 eqv-m2 ({f_add} a b) 1)",
        f"(defcong eqv-m2 eqv-m2 ({f_add} a b) 2)",
        f"(defcong eqv-m4 eqv-m4 ({f_add} a b) 1)",
        f"(defcong eqv-m4 eqv-m4 ({f_add} a b) 2)",
        f"(defcong eqv-m2 eqv-m4 ({f_step} a) 1)",
        f"(defcong eqv-m4 eqv-pair42 ({f_pair} a b) 1)",
        f"(defcong eqv-m2 eqv-pair42 ({f_pair} a b) 2)",
        f"(defcong eqv-car2 equal ({f_sel} p) 1)",
        # Deep nested patterned congruence on (cons (cons a z) w)
        f"(defthm {f_deep}-pat-cong-1"
        f"  (implies (eqv-m2 a b)"
        f"           (equal ({f_deep} (cons (cons a z) w))"
        f"                  ({f_deep} (cons (cons b z) w))))"
        f"  :rule-classes :congruence)",
        f"(defthm {f_deep}-pat-cong-2"
        f"  (implies (eqv-m2 w1 w2)"
        f"           (equal ({f_deep} (cons q w1))"
        f"                  ({f_deep} (cons q w2))))"
        f"  :rule-classes :congruence)",
        # Duplicate-variable patterned congruence on (f_dup w w a)!
        f"(defthm {f_dup}-dupvar-pat-cong"
        f"  (implies (eqv-m2 a b)"
        f"           (equal ({f_dup} w w a)"
        f"                  ({f_dup} w w b)))"
        f"  :rule-classes :congruence)",
        # Equivalence rewrite rules with double-rewrite, syntaxp, and bind-free
        f"(defthm {f_add}-comm-m4"
        f"  (eqv-m4 ({f_add} a b) ({f_add} b a))"
        f"  :rule-classes ((:rewrite :loop-stopper ((a b)))))",
        f"(defthm {f_add}-bind-free-m2"
        f"  (implies (and (bind-free (bind-const-alist '{k_bind}) (u))"
        f"                (syntaxp (quotep b))"
        f"                (eqv-m2 (double-rewrite u) 0))"
        f"           (eqv-m2 ({f_add} a b) ({f_add} a (+ b u)))))",
        # :rewrite-quoted-constant Form [1], Form [2], and Form [3]
        f"(defthm {f_add}-rqc-form1"
        f"  (eqv-m2 ({f_add} 0 {c3}) {c1})"
        f"  :rule-classes :rewrite-quoted-constant)",
        f"(defthm {f_pair}-rqc-form3"
        f"  (eqv-pair42 '(4 . 2) '(0 . 0))"
        f"  :rule-classes :rewrite-quoted-constant)",
        f"(defthm {f_sel}-rqc-form2"
        f"  (implies (syntaxp (quotep p))"
        f"           (equal (eqv-car2 (cons 4 (cdr p)) p)"
        f"                  (equal (p-car2 p) 0)))"
        f"  :rule-classes :rewrite-quoted-constant)",
        # Disable definitions so congruence + RQC + patterned rules drive rewriting!
        f"(in-theory (disable {f_add} {f_step} {f_deep} {f_dup} {f_pair} {f_sel}"
        f"                    (:executable-counterpart {f_add})"
        f"                    (:executable-counterpart {f_deep})"
        f"                    (:executable-counterpart {f_dup})))",
    ]

    # Build rich candidate expressions paired with exact Python evaluators
    candidates: List[Tuple[str, Callable[[Dict[str, Any]], bool]]] = []

    # Attack 1: Duplicate-variable patterned congruence must NOT fire when x != y!
    candidates.append((
        f"(implies (eqv-m2 a b) (equal ({f_dup} x y a) ({f_dup} x y b)))",
        lambda e: (not acl2_equiv("eqv-m2", e["z"], e["w"]))
        or (py_dup(e["x"], e["y"], e["z"]) == py_dup(e["x"], e["y"], e["w"])),
    ))
    candidates.append((
        f"(equal ({f_dup} x y (+ x 2)) ({f_dup} x y x))",
        lambda e: py_dup(e["x"], e["y"], acl2_ifix(e["x"]) + 2) == py_dup(e["x"], e["y"], e["x"]),
    ))

    # Attack 2: Coarse eqv-m2 rewrite inside fine eqv-m4 or equal context (geneqv confusion)
    candidates.append((
        f"(eqv-m4 ({f_add} x 2) ({f_add} x 0))",
        lambda e: acl2_equiv("eqv-m4", py_add(e["x"], 2), py_add(e["x"], 0)),
    ))
    candidates.append((
        f"(eqv-m6 ({f_add} x 4) ({f_add} x 0))",
        lambda e: acl2_equiv("eqv-m6", py_add(e["x"], 4), py_add(e["x"], 0)),
    ))

    # Attack 3: Deep patterned congruence off-path mutation (cdar vs caar)
    candidates.append((
        f"(equal ({f_deep} (cons (cons x y) z)) ({f_deep} (cons (cons (+ x 1) y) z)))",
        lambda e: py_deep(Cons(Cons(e["x"], e["y"]), e["z"]))
        == py_deep(Cons(Cons(acl2_ifix(e["x"]) + 1, e["y"]), e["z"])),
    ))
    candidates.append((
        f"(eqv-m4 ({f_deep} (cons (cons x 0) 1)) ({f_deep} (cons (cons x 0) 0)))",
        lambda e: acl2_equiv(
            "eqv-m4",
            py_deep(Cons(Cons(e["x"], 0), 1)),
            py_deep(Cons(Cons(e["x"], 0), 0)),
        ),
    ))

    # Attack 4: RQC Form [1]/[2]/[3] under stronger outer equivalence than rule equiv
    candidates.append((
        f"(equal ({f_add} 0 {c3}) {c1})",
        lambda e: py_add(0, c3) == c1,
    ))
    candidates.append((
        f"(equal ({f_pair} 4 2) '(0 . 0))",
        lambda e: py_pair(4, 2) == Cons(0, 0),
    ))
    candidates.append((
        f"(eqv-pair42 '(2 . 0) '(0 . 0))",
        lambda e: acl2_equiv("eqv-pair42", Cons(2, 0), Cons(0, 0)),
    ))
    candidates.append((
        f"(equal ({f_sel} '(4 . 1)) ({f_sel} '(1 . 1)))",
        lambda e: py_sel(Cons(4, 1)) == py_sel(Cons(1, 1)),
    ))

    # Attack 5: Randomized composite congruence + step + pair projections
    for j in range(6):
        eqv = rng.choice(["equal", "eqv-m2", "eqv-m3", "eqv-m4", "eqv-m6"])
        k_off = rng.choice([1, 2, 3, 5])
        if j % 2 == 0:
            goal_str = f"({eqv} ({f_step} ({f_add} x {k_off})) ({f_step} ({f_add} x 0)))"
            pred = lambda e, eqv=eqv, k_off=k_off: acl2_equiv(
                eqv, py_step(py_add(e["x"], k_off)), py_step(py_add(e["x"], 0))
            )
        else:
            goal_str = (
                f"({eqv} ({f_add} ({f_sel} ({f_pair} x y)) ({f_dup} x z y))"
                f"       ({f_add} ({f_sel} '(0 . 0)) ({f_dup} x x y)))"
            )
            pred = lambda e, eqv=eqv: acl2_equiv(
                eqv,
                py_add(py_sel(py_pair(e["x"], e["y"])), py_dup(e["x"], e["z"], e["y"])),
                py_add(py_sel(Cons(0, 0)), py_dup(e["x"], e["x"], e["y"])),
            )
        candidates.append((goal_str, pred))

    # Pre-filter with concrete Python witness evaluator: ONLY keep goals with a concrete counterexample!
    falsified: List[Tuple[str, str, Dict[str, Any]]] = []
    for idx, (g_lisp, pred) in enumerate(candidates):
        cex: Optional[Dict[str, Any]] = None
        for env in envs:
            # Map free vars a->z, b->w for 4-var goals
            if not pred(env):
                cex = env
                break
        if cex is not None:
            falsified.append((f"T{tid}-G{idx}", g_lisp, cex))

    hints = [
        "",
        ':hints (("Goal" :do-not-induct t))',
    ]
    return TheorySpec(
        tid=tid,
        preamble="\n".join(lines),
        falsified_goals=falsified,
        hints_variants=hints,
    )


def build_pure_batch_script(theories: Sequence[TheorySpec]) -> Tuple[str, int]:
    chunks: List[str] = [SHARED_PREAMBLE]
    total_goals = 0
    for th in theories:
        t_lines = [
            f"(encapsulate ()",
            "  (local (progn",
            th.preamble,
        ]
        for gid, g_lisp, _cex in th.falsified_goals:
            total_goals += 1
            t_lines.append(
                f"    (make-event"
                f"      (mv-let (erp val state)"
                f"        (with-output :off :all (thm {g_lisp} :hints ((\"Goal\" :do-not-induct t))))"
                f"        (declare (ignore val))"
                f"        (if erp"
                f"            (value '(value-triple :expected-fail))"
                f"          (prog2$ (cw \"~%!!!W4-KF-SOUNDNESS-BUG [{gid}]: ~x0~%\" '{g_lisp})"
                f"                  (value '(value-triple :soundness-bug))))))"
            )
        t_lines.append("  )))")
        chunks.append("\n".join(t_lines))
    chunks.append('(cw "~%W4-KF-PURE-BATCH-COMPLETE~%")\n:q\n')
    return "\n\n".join(chunks), total_goals


def build_apply_lambda_batch_script(
    batch_id: int,
    num_theories: int,
    rng: random.Random,
    envs: List[Dict[str, Any]],
) -> Tuple[str, int]:
    """
    Tests rewrite-lambda-object (`rewrite.lisp:23450-23637`) across all 3 modes of
    `rewrite-lambda-modep`, warranted/unwarranted `defun$` functions, `mbe` guard holders
    inside quoted lambdas, and RQC + congruence interactions on `apply$`.
    Every candidate goal is concretely falsified in Python before emission!
    """
    chunks: List[str] = [
        '(in-package "ACL2")',
        '(include-book "projects/apply/top" :dir :system)',
        SHARED_PREAMBLE,
    ]
    total_goals = 0
    modes = [
        # Mode 0: both (:executable-counterpart rewrite-lambda-modep) and (:definition rewrite-lambda-modep) enabled
        "(in-theory (enable (:executable-counterpart rewrite-lambda-modep) (:definition rewrite-lambda-modep)))",
        # Mode 1: (:definition rewrite-lambda-modep) disabled -> clean-up-dirty-lambda-object-body path!
        "(in-theory (and (enable (:executable-counterpart rewrite-lambda-modep)) (disable (:definition rewrite-lambda-modep))))",
        # Mode 2: (:executable-counterpart rewrite-lambda-modep) disabled
        "(in-theory (disable (:executable-counterpart rewrite-lambda-modep)))",
    ]

    for k in range(num_theories):
        tid = batch_id * 1000 + k
        c1 = rng.randint(1, 5)
        c2 = rng.choice([2, 4])
        fn_w = f"wfn-{tid}"
        fn_u = f"ufn-{tid}"

        def py_w(u: Any) -> int:
            return (2 * acl2_ifix(u)) + c1

        def py_u(u: Any) -> int:
            return acl2_ifix(u) + c2

        t_lines = [
            "(encapsulate ()",
            "  (local (progn",
            f"    (defun$ {fn_w} (u) (declare (xargs :guard t)) (+ (* 2 (ifix u)) {c1}))",
            f"    (defun {fn_u} (u) (+ (ifix u) {c2}))",
            f"    (defcong eqv-m2 eqv-m4 ({fn_w} u) 1)",
            f"    (defthm {fn_w}-shift-m2 (eqv-m2 ({fn_w} (+ 1 (ifix u))) ({fn_w} u)))",
        ]

        # Candidate falsified goals involving quoted lambdas and apply$:
        # Note: rewrite-lambda-object rewrites quoted lambda bodies under `:geneqv nil` (EQUAL),
        # pushes warrants, and checks tameness/free-vars. We attack:
        # 1) eqv-m2 rule must NOT rewrite inside quoted lambda body unless equal!
        # 2) mbe(:logic ..., :exec ...) inside quoted lambda body (clean-up-dirty-lambda-object-body)
        # 3) unwarranted fn inside quoted lambda body
        # 4) quoted lambda with RQC / congruence context outside apply$
        lam_goals: List[Tuple[str, Callable[[Dict[str, Any]], bool]]] = [
            (
                f"(equal (apply$ '(lambda (u) ({fn_w} (+ 1 (ifix u)))) (list x))"
                f"       (apply$ '(lambda (u) ({fn_w} u)) (list x)))",
                lambda e, py_w=py_w: py_w(1 + acl2_ifix(e["x"])) == py_w(e["x"]),
            ),
            (
                f"(eqv-m4 (apply$ '(lambda (u) (mbe :logic ({fn_w} u) :exec ({fn_w} (+ u 2)))) (list x))"
                f"        ({fn_w} (+ (ifix x) 1)))",
                lambda e, py_w=py_w: acl2_equiv("eqv-m4", py_w(e["x"]), py_w(acl2_ifix(e["x"]) + 1)),
            ),
            (
                f"(equal (apply$ '(lambda (u) (prog2$ u ({fn_w} (ifix u)))) (list x))"
                f"       (+ ({fn_w} x) 2))",
                lambda e, py_w=py_w: py_w(acl2_ifix(e["x"])) == py_w(e["x"]) + 2,
            ),
            (
                # Without warrant assumption in hypothesis (when forcing disabled), or false equality even with warrant:
                f"(implies (warrant {fn_w})"
                f"         (eqv-m6 (apply$ '(lambda (u) ({fn_w} (+ (ifix u) 2))) (list x))"
                f"                 (apply$ '(lambda (u) ({fn_w} u)) (list x))))",
                lambda e, py_w=py_w: acl2_equiv(
                    "eqv-m6", py_w(acl2_ifix(e["x"]) + 2), py_w(e["x"])
                ),
            ),
            (
                # Unwarranted userfn inside quoted lambda: must not fabricate evaluation!
                f"(equal (apply$ '(lambda (u) ({fn_u} u)) (list x)) (+ (ifix x) {c2 + 1}))",
                lambda _e: False,
            ),
        ]

        for m_idx, mode_form in enumerate(modes):
            t_lines.append(f"    {mode_form}")
            for g_idx, (g_lisp, pred) in enumerate(lam_goals):
                if any(not pred(env) for env in envs):
                    total_goals += 1
                    gid = f"LAM-{tid}-M{m_idx}-G{g_idx}"
                    t_lines.append(
                        f"    (make-event"
                        f"      (mv-let (erp val state)"
                        f"        (with-output :off :all (thm {g_lisp} :hints ((\"Goal\" :do-not-induct t))))"
                        f"        (declare (ignore val))"
                        f"        (if erp"
                        f"            (value '(value-triple :expected-fail))"
                        f"          (prog2$ (cw \"~%!!!W4-KF-SOUNDNESS-BUG [{gid}]: ~x0~%\" '{g_lisp})"
                        f"                  (value '(value-triple :soundness-bug))))))"
                    )
        t_lines.append("  )))")
        chunks.append("\n".join(t_lines))

    chunks.append('(cw "~%W4-KF-APPLY-BATCH-COMPLETE~%")\n:q\n')
    return "\n\n".join(chunks), total_goals


CRASH_PATTERNS = [
    re.compile(r"^!!!W4-KF-SOUNDNESS-BUG", re.MULTILINE),
    re.compile(r"HARD ACL2 ERROR"),
    re.compile(r"ABORTING from raw Lisp"),
    re.compile(r"ACL2 Halted"),
    re.compile(r"debugger invoked on"),
    re.compile(r"Unhandled memory fault"),
    re.compile(r"^> Error:", re.MULTILINE),
]


def run_acl2_script(acl2_bin: str, script_text: str, timeout_sec: int = 60) -> Tuple[int, str]:
    cmd = [TIMEOUT_BIN, "--kill-after=5s", f"{timeout_sec}s", acl2_bin]
    proc = subprocess.run(
        cmd,
        input=script_text,
        text=True,
        capture_output=True,
    )
    combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
    return proc.returncode, combined


def check_anomalies(rc: int, out: str, expected_marker: str) -> List[str]:
    issues: List[str] = []
    if rc == 124 or rc == 137:
        issues.append(f"TIMEOUT (rc={rc})")
    elif rc != 0:
        issues.append(f"NONZERO_EXIT (rc={rc})")
    for pat in CRASH_PATTERNS:
        m = pat.search(out)
        if m:
            start = max(0, m.start() - 120)
            end = min(len(out), m.end() + 280)
            issues.append(f"MATCH[{pat.pattern}]: {out[start:end].strip()}")
    if expected_marker not in out:
        issues.append(f"MISSING_COMPLETION_MARKER[{expected_marker}]")
    return issues


def ddmin_forms(acl2_bin: str, forms: List[str], predicate: Callable[[str], bool]) -> List[str]:
    """Delta-debugging reducer over top-level S-expression blocks."""
    n = 2
    cur = list(forms)
    while len(cur) >= 2:
        chunk_len = max(1, len(cur) // n)
        reduced = False
        for i in range(0, len(cur), chunk_len):
            cand = cur[:i] + cur[i + chunk_len :]
            if cand and predicate("\n".join(cand) + "\n:q\n"):
                cur = cand
                n = max(n - 1, 2)
                reduced = True
                break
        if not reduced:
            if n >= len(cur):
                break
            n = min(len(cur), n * 2)
    return cur


def main() -> int:
    ap = argparse.ArgumentParser(description="Wave-4 §5.1 Witness-Guided Congruence/RQC/Lambda Fuzzer")
    ap.add_argument("--acl2", default=DEFAULT_SBCL_ACL2, help="Path to saved_acl2 binary")
    ap.add_argument("--seed", type=int, default=20261114, help="RNG seed")
    ap.add_argument("--pure-batches", type=int, default=6, help="Number of pure congruence/RQC batches")
    ap.add_argument("--theories-per-batch", type=int, default=20, help="Theories per pure batch")
    ap.add_argument("--apply-batches", type=int, default=2, help="Number of apply$/rewrite-lambda batches")
    ap.add_argument("--apply-theories-per-batch", type=int, default=10, help="Theories per apply$ batch")
    ap.add_argument("--timeout", type=int, default=60, help="Per-invocation timeout in seconds")
    ap.add_argument("--save-anomaly-dir", default="", help="Optional directory to save anomalous inputs")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    envs = build_witness_envs(rng, count=280)

    total_theories = 0
    total_falsified_goals = 0
    anomalies_found = 0

    tmpdir = tempfile.mkdtemp(prefix="w4-kf-cong-")
    try:
        print(f"[fuzz_congruence_rewrite] acl2={args.acl2} seed={args.seed}")
        for b in range(args.pure_batches):
            theories = [
                generate_pure_theory(b * args.theories_per_batch + i, rng, envs)
                for i in range(args.theories_per_batch)
            ]
            script, n_goals = build_pure_batch_script(theories)
            rc, out = run_acl2_script(args.acl2, script, timeout_sec=args.timeout)
            issues = check_anomalies(rc, out, "W4-KF-PURE-BATCH-COMPLETE")
            total_theories += len(theories)
            total_falsified_goals += n_goals
            print(
                f"  [pure batch {b + 1}/{args.pure_batches}] theories={len(theories)} "
                f"falsified_goals={n_goals} rc={rc} issues={len(issues)}"
            )
            if issues:
                anomalies_found += len(issues)
                for iss in issues:
                    print(f"    ! ANOMALY: {iss}")
                if args.save_anomaly_dir:
                    os.makedirs(args.save_anomaly_dir, exist_ok=True)
                    with open(os.path.join(args.save_anomaly_dir, f"pure_batch_{b}.lisp"), "w") as f:
                        f.write(script)

        for b in range(args.apply_batches):
            script, n_goals = build_apply_lambda_batch_script(
                b, args.apply_theories_per_batch, rng, envs
            )
            rc, out = run_acl2_script(args.acl2, script, timeout_sec=args.timeout)
            issues = check_anomalies(rc, out, "W4-KF-APPLY-BATCH-COMPLETE")
            total_theories += args.apply_theories_per_batch
            total_falsified_goals += n_goals
            print(
                f"  [apply-lambda batch {b + 1}/{args.apply_batches}] "
                f"theories={args.apply_theories_per_batch} "
                f"falsified_goals={n_goals} rc={rc} issues={len(issues)}"
            )
            if issues:
                anomalies_found += len(issues)
                for iss in issues:
                    print(f"    ! ANOMALY: {iss}")
                if args.save_anomaly_dir:
                    os.makedirs(args.save_anomaly_dir, exist_ok=True)
                    with open(os.path.join(args.save_anomaly_dir, f"apply_batch_{b}.lisp"), "w") as f:
                        f.write(script)

        print(
            f"[fuzz_congruence_rewrite] SUMMARY: theories={total_theories} "
            f"witness_falsified_goals={total_falsified_goals} anomalies={anomalies_found}"
        )
        return 1 if anomalies_found else 0
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
