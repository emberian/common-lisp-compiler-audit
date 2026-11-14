#!/usr/bin/env python3
"""
Counterexample-Guided Prover Falsification Fuzzer (YinYang for ACL2 Prover Kernel)
===================================================================================
Uses Witness-First Polarity Alignment inside ACL2:
For every candidate tuple of expressions (e1..ek, target) and concrete witness (vx, vy, vz):
  - Evaluates each expression on (vx, vy, vz) via ACL2's own `trans-eval`.
  - Polarity-aligns each hypothesis hi = ei (if true on w) or (not ei) (if false on w),
    guaranteeing HYPS(vx, vy, vz) == T (never vacuous!).
  - Polarity-aligns CONCL = target (if false on w) or (not target) (if true on w),
    guaranteeing CONCL(vx, vy, vz) == NIL!
  - Thus EVERY SINGLE CANDIDATE (implies HYPS CONCL) is 100% guaranteed to evaluate
    to NIL at (vx, vy, vz), with non-vacuous, rich, mutually consistent hypotheses!
  - Bombards ACL2's prover kernel (:tau-system, bounders, signature rules, :linear,
    non-linear arithmetic, :bdd, :forward-chaining with force/case-split, :type-prescription,
    defequiv/defcong/defrefinement, defun-sk, and proof-builder :instructions).
  - Any Q.E.D. immediately instantiates at (vx, vy, vz) in the same encapsulate to prove
    `(defthm nil-proved-K nil :rule-classes nil)`!
"""

import argparse
import os
import random
import subprocess
import sys
import time
from pathlib import Path

TIMEOUT_BIN = "/opt/homebrew/bin/timeout"
SBCL_ACL2 = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2 = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"
OUT_DIR = Path("/Users/ember/dev/compiler-audit/hunts/prover-falsify")

WITNESS_ATOMS = [
    "nil", "t", "'a", "'b",
    "0", "1", "-1", "2", "-2", "3", "-3", "4", "-4", "7", "-8", "15", "16",
    "1/2", "-1/2", "3/2", "-3/2", "1/3", "-2/3", "5/4",
    "#c(0 1)", "#c(0 -1)", "#c(1 1)", "#c(-1 2)", "#c(1/2 -1/2)",
    "#\\a", "\"s\"", "'(nil)", "'(0 . 1)", "'(1 2)", "'(t . nil)",
]


def gen_arith_expr(rng: random.Random, vars_pool, depth: int = 2) -> str:
    if depth <= 0 or rng.random() < 0.35:
        if rng.random() < 0.72:
            return rng.choice(vars_pool)
        return rng.choice(["0", "1", "-1", "2", "-2", "3", "-4", "1/2", "-1/2", "3/2", "#c(0 1)"])
    op = rng.choice([
        "+", "-", "*", "unary--", "unary-/",
        "floor", "mod", "truncate", "rem",
        "ash", "logand", "logior", "logxor", "lognot",
        "expt", "abs", "realpart", "imagpart", "ifix", "nfix", "rfix", "fix",
    ])
    if op in ("unary--", "unary-/", "lognot", "abs", "realpart", "imagpart", "ifix", "nfix", "rfix", "fix"):
        a = gen_arith_expr(rng, vars_pool, depth - 1)
        if op == "unary--":
            return f"(- {a})"
        if op == "unary-/":
            return f"(/ {a})"
        return f"({op} {a})"
    if op == "expt":
        base = gen_arith_expr(rng, vars_pool, depth - 1)
        exp = rng.choice(["-2", "-1", "0", "1", "2", "3", f"(* -1 {rng.choice(vars_pool)})", rng.choice(vars_pool)])
        return f"(expt {base} {exp})"
    if op in ("floor", "mod", "truncate", "rem"):
        a = gen_arith_expr(rng, vars_pool, depth - 1)
        b = rng.choice(["1", "2", "-2", "3", "-3", "4", "1/2", "-1/2", rng.choice(vars_pool)])
        return f"({op} {a} {b})"
    if op == "ash":
        a = rng.choice(vars_pool) if rng.random() < 0.5 else gen_arith_expr(rng, vars_pool, depth - 1)
        b = rng.choice(["-3", "-2", "-1", "0", "1", "2", "3", "4"])
        return f"(ash {a} {b})"
    a = gen_arith_expr(rng, vars_pool, depth - 1)
    b = gen_arith_expr(rng, vars_pool, depth - 1)
    if op == "-":
        return f"(- {a} {b})"
    return f"({op} {a} {b})"


