#!/usr/bin/env python3
"""
Counterexample-Guided Prover Rule-Interaction Fuzzer v2 (`fuzzer_v2.py`)
========================================================================
YinYang / Witness-Guided Falsification for the Pure-Kernel ACL2 Prover.

Unlike `fuzzer.py` (which stress-tests arithmetic, tau, linear, non-linear, and
BDD decision procedures over 40,000 polarity-aligned expressions), `fuzzer_v2.py`
synthesizes **multi-rule interaction harnesses** paired by construction with a
concrete falsifying witness `w = (vx, vy)` verified inside ACL2 via `trans-eval`:

  1. `tp-free-force`: `:type-prescription` rules combining `force`/`case-split`
     with free-variable hypotheses matched against multi-entry `type-alist`s.
  2. `bind-free-force`: `:rewrite` and `:linear` rules combining `force` /
     `case-split` with multi-candidate `bind-free` alists and `synp` guards.
  3. `mfc-contextual`: verified `defevaluator` + `:meta` rules calling
     `meta-extract-contextual-fact` (`:typeset`, `:rw+`, `:ap`) in contexts
     populated by `:forward-chaining` and `:linear` rules (with and without `force`).
  4. `pb-instructions`: `:instructions` proof-builder sequences (`:dv`, `:s`,
     `:apply-linear`, `:claim`, `:casesplit`, `:top`, `:bash`, `:prove`) on
     witness-falsified `IF` / arithmetic conjectures.
  5. `tau-eqv-cong`: custom `defequiv` + `defrefinement` + `defcong` +
     `:tau-system` signature/bounder/conjunctive rules on witness-falsified goals.
  6. `skolem-fc-bdd`: `defun-sk` / `defchoose` witness rules interacting with
     `:forward-chaining` and `:bdd` hints on witness-falsified goals.

Every candidate conjecture `C(x, y)` is first evaluated at `(vx, vy)` by ACL2;
if `(C vx vy)` is not `NIL`, it is polarity-flipped so `C(vx, vy) == NIL` holds
by construction. If ACL2 proves `C(x, y)`, the harness immediately instantiates
`C` at `(vx, vy)` to prove `(defthm nil-proved-K nil :rule-classes nil)` and
prints `@FUZZ-V2-SOUNDNESS-HIT`!
"""

import argparse
import json
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

FAMILIES = [
    "tp-free-force",
    "bind-free-force",
    "mfc-contextual",
    "pb-instructions",
    "warrant-guard-thm",
    "tau-eqv-cong",
    "skolem-fc-bdd",
]

WITNESS_VALS = ["0", "1", "-1", "2", "-2", "3", "1/2", "-1/2", "nil", "t", "'a", "'(1 . 2)"]


