#!/usr/bin/env python3
"""
Wave-4 Deep Kernel Fuzzer §5.3 & §5.4:
Skolemization (`defchoose`/`defun-sk`), `defevaluator`, `apply$`, Lemma-Instances
(`:functional-instance`, `:termination-theorem`, `:guard-theorem`), Step-Limits,
Custom/Override/Backtrack Hints, and `brr`
=================================================================================

Implements the mechanical fuzzers specified in ACL2-KERNEL-DEEP.md §5.3 & §5.4,
explicitly excluding Wave-3 KD-2 (`:program`-mode RHS function symbol in
`:functional-instance`).

Modes:
  - Default: Runs the full grammar (surfacing novel Wave-4 kernel crashes/bugs as
    well as probing ratusan falsified soundness targets).
  - `--mask-wave4-known`: Masks the already-isolated Wave-4 crash shapes
    (`:termination-theorem` let-capture ASSERT$, `:termination-theorem` non-clique
    FMT0 crash, and `defun-sk` macroexpander `er hard`) so large campaigns can hunt
    for *additional* bugs with zero false-positive noise.
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
from typing import Dict, List, Sequence, Tuple

sys.dont_write_bytecode = True

TIMEOUT_BIN = "/opt/homebrew/bin/timeout"
DEFAULT_SBCL_ACL2 = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
DEFAULT_CCL_ACL2 = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

CRASH_PATTERNS = [
    re.compile(r"^!!!W4-KF-SOUNDNESS-BUG", re.MULTILINE),
    re.compile(r"^!!!W4-KF-UNEXPECTED-FAIL", re.MULTILINE),
    re.compile(r"HARD ACL2 ERROR"),
    re.compile(r"Implementation error:"),
    re.compile(r"ABORTING from raw Lisp"),
    re.compile(r"ACL2 Halted"),
    re.compile(r"debugger invoked on"),
    re.compile(r"Unhandled memory fault"),
    re.compile(r"^> Error:", re.MULTILINE),
]


def wrap_must_fail_thm(tag: str, thm_form: str) -> str:
    """
    Executes `thm_form` (whose formula is concretely false!) inside `make-event`.
    Soft failure (`erp` non-nil) is expected; if `erp` is nil, flags a SOUNDNESS BUG!
    Any `HARD ACL2 ERROR` emitted during translation/proof is captured on stdout.
    """
    return (
        f"(make-event"
        f"  (mv-let (erp val state)"
        f"    (with-output :off (warning observation prove proof-tree event summary)"
        f"      {thm_form})"
        f"    (declare (ignore val))"
        f"    (if erp"
        f"        (value '(value-triple :expected-fail))"
        f"      (prog2$ (cw \"~%!!!W4-KF-SOUNDNESS-BUG [{tag}]: ~x0~%\" '{thm_form})"
        f"              (value '(value-triple :soundness-bug))))))"
    )


def wrap_any_event(tag: str, ev_form: str, must_succeed: bool = False) -> str:
    return (
        f"(make-event"
        f"  (mv-let (erp val state)"
        f"    (with-output :off (warning observation prove proof-tree event summary)"
        f"      {ev_form})"
        f"    (declare (ignore val))"
        f"    (if erp"
        f"        (prog2$ {(f'(cw \"~%!!!W4-KF-UNEXPECTED-FAIL [{tag}]~%\")' if must_succeed else 'nil')}"
        f"                (value '(value-triple :soft-err)))"
        f"      (value '(value-triple :ok)))))"
    )


def generate_sk_fi_theory(tid: int, rng: random.Random, mask_wave4: bool) -> Tuple[str, int]:
    """
    Generates a randomized §5.3 theory block testing:
      - `defchoose` (`:strengthen {t, nil}`, 1-var and 2-var MV witnesses)
      - `defun-sk` (`forall`/`exists`, `:constrain {nil, t, sym}`, `:rewrite`, `:strengthen`,
        `:dfs`, `:stobjs`, `:split-types`)
      - `defevaluator` meta-evaluation + falsified functional substitutions
      - `:functional-instance`, `:termination-theorem`, `:termination-theorem!`,
        `:guard-theorem` with pseudo-lambdas (free vars, `mbe`), `let`/:ruler-extenders,
        and `proved-functional-instances-alist` across `local`/`encapsulate` boundaries.
    Returns (acl2_block, num_checks).
    """
    checks = 0
    k1 = rng.randint(1, 7)
    k2 = rng.randint(2, 9)
    lines: List[str] = [
        "(encapsulate ()",
        "  (local (progn",
        # Constrained base theory: cpred holds on at least one integer > k1
        f"    (encapsulate (((cpred-{tid} *) => *)"
        f"                  ((cmap-{tid} *) => *))"
        f"      (local (defun cpred-{tid} (x) (and (integerp x) (> x {k1}))))"
        f"      (local (defun cmap-{tid} (x) (+ (ifix x) {k2})))"
        f"      (defthm cpred-{tid}-witness (cpred-{tid} {k1 + 1}))"
        f"      (defthm cmap-{tid}-gt (implies (natp x) (> (cmap-{tid} x) x))))",
        # 1-var and 2-var defchoose with :strengthen
        f"    (defchoose ch1-{tid} (w) (x)"
        f"      (and (cpred-{tid} w) (> (ifix w) (ifix x)))"
        f"      :strengthen {rng.choice(['t', 'nil'])})",
        f"    (defchoose ch2-{tid} (u v) (x)"
        f"      (and (integerp u) (integerp v) (equal (+ u v) (+ (ifix x) {k1})))"
        f"      :strengthen {rng.choice(['t', 'nil'])})",
        # defun-sk matrix: constrained & unconstrained, multi-var, :rewrite :direct
        f"    (defun-sk sk-ex-{tid} (x)"
        f"      (exists (u v) (and (integerp u) (integerp v) (equal (+ u v) (cmap-{tid} x))))"
        f"      :strengthen {rng.choice(['t', 'nil'])}"
        f"      :constrain {rng.choice(['nil', 't', f'sk-ex-{tid}-def'])})",
        f"    (defun-sk sk-all-{tid} (x)"
        f"      (forall y (implies (natp y) (>= (+ (ifix x) y) (ifix x))))"
        f"      :rewrite {rng.choice([':default', ':direct'])}"
        f"      :constrain {rng.choice(['nil', 't'])})",
        # Recursive function with let-binding & :ruler-extenders :all for :termination-theorem
        f"    (defun rec-let-{tid} (x)"
        f"      (declare (xargs :ruler-extenders :all :verify-guards nil))"
        f"      (if (consp x)"
        f"          (if (let ((v (car x)))"
        f"                (if v (rec-let-{tid} (cdr x)) t))"
        f"              (rec-let-{tid} (cdr x))"
        f"            0)"
        f"        0))",
        # Guard-verified function for :guard-theorem substitutions
        f"    (defun gv-fn-{tid} (x)"
        f"      (declare (xargs :guard (consp x)))"
        f"      (let ((v (car x)))"
        f"        (cons v (cmap-{tid} (cdr x)))))",
        # defevaluator
        f"    (defevaluator ev-{tid} ev-{tid}-lst ((cmap-{tid} x) (cons a b) (car x) (if a b c)))",
        # Candidate target functions (:logic only — never :program per KD-2 exclusion!)
        f"    (defun bad-cpred-{tid} (x) (declare (ignore x)) nil)",
        f"    (defun bad-cmap-{tid} (x) (- (ifix x) {k2}))",
        f"    (defun df-fn-{tid} (x) (declare (xargs :dfs (x))) (df+ x (to-df 1)))",
        f"    (defun mv-fn-{tid} (x) (mv x x))",
    ]

    # Soundness Attack 1: Falsified :functional-instance on constrained + skolem + defchoose
    false_fi_cases = [
        # Violates cpred-witness (bad-cpred is always nil) -> goal is FALSE at x=0!
        f"(thm (equal (cmap-{tid} 0) -999)"
        f"  :hints ((\"Goal\" :use (:functional-instance cmap-{tid}-gt"
        f"                          (cpred-{tid} bad-cpred-{tid})"
        f"                          (cmap-{tid} bad-cmap-{tid})))))",
        # Violates cmap-gt with pseudo-lambda containing free variable `v` -> FALSE goal!
        f"(thm (< (+ (ifix x) {k2}) (ifix x))"
        f"  :hints ((\"Goal\" :use (:functional-instance cmap-{tid}-gt"
        f"                          (cmap-{tid} (lambda (z) (- (ifix z) v)))))))",
        # Attempt to capture `u` or `v` in 2-var Skolem / defchoose via pseudo-lambda free var!
        f"(thm nil"
        f"  :hints ((\"Goal\" :use (:functional-instance ch2-{tid}"
        f"                          (ch2-{tid} (lambda (z) (mv u v)))))))",
        # Attempt to instantiate single-value fn with mv-returning or :df logic fn on false goal
        f"(thm nil"
        f"  :hints ((\"Goal\" :use (:functional-instance cmap-{tid}-gt"
        f"                          (cmap-{tid} mv-fn-{tid})))))",
        f"(thm nil"
        f"  :hints ((\"Goal\" :use (:functional-instance cmap-{tid}-gt"
        f"                          (cmap-{tid} df-fn-{tid})))))",
        # Attempt to corrupt defevaluator constraint via functional substitution
        f"(thm (equal (ev-{tid} '(cons '1 '2) nil) '(9 . 9))"
        f"  :hints ((\"Goal\" :use (:functional-instance ev-{tid}-constraint-0"
        f"                          (ev-{tid} (lambda (tm al) (declare (ignore tm al)) '(9 . 9)))))))",
        # Attempt to smuggle proved-functional-instances-alist across inner local scope!
        f"(thm (equal (bad-cmap-{tid} 5) 999)"
        f"  :hints ((\"Goal\" :by (:functional-instance cmap-{tid}-gt"
        f"                         (cmap-{tid} bad-cmap-{tid})))))",
    ]
    for idx, tf in enumerate(false_fi_cases):
        checks += 1
        lines.append("    " + wrap_must_fail_thm(f"FI-{tid}-{idx}", tf))

    # Attack 2: `:guard-theorem` and `:termination-theorem` with substitutions
    gt_cases = [
        # :guard-theorem with free-var pseudo-lambda capturing let-bound `v`
        f"(thm nil"
        f"  :hints ((\"Goal\" :use ((:guard-theorem gv-fn-{tid}"
        f"                           ((cmap-{tid} (lambda (z) (cons v z)))))))))",
        # Valid :termination-theorem self-substitution on a FALSE goal (must NOT prove nil!)
        f"(thm nil"
        f"  :hints ((\"Goal\" :use ((:termination-theorem rec-let-{tid}"
        f"                           ((rec-let-{tid} (lambda (z) (ifix z)))))))))",
    ]
    if not mask_wave4:
        # Unmasked: includes the two Wave-4 crash shapes in translate-lmi (:termination-theorem)!
        gt_cases.extend([
            # Shape W4-KF-1: pseudo-lambda with free var `v` captured by let-bound `v` in rec-let!
            f"(thm nil"
            f"  :hints ((\"Goal\" :use ((:termination-theorem rec-let-{tid}"
            f"                           ((rec-let-{tid} (lambda (z) (if z v nil)))))))))",
            # Shape W4-KF-2: non-clique function symbol in :termination-theorem substitution!
            f"(thm nil"
            f"  :hints ((\"Goal\" :use ((:termination-theorem rec-let-{tid}"
            f"                           ((bad-cmap-{tid} bad-cpred-{tid})))))))",
        ])

    for idx, tf in enumerate(gt_cases):
        checks += 1
        lines.append("    " + wrap_must_fail_thm(f"LMI-{tid}-{idx}", tf))

    # Attack 3: `defun-sk` option/declaration combinations
    sk_edge_events = [
        f"(defun-sk sk-df-{tid} (x) (declare (xargs :dfs (x)))"
        f"  (forall y (implies (dfp y) (equal (df+ x (to-df 0)) x)))"
        f"  :constrain {rng.choice(['nil', 't'])})",
        f"(defun-sk sk-sp-{tid} (x) (declare (type integer x) (xargs :split-types t))"
        f"  (exists y (equal y (+ x 1)))"
        f"  :constrain {rng.choice(['nil', 't'])})",
    ]
    if not mask_wave4 and tid == 0:
        # Unmasked: probes malformed keyword / :constrain in defun-sk macroexpander
        # AND multi-declaration :stobjs splice bug under :constrain t!
        lines.append("    (defstobj st-a-0 fld-a-0)")
        lines.append("    (defstobj st-b-0 fld-b-0)")
        checks += 1
        lines.append(
            "    "
            + wrap_any_event(
                "SK-MULTIST-0",
                "(defun-sk sk-mst-0 (st-a-0 st-b-0)"
                "  (declare (xargs :stobjs st-a-0) (xargs :stobjs st-b-0))"
                "  (forall y (equal y y))"
                "  :constrain t)",
                must_succeed=True,
            )
        )
        sk_edge_events.extend([
            f"(defun-sk sk-badc-{tid} (x) (forall y (equal x y)) :constrain 123)",
            f"(defun-sk sk-badkw-{tid} (x) (forall y (equal x y)) :unknown-kw t)",
        ])
    for idx, ev in enumerate(sk_edge_events):
        checks += 1
        lines.append("    " + wrap_any_event(f"SK-{tid}-{idx}", ev))

    lines.append("  )))")
    return "\n".join(lines), checks


def generate_hints_steplimit_brr_theory(
    tid: int, rng: random.Random, mask_wave4: bool = False
) -> Tuple[str, int]:
    """
    Generates a randomized §5.4 block testing:
      - Nested `with-prover-step-limit` (0, 1, 3, 10, 40, 250) around `thm`, `defun`,
        `verify-guards`, and `encapsulate`
      - `add-custom-keyword-hint` + `table custom-keywords-table` + `:or` hints
      - `set-override-hints` + `:backtrack` hints (including `:computed-hint-replacement`,
        3/4-arg symbol hints, `:reorder` hints, `:rw-cache-state`)
      - `brr` (`:brr t` / `cw-gstack` / `wormhole-eval` / `:brr nil`) on false goals!
    Every theorem goal in the block is concretely FALSE, so any `Q.E.D.` is a soundness bug!
    """
    checks = 0
    step_lim = rng.choice([0, 1, 2, 5, 12, 35, 120])
    ckey = f":w4ck-{tid}"
    lines: List[str] = [
        "(encapsulate ()",
        "  (local (progn",
        f"    (defun hpred-{tid} (x) (and (integerp x) (> x 0)))",
        f"    (defun hstep-{tid} (x) (if (hpred-{tid} x) 1 2))",
        f"    (in-theory (disable hpred-{tid}))",
        # Custom keyword hint expanding into :in-theory / :no-op / :or
        f"    (add-custom-keyword-hint {ckey}"
        f"      (value (splice-keyword-alist {ckey} '(:no-op t) keyword-alist)))",
        # 3-arg and 4-arg symbol computed/backtrack hints
        f"    (defun symh3-{tid} (id clause world)"
        f"      (declare (ignore id clause world))"
        f"      '(:no-op t))",
        f"    (defun symbt4-{tid} (id clause world sus)"
        f"      (declare (ignore id clause world sus))"
        f"      nil)",
    ]

    hint_attack_thms = [
        # Tight step limit around false conjecture with :or + custom keyword hint
        f"(with-prover-step-limit {step_lim}"
        f"  (thm (equal (hstep-{tid} x) 3)"
        f"    :hints ((\"Goal\" {ckey} t"
        f"             :or ((:in-theory (enable hpred-{tid}))"
        f"                  (:do-not-induct t :rw-cache-state :disabled))))))",
        # Nested step limits (outer loose, inner tight & vice-versa)
        f"(with-prover-step-limit {step_lim + 50}"
        f"  (with-prover-step-limit {step_lim}"
        f"    (thm (equal (cons x y) nil) :hints (symh3-{tid}))))",
        # :backtrack hint with 4-arg symbol and :computed-hint-replacement
        f"(thm (equal (hstep-{tid} x) 99)"
        f"  :hints ((\"Goal\" :backtrack symbt4-{tid})))",
        f"(thm (equal (hstep-{tid} x) 88)"
        f"  :hints ((\"Goal\" :backtrack"
        f"           (if (equal processor 'simplify-clause)"
        f"               '(:computed-hint-replacement nil :do-not-induct t)"
        f"             nil))))",
        # :backtrack hint with `:computed-hint-replacement t` referencing `processor` & `clause-list`!
        f"(thm (equal (hstep-{tid} x) 77)"
        f"  :hints ((\"Goal\" :backtrack"
        f"           (if (and (equal processor 'simplify-clause) (consp clause-list))"
        f"               '(:computed-hint-replacement t :no-op t)"
        f"             nil))))",
        # :reorder hint on subgoal split of a false theorem
        f"(thm (equal (hstep-{tid} x) (if (hpred-{tid} x) 1 999))"
        f"  :hints ((\"Goal\" :reorder (2 1))))",
    ]

    for idx, tf in enumerate(hint_attack_thms):
        checks += 1
        lines.append("    " + wrap_must_fail_thm(f"HNT-{tid}-{idx}", tf))

    # Override-hints + custom keyword + step-limit
    lines.append(
        f"    (set-override-hints '((if stable-under-simplificationp"
        f"                              (append '(:do-not-induct t) keyword-alist)"
        f"                            keyword-alist)))"
    )
    checks += 1
    lines.append(
        "    "
        + wrap_must_fail_thm(
            f"OVR-{tid}",
            f"(with-prover-step-limit {step_lim + 10}"
            f"  (thm (equal (+ (ifix x) 1) (ifix x)) :hints ((\"Goal\" {ckey} t))))",
        )
    )
    lines.append("    (set-override-hints nil)")

    # Direct `table custom-keywords-table` raw entry (allowed by table guard!)
    ckey_raw = f":w4raw-{tid}"
    lines.append(
        f"    (table custom-keywords-table {ckey_raw}"
        f"           '((splice-keyword-alist {ckey_raw} '(:no-op t) keyword-alist) (value t)))"
    )
    checks += 1
    lines.append(
        "    "
        + wrap_must_fail_thm(
            f"RAWCK-{tid}",
            f"(thm (equal (hstep-{tid} 0) 999) :hints ((\"Goal\" {ckey_raw} 42)))",
        )
    )

    # `brr` + `wormhole-eval` boundary check inside isolated state
    checks += 1
    lines.append("    (value-triple (let ((erp-wh (wormhole-eval 'brr-wormhole '(lambda (whs) whs) nil))) (declare (ignore erp-wh)) :wh-ok))")
    lines.append("    " + wrap_any_event(f"BRR-ON-{tid}", "(brr t)"))
    lines.append(
        "    "
        + wrap_must_fail_thm(
            f"BRR-THM-{tid}",
            f"(with-prover-step-limit {step_lim + 25} (thm (equal (hstep-{tid} x) -1)))",
        )
    )
    lines.append("    " + wrap_any_event(f"BRR-OFF-{tid}", "(brr nil)"))

    if not mask_wave4 and tid == 0:
        # Unmasked: probes :backtrack :OMITTED sentinel leak via 4-arg symbol hint
        # and via :computed-hint-replacement t promotion into top-of-waterfall hints!
        lines.append("    (set-override-hints nil)")
        lines.append(
            "    (defun bt4-bool-0 (id clause world stable-under-simplificationp)"
            "      (declare (xargs :guard (booleanp stable-under-simplificationp))"
            "               (ignore id clause world))"
            "      (if stable-under-simplificationp nil '(:in-theory (enable hpred-0))))"
        )
        lines.append(
            "    (defun bt-cllen-0 (cl)"
            "      (declare (xargs :guard (true-listp cl)))"
            "      (len cl))"
        )
        checks += 2
        lines.append(
            "    "
            + wrap_any_event(
                "BT4-OMITTED-0",
                "(thm (implies (hpred-0 x) (> x 0)) :hints ((\"Goal\" :backtrack bt4-bool-0)))",
                must_succeed=True,
            )
        )
        lines.append(
            "    "
            + wrap_any_event(
                "BT-CHR-OMITTED-0",
                "(thm (and (implies (hpred-0 x) (> x 0)) (implies (equal y 1) (equal (+ y 0) 2)))"
                "  :hints ((\"Goal\" :backtrack"
                "           (let ((n (with-guard-checking :all (bt-cllen-0 clause-list))))"
                "             (if (zp n) nil '(:computed-hint-replacement t :in-theory (enable hpred-0)))))))",
                must_succeed=False,
            )
        )
        lines.append(
            "    "
            + wrap_must_fail_thm(
                "BT-CHR-OMITTED-LEAK-0",
                "(thm (and (implies (hpred-0 x) (equal x 999)) (implies (hpred-0 y) (equal y 888)))"
                "  :hints ((\"Goal\" :backtrack"
                "           (if (or (eq clause-list :omitted) (eq processor :omitted))"
                "               (prog2$ (cw \"~%!!!W4-KF-UNEXPECTED-FAIL [BT-OMITTED-LEAK]~%\") nil)"
                "             '(:computed-hint-replacement t :in-theory (enable hpred-0))))))",
            )
        )

    lines.append("  )))")
    return "\n".join(lines), checks


def generate_apply_fn_instance_batch(batch_id: int, count: int, rng: random.Random) -> Tuple[str, int]:
    """
    Dedicated `apply$` / `defun$` × `:functional-instance` / `defun-sk` / `defwarrant` batch!
    """
    chunks = [
        '(in-package "ACL2")',
        '(include-book "projects/apply/top" :dir :system)',
        '(set-inhibit-warnings "theory" "free" "non-rec" "subsume")',
    ]
    total_checks = 0
    for i in range(count):
        tid = batch_id * 1000 + i
        k = rng.randint(1, 10)
        lines = [
            "(encapsulate ()",
            "  (local (progn",
            f"    (defun$ wadd-{tid} (x) (declare (xargs :guard t)) (+ (ifix x) {k}))",
            f"    (defun$ wbad-{tid} (x) (declare (xargs :guard t)) (- (ifix x) {k}))",
            f"    (defun uwfn-{tid} (x) (+ (ifix x) {k}))",
            f"    (defun use-apply-{tid} (fn x) (apply$ fn (list x)))",
            f"    (defthm use-apply-{tid}-wadd"
            f"      (implies (warrant wadd-{tid})"
            f"               (equal (use-apply-{tid} 'wadd-{tid} x) (+ (ifix x) {k}))))",
        ]
        # Falsified goals attacking warrant / badge / apply$ under functional substitution:
        attacks = [
            # Attempt to functionally substitute wadd -> uwfn (unwarranted) or wbad to prove false apply$ equality
            f"(thm (equal (apply$ 'uwfn-{tid} (list 0)) {k})"
            f"  :hints ((\"Goal\" :use (:functional-instance use-apply-{tid}-wadd"
            f"                          (wadd-{tid} uwfn-{tid})))))",
            f"(thm (implies (warrant wbad-{tid})"
            f"              (equal (use-apply-{tid} 'wadd-{tid} 0) {-k}))"
            f"  :hints ((\"Goal\" :use (:functional-instance use-apply-{tid}-wadd"
            f"                          (wadd-{tid} wbad-{tid})))))",
            # defun-sk + defwarrant interaction
            f"(thm (implies (warrant wadd-{tid})"
            f"              (equal (apply$ '(lambda (z) (wadd-{tid} z)) (list 0)) 0)))",
        ]
        for idx, atk in enumerate(attacks):
            total_checks += 1
            lines.append("    " + wrap_must_fail_thm(f"APFI-{tid}-{idx}", atk))
        lines.append("  )))")
        chunks.append("\n".join(lines))

    marker = f"W4-KF-APFI-BATCH-{batch_id}-COMPLETE"
    chunks.append(f'(cw "~%{marker}~%")\n:q\n')
    return "\n\n".join(chunks), total_checks


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


def check_anomalies(rc: int, out: str, marker: str) -> List[str]:
    issues: List[str] = []
    if rc in (124, 137):
        issues.append(f"TIMEOUT (rc={rc})")
    elif rc != 0:
        issues.append(f"NONZERO_EXIT (rc={rc})")
    for pat in CRASH_PATTERNS:
        for m in pat.finditer(out):
            s = max(0, m.start() - 80)
            e = min(len(out), m.end() + 260)
            issues.append(f"MATCH[{pat.pattern}]: {out[s:e].strip()}")
    if marker not in out:
        issues.append(f"MISSING_MARKER[{marker}]")
    return issues


def main() -> int:
    ap = argparse.ArgumentParser(description="Wave-4 §5.3 & §5.4 Skolem/Functional-Instance/Hints/StepLimit Fuzzer")
    ap.add_argument("--acl2", default=DEFAULT_SBCL_ACL2, help="Path to saved_acl2 binary")
    ap.add_argument("--seed", type=int, default=20261114, help="RNG seed")
    ap.add_argument("--sk-batches", type=int, default=6, help="Number of §5.3 Skolem/FI batches")
    ap.add_argument("--hint-batches", type=int, default=6, help="Number of §5.4 Hints/StepLimit/BRR batches")
    ap.add_argument("--apply-batches", type=int, default=2, help="Number of apply$ × FI batches")
    ap.add_argument("--theories-per-batch", type=int, default=15, help="Theories per batch")
    ap.add_argument("--mask-wave4-known", action="store_true", help="Mask already-isolated Wave-4 crash shapes")
    ap.add_argument("--timeout", type=int, default=60, help="Per-batch timeout in seconds")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    total_theories = 0
    total_checks = 0
    anomalies = 0

    tmpdir = tempfile.mkdtemp(prefix="w4-kf-skfi-")
    try:
        print(
            f"[fuzz_fn_instance_sk] acl2={args.acl2} seed={args.seed} "
            f"mask_wave4_known={args.mask_wave4_known}"
        )

        for b in range(args.sk_batches):
            blocks = ['(in-package "ACL2")', '(set-inhibit-warnings "theory" "free" "non-rec" "subsume")']
            b_checks = 0
            for i in range(args.theories_per_batch):
                tid = b * args.theories_per_batch + i
                blk, n_chk = generate_sk_fi_theory(tid, rng, args.mask_wave4_known)
                blocks.append(blk)
                b_checks += n_chk
                total_theories += 1
            marker = f"W4-KF-SK-BATCH-{b}-COMPLETE"
            blocks.append(f'(cw "~%{marker}~%")\n:q\n')
            rc, out = run_acl2_script(args.acl2, "\n\n".join(blocks), timeout_sec=args.timeout)
            issues = check_anomalies(rc, out, marker)
            total_checks += b_checks
            print(
                f"  [sk-fi batch {b + 1}/{args.sk_batches}] theories={args.theories_per_batch} "
                f"checks={b_checks} rc={rc} issues={len(issues)}"
            )
            for iss in issues[:6]:
                print(f"    ! ANOMALY: {iss}")
            anomalies += len(issues)

        for b in range(args.hint_batches):
            blocks = ['(in-package "ACL2")', '(set-inhibit-warnings "theory" "free" "non-rec" "subsume")']
            b_checks = 0
            for i in range(args.theories_per_batch):
                tid = b * args.theories_per_batch + i
                blk, n_chk = generate_hints_steplimit_brr_theory(tid, rng, args.mask_wave4_known)
                blocks.append(blk)
                b_checks += n_chk
                total_theories += 1
            marker = f"W4-KF-HNT-BATCH-{b}-COMPLETE"
            blocks.append(f'(cw "~%{marker}~%")\n:q\n')
            rc, out = run_acl2_script(args.acl2, "\n\n".join(blocks), timeout_sec=args.timeout)
            issues = check_anomalies(rc, out, marker)
            total_checks += b_checks
            print(
                f"  [hints-steplimit-brr batch {b + 1}/{args.hint_batches}] "
                f"theories={args.theories_per_batch} checks={b_checks} rc={rc} issues={len(issues)}"
            )
            for iss in issues[:6]:
                print(f"    ! ANOMALY: {iss}")
            anomalies += len(issues)

        for b in range(args.apply_batches):
            script, b_checks = generate_apply_fn_instance_batch(b, args.theories_per_batch, rng)
            marker = f"W4-KF-APFI-BATCH-{b}-COMPLETE"
            rc, out = run_acl2_script(args.acl2, script, timeout_sec=args.timeout)
            issues = check_anomalies(rc, out, marker)
            total_theories += args.theories_per_batch
            total_checks += b_checks
            print(
                f"  [apply-fi batch {b + 1}/{args.apply_batches}] "
                f"theories={args.theories_per_batch} checks={b_checks} rc={rc} issues={len(issues)}"
            )
            for iss in issues[:6]:
                print(f"    ! ANOMALY: {iss}")
            anomalies += len(issues)

        print(
            f"[fuzz_fn_instance_sk] SUMMARY: theories={total_theories} "
            f"checks={total_checks} anomalies={anomalies}"
        )
        return 1 if anomalies else 0
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