def gen_raw_prop(rng: random.Random, vars_pool, custom_preds, custom_fns, custom_eqvs, mode: str) -> str:
    v1 = rng.choice(vars_pool)
    v2 = rng.choice(vars_pool)
    kind = rng.randint(0, 10)
    if mode == "tau" and rng.random() < 0.45:
        kind = rng.choice([0, 1, 3, 4, 8])
    elif mode == "nonlinear" and rng.random() < 0.55:
        kind = rng.choice([1, 2, 8])
    elif mode == "bdd" and rng.random() < 0.45:
        kind = rng.choice([0, 3, 6, 9])

    if kind == 0:
        recog = rng.choice([
            "integerp", "natp", "posp", "rationalp", "acl2-numberp",
            "complex-rationalp", "booleanp", "symbolp", "consp", "atom",
            "characterp", "stringp", "zp", "zip", "null",
        ] + custom_preds)
        arg = v1 if rng.random() < 0.75 else gen_arith_expr(rng, vars_pool, 1)
        return f"({recog} {arg})"
    if kind in (1, 2):
        e1 = gen_arith_expr(rng, vars_pool, rng.choice([0, 1, 2]))
        e2 = gen_arith_expr(rng, vars_pool, rng.choice([0, 1]))
        rel = rng.choice(["<", "<=", "equal"])
        return f"({rel} {e1} {e2})"
    if kind == 3 and custom_fns:
        fn = rng.choice(custom_fns)
        e1 = v1 if rng.random() < 0.65 else gen_arith_expr(rng, vars_pool, 1)
        c = rng.choice(["nil", "t", "0", "1", "-1", "2", "'a", v2])
        rel = rng.choice(["equal", "<", "<=", "iff"] + custom_eqvs)
        return f"({rel} ({fn} {e1}) {c})"
    if kind == 4:
        c = rng.choice(["nil", "t", "0", "1", "-1", "2", "-2", "1/2", "#c(0 1)", "'a", "'b", "'(0 . 1)"])
        return f"(equal {v1} {c})"
    if kind == 5 and custom_eqvs:
        eqv = rng.choice(custom_eqvs)
        e1 = v1 if rng.random() < 0.5 else f"({rng.choice(custom_fns)} {v1})"
        e2 = rng.choice([v2, "0", "1", "-1", "nil", "t", "'a"])
        return f"({eqv} {e1} {e2})"
    if kind == 6:
        a = gen_raw_prop(rng, vars_pool, custom_preds, custom_fns, custom_eqvs, mode)
        b = gen_raw_prop(rng, vars_pool, custom_preds, custom_fns, custom_eqvs, mode)
        c = rng.choice(["t", "nil", v1, gen_raw_prop(rng, vars_pool, custom_preds, custom_fns, custom_eqvs, mode)])
        return f"(if {a} {b} {c})"
    if kind == 7:
        sub = gen_raw_prop(rng, vars_pool, custom_preds, custom_fns, custom_eqvs, mode)
        wrap = rng.choice(["hide", "let-swap"])
        if wrap == "let-swap":
            return f"(let ((x {v2}) (y {v1})) (declare (ignorable x y)) {sub})"
        return f"(hide {sub})"
    if kind == 8:
        # Interval / bounder stress atom
        op_expr = gen_arith_expr(rng, vars_pool, 2)
        lo = rng.choice(["-8", "-4", "-2", "-1", "0", "1", "2"])
        hi = rng.choice(["-1", "0", "1", "2", "4", "8", "16"])
        return f"(and (<= {lo} {op_expr}) (<= {op_expr} {hi}))"
    if kind == 9:
        # Boolean / iff / implies combination
        a = gen_raw_prop(rng, vars_pool, custom_preds, custom_fns, custom_eqvs, mode)
        b = gen_raw_prop(rng, vars_pool, custom_preds, custom_fns, custom_eqvs, mode)
        comb = rng.choice(["iff", "implies", "equal", "or"])
        return f"({comb} {a} {b})"
    e1 = gen_arith_expr(rng, vars_pool, 1)
    recog = rng.choice(["integerp", "rationalp", "natp", "booleanp"] + custom_preds)
    return f"({recog} {e1})"