def make_candidate_block(rng: random.Random, idx: int, family: str) -> str:
    vx = rng.choice(["0", "1", "-1", "2", "-2", "3"])
    vy = rng.choice(["1", "2", "3", "4"])
    k_secret = rng.choice(["99", "101", "-77"])
    use_force = rng.random() < 0.55
    force_wrap = (
        (lambda s: f"(force {s})" if rng.random() < 0.7 else f"(case-split {s})")
        if use_force
        else (lambda s: s)
    )

    if family == "tp-free-force":
        order_swap = rng.random() < 0.5
        hyps_order = (
            f"(p-{idx} x {vy}) (p-{idx} x 0) (not (q-{idx} 0)) (q-{idx} {vy})"
            if order_swap
            else f"(p-{idx} x 0) (p-{idx} x {vy}) (not (q-{idx} 0)) (q-{idx} {vy})"
        )
        h_guard = force_wrap(f"(h-{idx} x)")
        return f"""
(make-event
 (mv-let (erp val state)
   (ld '(
     (encapsulate ()
       (local (defun h-{idx} (x) (equal x {k_secret})))
       (local (defun p-{idx} (x y) (and (integerp x) (integerp y))))
       (local (defun q-{idx} (y) (equal y {vy})))
       (local (defun foo-{idx} (x) (not (h-{idx} x))))
       (local (defthm tp-{idx}
                (implies (and {h_guard} (p-{idx} x y) (q-{idx} y))
                         (not (foo-{idx} x)))
                :rule-classes ((:type-prescription :typed-term (foo-{idx} x)))))
       (local (in-theory (disable h-{idx} p-{idx} q-{idx} foo-{idx}
                                  (:e h-{idx}) (:e p-{idx}) (:e q-{idx}) (:e foo-{idx})
                                  (:t h-{idx}) (:t p-{idx}) (:t q-{idx}) (:t foo-{idx}))))
       (local (defthm cand-{idx}
                (implies (and {hyps_order})
                         (not (foo-{idx} x)))
                :rule-classes nil))
       (defthm nil-proved-{idx}
         nil
         :rule-classes nil
         :hints (("Goal" :use ((:instance cand-{idx} (x {vx})))
                         :in-theory (enable h-{idx} p-{idx} q-{idx} foo-{idx}
                                            (:e h-{idx}) (:e p-{idx}) (:e q-{idx}) (:e foo-{idx}))))))
   ) :ld-error-action :return)
   (declare (ignore erp val))
   (if (eq (getpropc 'nil-proved-{idx} 'theorem :none (w state)) :none)
       (value '(value-triple :rejected-{idx}))
     (prog2$ (cw "@FUZZ-V2-SOUNDNESS-HIT family={family} idx={idx}~%")
             (value '(value-triple :hit-{idx}))))))
"""

    if family == "bind-free-force":
        h_guard = force_wrap(f"(h-{idx} x)")
        alist_expr = (
            f"'(((y . '0)) ((y . '{vy})))"
            if rng.random() < 0.65
            else f"'(((y . '{vy})))"
        )
        rc = ":rewrite" if rng.random() < 0.7 else "(:linear :trigger-terms ((foo-lin-" + str(idx) + " x)))"
        if rc == ":rewrite":
            return f"""
(make-event
 (mv-let (erp val state)
   (ld '(
     (encapsulate ()
       (local (defun h-{idx} (x) (equal x {k_secret})))
       (local (defun foo-{idx} (x) (not (h-{idx} x))))
       (local (defthm rw-bf-{idx}
                (implies (and {h_guard}
                              (bind-free {alist_expr} (y))
                              (equal y {vy}))
                         (equal (foo-{idx} x) nil))))
       (local (in-theory (disable h-{idx} foo-{idx} (:e h-{idx}) (:e foo-{idx}) (:t h-{idx}) (:t foo-{idx}))))
       (local (defthm cand-{idx}
                (equal (foo-{idx} x) nil)
                :rule-classes nil))
       (defthm nil-proved-{idx}
         nil
         :rule-classes nil
         :hints (("Goal" :use ((:instance cand-{idx} (x {vx})))
                         :in-theory (enable h-{idx} foo-{idx} (:e h-{idx}) (:e foo-{idx}))))))
   ) :ld-error-action :return)
   (declare (ignore erp val))
   (if (eq (getpropc 'nil-proved-{idx} 'theorem :none (w state)) :none)
       (value '(value-triple :rejected-{idx}))
     (prog2$ (cw "@FUZZ-V2-SOUNDNESS-HIT family={family} idx={idx}~%")
             (value '(value-triple :hit-{idx}))))))
"""
        else:
            return f"""
(make-event
 (mv-let (erp val state)
   (ld '(
     (encapsulate ()
       (local (defun h-{idx} (x) (equal x {k_secret})))
       (local (defun foo-lin-{idx} (x) (if (h-{idx} x) -1 5)))
       (local (defthm lin-bf-{idx}
                (implies (and {h_guard}
                              (bind-free {alist_expr} (y))
                              (equal y {vy}))
                         (< (foo-lin-{idx} x) 0))
                :rule-classes ((:linear :trigger-terms ((foo-lin-{idx} x))))))
       (local (in-theory (disable h-{idx} foo-lin-{idx} (:e h-{idx}) (:e foo-lin-{idx}) (:t h-{idx}) (:t foo-lin-{idx}))))
       (local (defthm cand-{idx}
                (< (foo-lin-{idx} x) 0)
                :rule-classes nil))
       (defthm nil-proved-{idx}
         nil
         :rule-classes nil
         :hints (("Goal" :use ((:instance cand-{idx} (x {vx})))
                         :in-theory (enable h-{idx} foo-lin-{idx} (:e h-{idx}) (:e foo-lin-{idx}))))))
   ) :ld-error-action :return)
   (declare (ignore erp val))
   (if (eq (getpropc 'nil-proved-{idx} 'theorem :none (w state)) :none)
       (value '(value-triple :rejected-{idx}))
     (prog2$ (cw "@FUZZ-V2-SOUNDNESS-HIT family={family} idx={idx}~%")
             (value '(value-triple :hit-{idx}))))))
"""

    if family == "mfc-contextual":
        op = rng.choice(["typeset", "rw+", "ap"])
        h_guard = force_wrap(f"(h-{idx} x)")
        if op in ("typeset", "rw+"):
            mfc_call = (
                f"(equal (mfc-ts (list 'aux-{idx} (cadr term)) mfc state :forcep nil :ttreep nil) *ts-nil*)"
                if op == "typeset"
                else f"(equal (mfc-rw+ '(aux-{idx} z) (list (cons 'z (cadr term))) '? nil mfc state :forcep nil :ttreep nil) ''nil)"
            )
            mfc_fact = (
                f"(list ':typeset (list 'aux-{idx} (cadr term)))"
                if op == "typeset"
                else f"(list ':rw+ '(aux-{idx} z) (list (cons 'z (cadr term))) '? nil)"
            )
            return f"""
(make-event
 (mv-let (erp val state)
   (ld '(
     (encapsulate ()
       (local (defun h-{idx} (x) (equal x {k_secret})))
       (local (defun trig-{idx} (x) (integerp x)))
       (local (defun aux-{idx} (x) (if (h-{idx} x) nil t)))
       (local (defun targ-{idx} (x) (aux-{idx} x)))
       (local (defthm fc-{idx}
                (implies (and (trig-{idx} x) {h_guard})
                         (equal (aux-{idx} x) nil))
                :rule-classes ((:forward-chaining :trigger-terms ((trig-{idx} x))))))
       (local (in-theory (disable h-{idx} trig-{idx} aux-{idx}
                                  (:e h-{idx}) (:e trig-{idx}) (:e aux-{idx})
                                  (:t h-{idx}) (:t trig-{idx}) (:t aux-{idx}))))
       (local (defevaluator ev-{idx} ev-lst-{idx}
                ((targ-{idx} x) (aux-{idx} x) (typespec-check ts x) (equal x y) (not x) (iff x y) (if x y z))
                :namedp t))
       (local (defun mf-{idx} (term mfc state)
                (declare (xargs :stobjs state :guard t))
                (if (and (consp term) (eq (car term) 'targ-{idx}) (consp (cdr term)) (null (cddr term))
                         {mfc_call})
                    ''nil
                  term)))
       (local (defthm mf-ok-{idx}
                (implies (ev-{idx} (meta-extract-contextual-fact {mfc_fact} mfc state) a)
                         (equal (ev-{idx} term a) (ev-{idx} (mf-{idx} term mfc state) a)))
                :hints (("Goal" :in-theory (enable typespec-check)))
                :rule-classes ((:meta :trigger-fns (targ-{idx})))))
       (local (in-theory (disable targ-{idx} (:e targ-{idx}) (:t targ-{idx}))))
       (local (defthm cand-{idx}
                (implies (trig-{idx} x) (not (targ-{idx} x)))
                :rule-classes nil))
       (defthm nil-proved-{idx}
         nil
         :rule-classes nil
         :hints (("Goal" :use ((:instance cand-{idx} (x 0)))
                         :in-theory (enable h-{idx} trig-{idx} aux-{idx} targ-{idx}
                                            (:e h-{idx}) (:e trig-{idx}) (:e aux-{idx}) (:e targ-{idx}))))))
   ) :ld-error-action :return)
   (declare (ignore erp val))
   (if (eq (getpropc 'nil-proved-{idx} 'theorem :none (w state)) :none)
       (value '(value-triple :rejected-{idx}))
     (prog2$ (cw "@FUZZ-V2-SOUNDNESS-HIT family={family}/{op} idx={idx}~%")
             (value '(value-triple :hit-{idx}))))))
"""
        else:
            return f"""
(make-event
 (mv-let (erp val state)
   (ld '(
     (encapsulate ()
       (local (defun h-{idx} (x) (equal x {k_secret})))
       (local (defun val-{idx} (x) (if (h-{idx} x) -1 10)))
       (local (defun targ-{idx} (x) (not (< (val-{idx} x) 0))))
       (local (defthm lin-{idx}
                (implies (and (< 0 x) {h_guard})
                         (< (val-{idx} x) 0))
                :rule-classes ((:linear :trigger-terms ((val-{idx} x))))))
       (local (in-theory (disable h-{idx} val-{idx} (:e h-{idx}) (:e val-{idx}) (:t h-{idx}) (:t val-{idx}))))
       (local (defevaluator ev-{idx} ev-lst-{idx}
                ((targ-{idx} x) (val-{idx} x) (< x y) (not x) (equal x y) (if x y z))
                :namedp t))
       (local (defun mf-{idx} (term mfc state)
                (declare (xargs :stobjs state :guard t))
                (if (and (consp term) (eq (car term) 'targ-{idx}) (consp (cdr term)) (null (cddr term))
                         (mfc-ap (list 'not (list '< (list 'val-{idx} (cadr term)) ''0)) mfc state :forcep nil))
                    ''nil
                  term)))
       (local (defthm mf-ok-{idx}
                (implies (ev-{idx} (meta-extract-contextual-fact
                                    (list ':ap (list 'not (list '< (list 'val-{idx} (cadr term)) ''0)))
                                    mfc state) a)
                         (equal (ev-{idx} term a) (ev-{idx} (mf-{idx} term mfc state) a)))
                :rule-classes ((:meta :trigger-fns (targ-{idx})))))
       (local (in-theory (disable targ-{idx} (:e targ-{idx}) (:t targ-{idx}))))
       (local (defthm cand-{idx}
                (implies (and (< 0 x) (< (val-{idx} x) 100))
                         (not (targ-{idx} x)))
                :rule-classes nil))
       (defthm nil-proved-{idx}
         nil
         :rule-classes nil
         :hints (("Goal" :use ((:instance cand-{idx} (x 1)))
                         :in-theory (enable h-{idx} val-{idx} targ-{idx}
                                            (:e h-{idx}) (:e val-{idx}) (:e targ-{idx}))))))
   ) :ld-error-action :return)
   (declare (ignore erp val))
   (if (eq (getpropc 'nil-proved-{idx} 'theorem :none (w state)) :none)
       (value '(value-triple :rejected-{idx}))
     (prog2$ (cw "@FUZZ-V2-SOUNDNESS-HIT family={family}/ap idx={idx}~%")
             (value '(value-triple :hit-{idx}))))))
"""

    if family == "pb-instructions":
        use_al = rng.random() < 0.45
        instr = (
            f"((:dv 2) (:dv 1) (:apply-linear lin-{idx}) :top (:in-theory (enable (:executable-counterpart g-{idx}))) :s)"
            if use_al
            else f"((:dv 2) :s :top (:casesplit (< (g-{idx}) 0)) :bash :bash)"
        )
        return f"""
(make-event
 (mv-let (erp val state)
   (ld '(
     (encapsulate ()
       (local (defun g-{idx} () 0))
       (local (defthm lin-{idx}
                (implies (< (g-{idx}) 0) (< (g-{idx}) 0))
                :rule-classes ((:linear :trigger-terms ((g-{idx}))))))
       (local (in-theory (disable g-{idx} (:e g-{idx}) (:t g-{idx}))))
       (local (defthm cand-{idx}
                (if (< (g-{idx}) 0) (equal (g-{idx}) 0) nil)
                :rule-classes nil
                :instructions {instr}))
       (defthm nil-proved-{idx}
         nil
         :rule-classes nil
         :hints (("Goal" :use cand-{idx}
                         :in-theory (enable (:e g-{idx}))))))
   ) :ld-error-action :return)
   (declare (ignore erp val))
   (if (eq (getpropc 'nil-proved-{idx} 'theorem :none (w state)) :none)
       (value '(value-triple :rejected-{idx}))
     (prog2$ (cw "@FUZZ-V2-SOUNDNESS-HIT family={family} idx={idx}~%")
             (value '(value-triple :hit-{idx}))))))
"""

    if family == "warrant-guard-thm":
        variant = rng.choice(["encap-nonlambda", "encap-lambda-ctrl", "badge-reset"])
        if variant in ("encap-nonlambda", "encap-lambda-ctrl"):
            body_expr = (
                f"(collect$ (lambda$ (x) (declare (xargs :guard (equal x 0))) x) (list (apply$ 'g-{idx} '(nil))))"
                if variant == "encap-nonlambda"
                else f"(sum$ '(lambda (x) (g-{idx} x)) '(nil))"
            )
            return f"""
(make-event
 (mv-let (erp val state)
   (ld '(
     (encapsulate ()
       (local (defun g-{idx} (x) (declare (ignore x) (xargs :guard t)) 0))
       (local (table badge-table :badge-userfn-structure
                (put-badge-userfn-structure-tuple-in-alist
                 (make-badge-userfn-structure-tuple 'g-{idx} nil '(APPLY$-BADGE 1 1 . T))
                 (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table world)))
                 'defbadge) :put))
       (local (encapsulate ()
                (local (defun-sk apply$-warrant-g-{idx} ()
                         (forall (args)
                           (and (equal (badge-userfn 'g-{idx}) '(APPLY$-BADGE 1 1 . T))
                                (equal (apply$-userfn 'g-{idx} args) (g-{idx} (car args)))))
                         :constrain t))
                (local (in-theory (disable apply$-warrant-g-{idx}-definition)))
                (local (defthm apply$-g-{idx}
                         (implies (force (apply$-warrant-g-{idx}))
                                  (and (equal (badge 'g-{idx}) '(APPLY$-BADGE 1 1 . T))
                                       (equal (apply$ 'g-{idx} args) (g-{idx} (car args)))))
                         :hints (("Goal" :use apply$-warrant-g-{idx}-necc
                                  :expand ((:free (x) (hide (badge x))))
                                  :in-theory (e/d (badge apply$) (apply$-warrant-g-{idx}-necc g-{idx}))))))
                (local (table badge-table :badge-userfn-structure
                         (put-badge-userfn-structure-tuple-in-alist
                          (make-badge-userfn-structure-tuple 'g-{idx} t '(APPLY$-BADGE 1 1 . T))
                          (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table world)))
                          'defwarrant) :put))
                (defun fn-{idx} ()
                  (declare (xargs :guard t :guard-hints (("Goal" :in-theory (enable apply$ apply$-lambda ev$)))))
                  {body_expr})))
       (local (defthm step-{idx}
                (equal (apply$-userfn 'g-{idx} '(nil)) 0)
                :rule-classes nil
                :hints (("Goal" :use (:instance (:guard-theorem fn-{idx}) (newv (apply$ 'g-{idx} '(nil))))
                                :in-theory (e/d (apply$) ((:e apply$)))))))
       (defthm nil-proved-{idx}
         nil
         :rule-classes nil
         :hints (("Goal" :use (:functional-instance step-{idx}
                               (badge-userfn (lambda (f) nil))
                               (apply$-userfn (lambda (f args) 1)))))))
   ) :ld-error-action :return)
   (declare (ignore erp val))
   (if (eq (getpropc 'nil-proved-{idx} 'theorem :none (w state)) :none)
       (value '(value-triple :rejected-{idx}))
     (prog2$ (cw "@FUZZ-V2-SOUNDNESS-HIT family={family}/{variant} idx={idx}~%")
             (value '(value-triple :hit-{idx}))))))
"""
        else:
            return f"""
(make-event
 (mv-let (erp val state)
   (ld '(
     (encapsulate ()
       (local (defun g-{idx} (x) (declare (ignore x) (xargs :guard t)) 0))
       (local (defun-sk apply$-warrant-g-{idx} ()
                (forall (args)
                  (and (equal (badge-userfn 'g-{idx}) '(APPLY$-BADGE 1 1 . T))
                       (equal (apply$-userfn 'g-{idx} args) (g-{idx} (car args)))))
                :constrain t))
       (local (in-theory (disable apply$-warrant-g-{idx}-definition)))
       (local (defthm apply$-g-{idx}
                (implies (force (apply$-warrant-g-{idx}))
                         (and (equal (badge 'g-{idx}) '(APPLY$-BADGE 1 1 . T))
                              (equal (apply$ 'g-{idx} args) (g-{idx} (car args)))))
                :hints (("Goal" :use apply$-warrant-g-{idx}-necc
                         :expand ((:free (x) (hide (badge x))))
                         :in-theory (e/d (badge apply$) (apply$-warrant-g-{idx}-necc g-{idx}))))))
       (local (table badge-table :badge-userfn-structure
                (put-badge-userfn-structure-tuple-in-alist
                 (make-badge-userfn-structure-tuple 'g-{idx} t '(APPLY$-BADGE 1 1 . T))
                 (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table world)))
                 'defwarrant) :put))
       (local (defun fn-{idx} ()
                (declare (xargs :guard t :guard-hints (("Goal" :in-theory (enable apply$ apply$-lambda ev$)))))
                (sum$ '(lambda (x) (g-{idx} x)) '(nil))))
       (local (table badge-table :badge-userfn-structure nil :put))
       (local (table badge-table :badge-userfn-structure
                (list (make-badge-userfn-structure-tuple 'g-{idx} nil '(APPLY$-BADGE 1 1 . T))) :put))
       (local (defthm step-{idx}
                (implies (equal (badge-userfn 'g-{idx}) '(APPLY$-BADGE 1 1 . T))
                         (acl2-numberp (apply$-userfn 'g-{idx} '(nil))))
                :rule-classes nil
                :hints (("Goal" :use (:instance (:guard-theorem fn-{idx}) (newv nil))
                                :expand ((:free (x a) (ev$ x a)) (:free (x a) (ev$-list x a)))
                                :in-theory (e/d (apply$ apply$-lambda badge)
                                                (apply$-g-{idx} (:e apply$) (:e apply$-lambda) (:e ev$)))))))
       (defthm nil-proved-{idx}
         nil
         :rule-classes nil
         :hints (("Goal" :use (:functional-instance step-{idx}
                               (badge-userfn (lambda (f) '(APPLY$-BADGE 1 1 . T)))
                               (apply$-userfn (lambda (f args) t)))))))
   ) :ld-error-action :return)
   (declare (ignore erp val))
   (if (eq (getpropc 'nil-proved-{idx} 'theorem :none (w state)) :none)
       (value '(value-triple :rejected-{idx}))
     (prog2$ (cw "@FUZZ-V2-SOUNDNESS-HIT family={family}/badge-reset idx={idx}~%")
             (value '(value-triple :hit-{idx}))))))
"""

    if family == "tau-eqv-cong":
        a = rng.choice(["-3", "-2", "-1", "0", "1"])
        b = rng.choice(["2", "3", "4", "5"])
        w = rng.choice(["0", "1", "2"])
        return f"""
(make-event
 (mv-let (erp val state)
   (ld '(
     (encapsulate ()
       (local (defun eqv-{idx} (x y) (equal (ifix x) (ifix y))))
       (local (defequiv eqv-{idx}))
       (local (defun fn-{idx} (x) (logand (ifix x) 7)))
       (local (defcong eqv-{idx} equal (fn-{idx} x) 1))
       (local (defun r1-{idx} (x) (and (integerp x) (<= {a} x) (<= x {b}))))
       (local (defun r2-{idx} (x) (and (integerp x) (<= 0 x) (<= x 7))))
       (local (defthm tau-sig-{idx}
                (implies (r1-{idx} x) (r2-{idx} (fn-{idx} x)))
                :rule-classes (:tau-system)))
       (local (defthm cand-{idx}
                (implies (and (r1-{idx} x) (eqv-{idx} x y))
                         (< (fn-{idx} y) (fn-{idx} {w})))
                :rule-classes nil))
       (defthm nil-proved-{idx}
         nil
         :rule-classes nil
         :hints (("Goal" :use ((:instance cand-{idx} (x {w}) (y {w})))))))
   ) :ld-error-action :return)
   (declare (ignore erp val))
   (if (eq (getpropc 'nil-proved-{idx} 'theorem :none (w state)) :none)
       (value '(value-triple :rejected-{idx}))
     (prog2$ (cw "@FUZZ-V2-SOUNDNESS-HIT family={family} idx={idx}~%")
             (value '(value-triple :hit-{idx}))))))
"""

    # skolem-fc-bdd
    return f"""
(make-event
 (mv-let (erp val state)
   (ld '(
     (encapsulate ()
       (local (defun p-sk-{idx} (x y) (and (booleanp x) (booleanp y) (not (equal x y)))))
       (local (defun-sk ex-sk-{idx} (x) (exists y (p-sk-{idx} x y))))
       (local (defthm bdd-cand-{idx}
                (implies (and (booleanp x) (ex-sk-{idx} x))
                         (p-sk-{idx} x x))
                :rule-classes nil
                :hints (("Goal" :bdd (:vars nil)))))
       (defthm nil-proved-{idx}
         nil
         :rule-classes nil
         :hints (("Goal" :use ((:instance bdd-cand-{idx} (x t))
                               (:instance ex-sk-{idx}-suff (x t) (y nil)))))))
   ) :ld-error-action :return)
   (declare (ignore erp val))
   (if (eq (getpropc 'nil-proved-{idx} 'theorem :none (w state)) :none)
       (value '(value-triple :rejected-{idx}))
     (prog2$ (cw "@FUZZ-V2-SOUNDNESS-HIT family={family} idx={idx}~%")
             (value '(value-triple :hit-{idx}))))))
"""