def gen_background_theory(rng: random.Random, mode: str) -> tuple[str, list[str], list[str], list[str], list[str]]:
    lines = []
    preds = ["p1", "p2", "p3"]
    fns = ["f1", "f2", "g-cong"]
    eqvs = ["my-eqv"]
    disables = []

    p1_choices = [
        "(and (integerp x) (<= -2 x) (<= x 3) (not (equal x 0)))",
        "(or (null x) (and (integerp x) (<= 0 x) (<= x 4)))",
        "(or (booleanp x) (and (rationalp x) (< -1 x) (< x 2)))",
        "(and (acl2-numberp x) (not (equal x 0)) (not (equal x 1)))",
        "(or (equal x 'a) (equal x 0) (equal x -1))",
        "(and (not (equal x nil)) (not (equal x 0)) (not (equal x 2)))",
    ]
    p2_choices = [
        "(if (integerp x) (< x 2) (booleanp x))",
        "(or (equal x nil) (equal x 1) (and (integerp x) (< 2 x) (< x 6)))",
        "(and (rationalp x) (<= -3/2 x) (<= x 3/2))",
        "(not (or (equal x nil) (equal x 0) (equal x -1)))",
        "(or (consp x) (and (integerp x) (<= -4 x) (< x 0)))",
    ]
    p3_choices = [
        "(if (p1 x) (p2 x) (not (p2 x)))",
        "(if (p1 x) t (if (p2 x) nil (booleanp x)))",
        "(and (not (equal x 'b)) (or (p1 x) (booleanp x)))",
    ]
    f1_choices = [
        "(if (integerp x) (+ x 1) 0)",
        "(if (p1 x) (* 2 (ifix x)) -1)",
        "(if (booleanp x) (if x 1 0) (rfix x))",
        "(if (equal x nil) 'a (if (integerp x) (ash x -1) 0))",
        "(logand (ifix x) 7)",
        "(if (equal x 0) 'a x)",
    ]
    f2_choices = [
        "(if (p2 x) (f1 x) nil)",
        "(if (rationalp x) (/ (+ 2 (abs x))) 'b)",
        "(floor (ifix x) 2)",
        "(mod (ifix x) 4)",
        "(if (consp x) (car x) (f1 x))",
        "(if (equal x nil) -1 (ifix x))",
    ]

    lines.append(f"(defun p1 (x) {rng.choice(p1_choices)})")
    lines.append(f"(defun p2 (x) {rng.choice(p2_choices)})")
    lines.append(f"(defun p3 (x) {rng.choice(p3_choices)})")
    lines.append(f"(defun f1 (x) {rng.choice(f1_choices)})")
    lines.append(f"(defun f2 (x) {rng.choice(f2_choices)})")

    eqv_kind = rng.randint(0, 2)
    if eqv_kind == 0:
        lines.append("(defun my-eqv (x y) (equal (ifix x) (ifix y)))")
        lines.append("(defequiv my-eqv)")
        lines.append("(defun g-cong (x) (+ (ifix x) 1))")
        lines.append("(defcong my-eqv equal (g-cong x) 1)")
    elif eqv_kind == 1:
        lines.append("(defun my-eqv (x y) (iff x y))")
        lines.append("(defequiv my-eqv)")
        lines.append("(defrefinement my-eqv iff)")
        lines.append("(defun g-cong (x) (if x 1 0))")
        lines.append("(defcong my-eqv equal (g-cong x) 1)")
    else:
        lines.append("(defun my-eqv (x y) (equal (booleanp x) (booleanp y)))")
        lines.append("(defequiv my-eqv)")
        lines.append("(defun g-cong (x) (if (booleanp x) t 0))")
        lines.append("(defcong my-eqv equal (g-cong x) 1)")

    if mode == "nonlinear":
        lines.append("(set-non-linearp t)")

    # Attempt valid background rules including forced-hyp forward-chaining/rewrite/linear/tau rules!
    rule_attempts = [
        "(defthm r-tau-1 (implies (and (integerp x) (equal x 1)) (p1 x)) :rule-classes (:tau-system :forward-chaining))",
        "(defthm r-cr-1 (implies (p1 x) (or (acl2-numberp x) (booleanp x) (symbolp x))) :rule-classes :compound-recognizer)",
        "(defthm r-tp-1 (or (acl2-numberp (f1 x)) (symbolp (f1 x))) :rule-classes :type-prescription)",
        "(defthm r-sig-1 (implies (p1 x) (acl2-numberp (f1 x))) :rule-classes (:tau-system :type-prescription))",
        "(defthm r-lin-1 (implies (and (force (integerp x)) (<= 0 x)) (<= -1 (f1 x))) :rule-classes :linear)",
        "(defthm r-fc-force (implies (and (p2 x) (force (integerp x))) (or (acl2-numberp (f2 x)) (null (f2 x)))) :rule-classes :forward-chaining)",
        "(defthm r-rw-force (implies (and (force (booleanp x)) (not x)) (equal (p1 x) (p1 nil))))",
    ]
    rng.shuffle(rule_attempts)
    lines.extend(rule_attempts[:5])

    for sym in ["p1", "p2", "p3", "f1", "f2"]:
        r = rng.random()
        if r < 0.4:
            disables.append(sym)
        elif r < 0.8:
            disables.append(sym)
            disables.append(f"(:e {sym})")

    return "\n".join(lines), preds, fns, eqvs, disables


def gen_hints(rng: random.Random, mode: str, disables: list[str]) -> str:
    dis_str = f":in-theory (disable {' '.join(disables)})" if disables else ""
    if mode == "tau":
        extra = " :do-not-induct t" if rng.random() < 0.4 else ""
        return f'(("Goal" {dis_str}{extra}))'
    if mode == "nonlinear":
        return f'(("Goal" :nonlinearp t {dis_str} :do-not-induct t))'
    if mode == "bdd":
        lit_opt = rng.choice(["", " :literal 1", " :literal 2", " :literal :conc", " :prove nil"])
        vars_opt = rng.choice(["nil", "(x y z)", "(x)"])
        return f'(("Goal" :bdd (:vars {vars_opt}{lit_opt}) {dis_str}))'
    if mode == "instructions":
        instr = rng.choice([
            "(:bash)",
            "(:s :bash)",
            "(:promote :s :top :bash)",
            "(:casesplit (integerp x) :s :s)",
            "(:dive 1 :s :top :prove)",
            "(:reduce)",
            "(:s-prop :bash)",
            "(:promote :bdd :prove)",
        ])
        return f":instructions {instr}"
    return f'(("Goal" {dis_str}))'


def build_batch_lisp(rng: random.Random, mode: str, batch_id: int, num_candidates: int) -> str:
    out = [
        '(in-package "ACL2")',
        "(set-ignore-ok t)",
        "(set-guard-checking :none)",
        "(set-inhibit-output-lst '(prove proof-tree warning observation event summary))",
        "(set-prover-step-limit 3500)",
        """
(defun align-hyps-true (exprs vx vy vz acc state)
  (declare (xargs :stobjs state :mode :program))
  (if (endp exprs)
      (mv (reverse acc) state)
    (let* ((e (car exprs))
           (form `(let ((x ',vx) (y ',vy) (z ',vz))
                    (declare (ignorable x y z))
                    ,e)))
      (mv-let (erp val state)
        (trans-eval form 'ce-align state t)
        (if erp
            (mv :error state)
          (let ((aligned (if (cdr val) e `(not ,e))))
            (align-hyps-true (cdr exprs) vx vy vz (cons aligned acc) state)))))))

(defun align-concl-false (e vx vy vz state)
  (declare (xargs :stobjs state :mode :program))
  (let ((form `(let ((x ',vx) (y ',vy) (z ',vz))
                 (declare (ignorable x y z))
                 ,e)))
    (mv-let (erp val state)
      (trans-eval form 'ce-align state t)
      (if erp
          (mv :error state)
        (mv (if (cdr val) `(not ,e) e) state)))))
""",
    ]

    bg_code, preds, fns, eqvs, disables = gen_background_theory(rng, mode)
    out.append(bg_code)

    vars_pool = ["x", "y", "z"]
    for k in range(num_candidates):
        vx = rng.choice(WITNESS_ATOMS)
        vy = rng.choice(WITNESS_ATOMS)
        vz = rng.choice(WITNESS_ATOMS)

        nhyps = rng.randint(2, 5)
        raw_hyps = [gen_raw_prop(rng, vars_pool, preds, fns, eqvs, mode) for _ in range(nhyps)]
        raw_concl = gen_raw_prop(rng, vars_pool, preds, fns, eqvs, mode)

        cand_mode = mode if mode != "mixed" else rng.choice(["tau", "nonlinear", "bdd", "instructions", "default"])
        hints_spec = gen_hints(rng, cand_mode, disables)
        if hints_spec.startswith(":instructions"):
            thm_opts = f"{hints_spec} :rule-classes nil"
        else:
            thm_opts = f":hints {hints_spec} :rule-classes nil"

        raw_hyps_lisp = " ".join(raw_hyps)
        out.append(f"""
(make-event
 (let ((vx {vx}) (vy {vy}) (vz {vz}))
   (mv-let (hyps state)
     (align-hyps-true '({raw_hyps_lisp}) vx vy vz nil state)
     (if (eq hyps :error)
         (value '(value-triple :eval-err))
       (mv-let (concl state)
         (align-concl-false '{raw_concl} vx vy vz state)
         (if (eq concl :error)
             (value '(value-triple :eval-err))
           (value
            `(encapsulate ()
               (local (defthm falsify-cand-{k}
                        (implies (and ,@hyps) ,concl)
                        {thm_opts}))
               (defthm nil-proved-{k} nil
                 :rule-classes nil
                 :hints (("Goal" :use ((:instance falsify-cand-{k}
                                                  (x ',vx) (y ',vy) (z ',vz)))
                                 :in-theory (enable p1 p2 p3 f1 f2 g-cong my-eqv
                                                    (:e p1) (:e p2) (:e p3) (:e f1) (:e f2) (:e g-cong) (:e my-eqv)))))))))))))
""")

    check_syms = " ".join(f"nil-proved-{k}" for k in range(num_candidates))
    out.append(f"""
(defun check-nil-proved-list (syms wrld)
  (declare (xargs :mode :program))
  (if (endp syms)
      nil
    (if (not (eq (getpropc (car syms) 'theorem :none wrld) :none))
        (cons (car syms) (check-nil-proved-list (cdr syms) wrld))
      (check-nil-proved-list (cdr syms) wrld))))

(make-event
 (let ((hits (check-nil-proved-list '({check_syms}) (w state))))
   (if hits
       (prog2$ (cw "~%@@@ SOUNDNESS_BUG_FOUND: ~x0 @@@~%" hits)
               (value '(value-triple :bug-found)))
     (prog2$ (cw "~%@@@ BATCH_CLEAN @@@~%")
             (value '(value-triple :clean))))))
""")
    return "\n".join(out)