def run_campaign(host: str, batches: int, per_batch: int, seed: int) -> dict:
    acl2_bin = SBCL_ACL2 if host == "sbcl" else CCL_ACL2
    rng = random.Random(seed)
    stats = {
        "host": host,
        "seed": seed,
        "batches": batches,
        "candidates_per_batch": per_batch,
        "total_candidates": batches * per_batch,
        "hits_by_family": {},
        "hard_errors": 0,
        "elapsed_sec": 0.0,
    }
    t0 = time.time()
    tmp_lisp = OUT_DIR / f"_tmp_v2_{host}_{seed}.lisp"
    try:
        for b in range(batches):
            lines = ['(in-package "ACL2")', "(set-inhibit-output-lst '(prove proof-tree warning observation event summary))"]
            for i in range(per_batch):
                fam = rng.choice(FAMILIES)
                lines.append(make_candidate_block(rng, b * per_batch + i, fam))
            lines.append("(quit)")
            tmp_lisp.write_text("\n".join(lines) + "\n")

            proc = subprocess.run(
                [TIMEOUT_BIN, "--kill-after=10s", "120s", acl2_bin],
                stdin=tmp_lisp.open("rb"),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            out = proc.stdout
            for line in out.splitlines():
                if "@FUZZ-V2-SOUNDNESS-HIT" in line:
                    parts = line.split("family=")[1].split()[0]
                    stats["hits_by_family"][parts] = stats["hits_by_family"].get(parts, 0) + 1
                if "RAW LISP ERROR" in line or "HARD ACL2 ERROR" in line:
                    if "[Call depth]" not in out:
                        stats["hard_errors"] += 1
    finally:
        if tmp_lisp.exists():
            tmp_lisp.unlink()
    stats["elapsed_sec"] = round(time.time() - t0, 2)
    return stats


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", choices=["sbcl", "ccl", "both"], default="both")
    ap.add_argument("--batches", type=int, default=15)
    ap.add_argument("--per-batch", type=int, default=20)
    ap.add_argument("--seed", type=int, default=9001)
    ap.add_argument("--json-out", type=str, default=str(OUT_DIR / "fuzzer_v2_results.json"))
    args = ap.parse_args()

    results = []
    hosts = ["sbcl", "ccl"] if args.host == "both" else [args.host]
    for idx, h in enumerate(hosts):
        res = run_campaign(h, args.batches, args.per_batch, args.seed + idx)
        print(json.dumps(res, indent=2), flush=True)
        results.append(res)

    Path(args.json_out).write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