def run_batch(acl2_bin: str, batch_file: Path) -> tuple[int, str]:
    driver = f'(ld "{batch_file}" :ld-error-action :continue)\n(quit)\n'
    proc = subprocess.run(
        [TIMEOUT_BIN, "--kill-after=10s", "120s", acl2_bin],
        input=driver,
        text=True,
        capture_output=True,
    )
    return proc.returncode, proc.stdout + "\n" + proc.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batches", type=int, default=100)
    ap.add_argument("--candidates", type=int, default=60)
    ap.add_argument("--seed", type=int, default=20261114)
    ap.add_argument("--mode", type=str, default="mixed")
    ap.add_argument("--host", choices=["sbcl", "ccl"], default="sbcl")
    args = ap.parse_args()

    acl2_bin = SBCL_ACL2 if args.host == "sbcl" else CCL_ACL2
    runs_dir = OUT_DIR / "runs"
    hits_dir = OUT_DIR / "hits"
    runs_dir.mkdir(parents=True, exist_ok=True)
    hits_dir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(args.seed)
    log_path = OUT_DIR / f"campaign-{args.host}-{args.mode}-{args.seed}.log"

    total_tested = 0
    t0 = time.time()
    for b in range(args.batches):
        b_mode = args.mode if args.mode != "mixed" else rng.choice(["tau", "nonlinear", "bdd", "instructions"])
        batch_code = build_batch_lisp(rng, b_mode, b, args.candidates)
        batch_file = runs_dir / f"batch-{args.host}-{args.seed}-{b:04d}-{b_mode}.lisp"
        batch_file.write_text(batch_code)

        rc, output = run_batch(acl2_bin, batch_file)
        total_tested += args.candidates
        elapsed = time.time() - t0

        hard_err = (
            ("HARD ACL2 ERROR" in output or "ABORTING from raw Lisp" in output)
            and "[Call depth]" not in output
        )
        bug_hit = "SOUNDNESS_BUG_FOUND" in output

        msg = f"[batch {b+1}/{args.batches}] host={args.host} mode={b_mode} rc={rc} cands={total_tested} elapsed={elapsed:.1f}s bug={bug_hit} hard_err={hard_err}"
        print(msg, flush=True)
        with open(log_path, "a") as lf:
            lf.write(msg + "\n")

        if bug_hit or hard_err:
            tag = "SOUNDNESS" if bug_hit else "HARDERR"
            hit_file = hits_dir / f"{tag}-{args.host}-{args.seed}-{b:04d}-{b_mode}.lisp"
            hit_out = hits_dir / f"{tag}-{args.host}-{args.seed}-{b:04d}-{b_mode}.out"
            hit_file.write_text(batch_code)
            hit_out.write_text(output)
            print(f"!!! SAVED HIT TO {hit_file} !!!", flush=True)
        else:
            batch_file.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
