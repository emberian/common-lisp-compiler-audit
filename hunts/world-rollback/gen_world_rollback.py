#!/usr/bin/env python3
"""
World-Rollback State-Machine Fuzzer for ACL2 ("Jepsen / QuickCheck StateMachine")
=================================================================================

Tests observational rollback equivalence across SBCL 2.6.10 and CCL 1.14:

    Oracle:  Run(Fresh -> B -> P)  ==  Run(Fresh -> B -> H -> Rollback(H) -> P)

where:
  - B is a baseline event sequence that survives rollback (0..3 events),
  - H is a multi-step state-machine history over reused symbol/stobj/package names
    (defun, defun-nx, defund, defmacro, defconst, defstobj with scalar/resizable-array/
    hash-table/congruent/nested/stobj-table/:inline/:non-executable fields, defabsstobj,
    remove-global-stobj / add-global-stobj, verify-guards, comp, defattach, memoize /
    unmemoize, apply$ / defwarrant / lambda$, defpkg, table, add-custom-keyword-hint),
  - Rollback(H) is one of 6 ACL2 world-reversion boundaries:
      1. ubt            (:ubt! mark)
      2. encap-local    (encapsulate () (local ...))
      3. encap-fail     intentional mid-encapsulate error (revert-world-on-error)
      4. ld-fail        failed (ld ... :ld-error-action :return!)
      5. certify-reset  post-(certify-book ...) world reset
      6. include-fail   failed (include-book ...) after compiled-book early load
  - P is an observational probe suite reusing the same symbol/stobj names and
    recording admission erp, guard-verified evaluation values, stobj live invariants,
    memoize/apply$/defattach coherence, and raw Common Lisp errors/crashes.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import copy
import dataclasses
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

TIMEOUT_BIN = "/opt/homebrew/bin/timeout"
SBCL_ACL2 = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2 = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

ROLLBACK_OPS = [
    "ubt",
    "encap-local",
    "encap-fail",
    "progn-fail",
    "ld-fail",
    "certify-reset",
    "include-fail",
]


@dataclasses.dataclass
class FnInfo:
    name: str
    kind: str  # "defun", "defund", "defun-nx", "defmacro"
    arity: int
    mv_out: int = 1
    mode: str = ":logic"
    guard_verified: bool = False
    stobj_arg: Optional[str] = None
    warranted: bool = False
    memoized: bool = False


@dataclasses.dataclass
class StobjInfo:
    name: str
    variant: str  # "scalar", "array", "ht", "congruent", "nested", "table", "abs"
    recognizer: str
    accessor: str
    updater: str
    congruent_to: Optional[str] = None
    child_stobj: Optional[str] = None
    non_executable: bool = False
    global_live: bool = True


@dataclasses.dataclass
class WorldModel:
    fns: Dict[str, FnInfo] = dataclasses.field(default_factory=dict)
    stobjs: Dict[str, StobjInfo] = dataclasses.field(default_factory=dict)
    consts: Set[str] = dataclasses.field(default_factory=set)
    pkgs: Set[str] = dataclasses.field(default_factory=set)
    has_stub_ds1: bool = False
    ds1_attached: Optional[str] = None
    ds1_caller_memo: bool = False
    include_apply_top: bool = False
    hint_installed: bool = False
    step_counter: int = 0

    def clone(self) -> "WorldModel":
        return copy.deepcopy(self)

    def used_names(self) -> Set[str]:
        used = set(self.fns.keys()) | set(self.stobjs.keys()) | set(self.consts)
        for st in self.stobjs.values():
            used.update({st.name, st.recognizer, st.accessor, st.updater})
            if st.variant == "array":
                used.update({f"{st.accessor}-length", f"resize-{st.accessor}"})
        if self.has_stub_ds1:
            used.update({"ds1", "call-ds1"})
        return used


FN_POOL = ["f1", "f2", "f3"]
MACRO_POOL = ["m1", "f1"]  # note f1 shared between macro & fn to test fn<->macro swap!
STOBJ_POOL = [
    ("st1", "st1p", "st1-fld", "update-st1-fld"),
    ("st2", "st2p", "st2-fld", "update-st2-fld"),
]


def emit_probe_expr(tag: str, expr: str, stobjs_out: str = "(nil)") -> str:
    """Wrap an ACL2 expression in trans-eval and print deterministic @PROBE output."""
    return (
        f"(mv-let (erp val state)\n"
        f"  (trans-eval '{expr} 'wrb-probe state t)\n"
        f"  (prog2$ (cw \"@PROBE {tag} erp=~x0 val=~x1~%\" erp val)\n"
        f"          state))"
    )


def emit_probe_event(tag: str, event_form: str) -> str:
    """Run an event via ld :ld-error-action :return! so admission differences show in @PROBE."""
    return (
        f"(mv-let (erp val state)\n"
        f"  (ld '({event_form}) :ld-error-action :return! :ld-verbose nil :ld-prompt nil)\n"
        f"  (declare (ignore val))\n"
        f"  (prog2$ (cw \"@PROBE {tag} admit-erp=~x0~%\" erp)\n"
        f"          state))"
    )


class ScenarioGenerator:
    def __init__(self, rng: random.Random, allow_found_triggers: bool = False):
        self.rng = rng
        self.allow_found_triggers = allow_found_triggers

    def fresh_uid(self, model: WorldModel) -> int:
        model.step_counter += 1
        return model.step_counter

    def gen_step(
        self,
        model: WorldModel,
        in_local_encap: bool = False,
        in_book: bool = False,
        is_baseline: bool = False,
    ) -> Optional[str]:
        used = model.used_names()
        choices: List[str] = []

        # 1. Functions / Macros / Constants
        free_fns = [f for f in FN_POOL if f not in used]
        if free_fns:
            choices.extend(["defun_1", "defun_2", "defun_mv", "defund", "defun_nx", "defun_mbe"])
            if model.include_apply_top:
                choices.append("defun_warrant_apply")
        free_macros = [m for m in MACRO_POOL if m not in used]
        if free_macros:
            choices.append("defmacro")
        if "*c1*" not in used:
            choices.append("defconst")

        # 2. Guard verification / compilation / memoize on existing functions
        unverified = [
            fn for fn in model.fns.values()
            if fn.kind in ("defun", "defund") and fn.mode == ":logic" and not fn.guard_verified
        ]
        if unverified:
            choices.append("verify_guards")
        compilable = [fn for fn in model.fns.values() if fn.kind in ("defun", "defund")]
        if compilable and not in_book:
            choices.append("comp_fn")
        memo_candidates = [
            fn for fn in model.fns.values()
            if fn.kind in ("defun", "defund")
            and fn.mode == ":logic"
            and fn.guard_verified
            and fn.mv_out == 1
            and not fn.memoized
        ]
        if memo_candidates:
            choices.append("memoize_fn")
        unmemo_candidates = [fn for fn in model.fns.values() if fn.memoized]
        if unmemo_candidates:
            choices.append("unmemoize_fn")

        # 3. Concrete & Abstract Stobjs
        free_stobjs = [s for s in STOBJ_POOL if s[0] not in used]
        if free_stobjs:
            choices.extend([
                "stobj_scalar",
                "stobj_array",
                "stobj_inline",
                "stobj_nonexec",
            ])
            scalar_live = [
                st for st in model.stobjs.values()
                if st.variant == "scalar" and st.global_live and not st.non_executable and st.congruent_to is None
            ]
            if scalar_live:
                choices.append("stobj_congruent")
                if "nest1" not in used:
                    choices.append("stobj_nested")
            if "abs1" not in used and "abs1$c" not in used:
                choices.append("defabsstobj")

        if "tbl1" not in used:
            choices.append("stobj_table_create")

        # Mutations on live stobjs
        # In exploratory clean mode, mutate stobjs introduced in H (or check invariants on B stobjs)
        live_scalars = [
            st for st in model.stobjs.values()
            if st.variant in ("scalar", "congruent") and st.global_live and not st.non_executable
        ]
        if live_scalars and not in_book and (is_baseline or self.allow_found_triggers):
            choices.append("mutate_scalar_stobj")
        live_arrays = [
            st for st in model.stobjs.values()
            if st.variant == "array" and st.global_live and not st.non_executable
        ]
        if live_arrays and not in_book and (is_baseline or self.allow_found_triggers):
            choices.append("mutate_resize_stobj")

        # Congruent swap-stobjs
        cong_pairs = [
            (st, model.stobjs[st.congruent_to])
            for st in model.stobjs.values()
            if st.congruent_to and st.congruent_to in model.stobjs
            and st.global_live and model.stobjs[st.congruent_to].global_live
        ]
        if cong_pairs and not in_book and (is_baseline or self.allow_found_triggers):
            choices.append("swap_congruent_stobjs")

        # Nested stobj swap (WRB-S1 trigger if st1 + congruent st2 + nest1 in baseline, and H defines a stobj + swaps!)
        if self.allow_found_triggers and "nest1" in model.stobjs and not in_book:
            child_name = model.stobjs["nest1"].child_stobj
            cong_siblings = [
                s for s in model.stobjs.values()
                if s.congruent_to == child_name and s.global_live
            ]
            if child_name and child_name in model.stobjs and model.stobjs[child_name].global_live and cong_siblings:
                choices.append("nested_swap_stobj_trigger")

        # Stobj-table populate (WRB-S2 / WRB-R1 trigger if tbl1 in baseline and child stobj in H!)
        if "tbl1" in model.stobjs and live_scalars:
            if self.allow_found_triggers or is_baseline:
                choices.append("populate_stobj_table")

        # remove-global-stobj / add-global-stobj (WRB-R2 trigger if combined with stobj rollback)
        if not in_book and self.allow_found_triggers:
            removable = [st for st in model.stobjs.values() if st.global_live and not st.non_executable]
            addable = [st for st in model.stobjs.values() if not st.global_live and not st.non_executable]
            if removable:
                choices.append("remove_global_stobj")
            if addable:
                choices.append("add_global_stobj")

        # 4. Stubs + defattach + memoize :aokp t
        if not model.has_stub_ds1 and "ds1" not in used:
            choices.append("define_stub_ds1")
        elif model.has_stub_ds1:
            choices.append("reattach_ds1")

        # 5. Tables & custom keyword hints & packages
        choices.append("table_defaults")
        if not model.hint_installed:
            choices.append("custom_keyword_hint")
        if not in_local_encap and not in_book and "WRB-PKG1" not in model.pkgs and is_baseline:
            choices.append("defpkg_wrb")

        if not choices:
            return None

        op = self.rng.choice(choices)
        k = self.rng.randint(1, 50)
        uid = self.fresh_uid(model)

        if op == "defun_1":
            fn = self.rng.choice(free_fns)
            vg = self.rng.choice([True, False])
            mode = ":logic" if vg else self.rng.choice([":logic", ":program"])
            decl = (
                f"(declare (xargs :mode {mode}"
                + (" :guard (integerp x) :verify-guards t" if vg else " :guard (integerp x) :verify-guards nil" if mode == ":logic" else "")
                + "))"
            )
            model.fns[fn] = FnInfo(fn, "defun", 1, 1, mode, vg)
            return f"(defun {fn} (x) {decl} (+ (ifix x) {k}))"

        if op == "defun_2":
            fn = self.rng.choice(free_fns)
            vg = self.rng.choice([True, False])
            model.fns[fn] = FnInfo(fn, "defun", 2, 1, ":logic", vg)
            return (
                f"(defun {fn} (x y)\n"
                f"  (declare (xargs :guard (and (integerp x) (integerp y)) :verify-guards {'t' if vg else 'nil'}))\n"
                f"  (+ (* {k} (ifix x)) (ifix y)))"
            )

        if op == "defun_mv":
            fn = self.rng.choice(free_fns)
            model.fns[fn] = FnInfo(fn, "defun", 1, 2, ":logic", True)
            return (
                f"(defun {fn} (x)\n"
                f"  (declare (xargs :guard (integerp x) :verify-guards t))\n"
                f"  (mv (+ (ifix x) {k}) (- (ifix x) {k})))"
            )

        if op == "defund":
            fn = self.rng.choice(free_fns)
            model.fns[fn] = FnInfo(fn, "defund", 1, 1, ":logic", True)
            return (
                f"(defund {fn} (x)\n"
                f"  (declare (xargs :guard t :verify-guards t))\n"
                f"  (+ (nfix x) {k}))"
            )

        if op == "defun_nx":
            fn = self.rng.choice(free_fns)
            model.fns[fn] = FnInfo(fn, "defun-nx", 1, 1, ":logic", False)
            return f"(defun-nx {fn} (x) (cons {k} x))"

        if op == "defun_mbe":
            fn = self.rng.choice(free_fns)
            model.fns[fn] = FnInfo(fn, "defun", 1, 1, ":logic", True)
            return (
                f"(defun {fn} (x)\n"
                f"  (declare (xargs :guard (natp x) :verify-guards t))\n"
                f"  (mbe :logic (+ (nfix x) {k}) :exec (the integer (+ x {k}))))"
            )

        if op == "defun_warrant_apply":
            fn = self.rng.choice(free_fns)
            model.fns[fn] = FnInfo(fn, "defun", 1, 1, ":logic", True, warranted=True)
            warm = ""
            if not in_book:
                warm = (
                    f"\n  (value-triple (apply$ '{fn} '(7)))"
                    f"\n  (value-triple (apply$ '(lambda$ (z) ({fn} z)) '(7)))"
                )
            return (
                f"(progn\n"
                f"  (defun$ {fn} (x) (declare (xargs :guard t :verify-guards t)) (+ (nfix x) {k})){warm})"
            )

        if op == "defmacro":
            m = self.rng.choice(free_macros)
            model.fns[m] = FnInfo(m, "defmacro", 1, 1, ":logic", False)
            return f"(defmacro {m} (x) (list '+ x {k}))"

        if op == "defconst":
            model.consts.add("*c1*")
            return f"(defconst *c1* '{k})"

        if op == "verify_guards":
            fn_info = self.rng.choice(unverified)
            fn_info.guard_verified = True
            return f"(verify-guards {fn_info.name})"

        if op == "comp_fn":
            fn_info = self.rng.choice(compilable)
            return f"(comp '{fn_info.name})"

        if op == "memoize_fn":
            fn_info = self.rng.choice(memo_candidates)
            fn_info.memoized = True
            call_args = " ".join(str(i + 3) for i in range(fn_info.arity))
            warm = f"\n  (value-triple ({fn_info.name} {call_args}))" if not in_book and fn_info.stobj_arg is None else ""
            return f"(progn (memoize '{fn_info.name}){warm})"

        if op == "unmemoize_fn":
            fn_info = self.rng.choice(unmemo_candidates)
            fn_info.memoized = False
            return f"(unmemoize '{fn_info.name})"

        if op == "stobj_scalar":
            name, rec, acc, upd = self.rng.choice(free_stobjs)
            model.stobjs[name] = StobjInfo(name, "scalar", rec, acc, upd)
            return f"(defstobj {name} ({acc} :type integer :initially {k}))"

        if op == "stobj_inline":
            name, rec, acc, upd = self.rng.choice(free_stobjs)
            model.stobjs[name] = StobjInfo(name, "scalar", rec, acc, upd)
            return f"(defstobj {name} ({acc} :type (signed-byte 32) :initially {k}) :inline t)"

        if op == "stobj_nonexec":
            name, rec, acc, upd = self.rng.choice(free_stobjs)
            model.stobjs[name] = StobjInfo(
                name, "scalar", rec, acc, upd, non_executable=True, global_live=False
            )
            return f"(defstobj {name} ({acc} :type integer :initially {k}) :non-executable t)"

        if op == "stobj_array":
            name, rec, acc, _ = self.rng.choice(free_stobjs)
            model.stobjs[name] = StobjInfo(name, "array", rec, acc, f"update-{acc}i")
            return f"(defstobj {name} ({acc} :type (array integer (4)) :initially {k} :resizable t))"

        if op == "stobj_congruent":
            name, rec, acc, upd = self.rng.choice(free_stobjs)
            target = self.rng.choice(scalar_live)
            model.stobjs[name] = StobjInfo(
                name, "congruent", rec, target.accessor, target.updater, congruent_to=target.name
            )
            return f"(defstobj {name} ({target.accessor} :type integer :initially 0) :congruent-to {target.name})"

        if op == "stobj_nested":
            target = self.rng.choice(scalar_live)
            model.stobjs["nest1"] = StobjInfo(
                "nest1", "nested", "nest1p", "nest1-c1", "update-nest1-c1", child_stobj=target.name
            )
            model.fns["chk-nest1-disjoint"] = FnInfo("chk-nest1-disjoint", "defun", 1, 2, ":logic", True, stobj_arg="nest1")
            return (
                f"(progn\n"
                f"  (defstobj nest1 (nest1-c1 :type {target.name}) (nest1-c2 :type {target.name}))\n"
                f"  (defun chk-nest1-disjoint (nest1)\n"
                f"    (declare (xargs :stobjs nest1 :guard t))\n"
                f"    (let* ((nest1 (stobj-let (({target.name} (nest1-c1 nest1))) ({target.name}) ({target.updater} 111 {target.name}) nest1))\n"
                f"           (nest1 (stobj-let (({target.name} (nest1-c2 nest1))) ({target.name}) ({target.updater} 222 {target.name}) nest1)))\n"
                f"      (stobj-let (({target.name} (nest1-c1 nest1))) (v) ({target.accessor} {target.name}) (mv v nest1)))))"
            )

        if op == "stobj_table_create":
            model.stobjs["tbl1"] = StobjInfo(
                "tbl1", "table", "tbl1p", "tbl1-get", "tbl1-put"
            )
            rfn = "read-tbl1-keys"
            extra = ""
            if rfn not in used:
                model.fns[rfn] = FnInfo(rfn, "defun", 1, 1, ":logic", True, stobj_arg="tbl1", memoized=True)
                extra = (
                    f"\n  (defun {rfn} (tbl1) (declare (xargs :stobjs tbl1)) (tbl1-keys tbl1))"
                    f"\n  (memoize '{rfn})"
                )
            return (
                f"(progn\n"
                f"  (defstobj tbl1 (tbl1 :type (stobj-table))){extra})"
            )

        if op == "defabsstobj":
            model.stobjs["abs1$c"] = StobjInfo("abs1$c", "scalar", "abs1$cp", "abs1-v$c", "update-abs1-v$c")
            model.stobjs["abs1"] = StobjInfo("abs1", "abs", "abs1p", "abs1-v", "update-abs1-v")
            for sym in [
                "abs1$ap", "create-abs1$a", "abs1-v$a", "update-abs1-v$a",
                "abs1-corr", "abs1-corr-create", "abs1-corr-v", "abs1-corr-upd",
                "abs1-pres-upd",
            ]:
                model.fns[sym] = FnInfo(sym, "defun", 1, 1, ":logic", True)
            return f"""(progn
  (defstobj abs1$c (abs1-v$c :type integer :initially {k}))
  (defun abs1$ap (x) (declare (xargs :guard t)) (integerp x))
  (defun create-abs1$a () (declare (xargs :guard t)) {k})
  (defun abs1-v$a (x) (declare (xargs :guard (abs1$ap x))) (ifix x))
  (defun update-abs1-v$a (v x) (declare (ignore x) (xargs :guard (and (integerp v) (abs1$ap x)))) (ifix v))
  (defun-nx abs1-corr (c a) (and (abs1$cp c) (integerp a) (equal (nth 0 c) a)))
  (defthm abs1-corr-create (abs1-corr (create-abs1$c) (create-abs1$a)))
  (defthm abs1-corr-v (implies (and (abs1-corr c a) (abs1$ap a)) (equal (abs1-v$c c) (abs1-v$a a))))
  (defthm abs1-corr-upd (implies (and (abs1-corr c a) (integerp v) (abs1$ap a)) (abs1-corr (update-abs1-v$c v c) (update-abs1-v$a v a))))
  (defthm abs1-pres-upd (implies (and (integerp v) (abs1$ap a)) (abs1$ap (update-abs1-v$a v a))))
  (defabsstobj abs1
    :foundation abs1$c
    :recognizer (abs1p :logic abs1$ap :exec abs1$cp)
    :creator (create-abs1 :logic create-abs1$a :exec create-abs1$c)
    :corr-fn abs1-corr
    :exports ((abs1-v :logic abs1-v$a :exec abs1-v$c :correspondence abs1-corr-v)
              (update-abs1-v :logic update-abs1-v$a :exec update-abs1-v$c
                             :correspondence abs1-corr-upd :preserved abs1-pres-upd))))"""

        if op == "mutate_scalar_stobj":
            st = self.rng.choice(live_scalars)
            return (
                f"(make-event\n"
                f"  (mv-let (erp val state)\n"
                f"    (trans-eval '({st.updater} {k} {st.name}) 'wrb-mut state t)\n"
                f"    (declare (ignore erp val))\n"
                f"    (value '(value-triple :mutated-{st.name}))))"
            )

        if op == "mutate_resize_stobj":
            st = self.rng.choice(live_arrays)
            new_len = self.rng.choice([2, 6, 9])
            return (
                f"(make-event\n"
                f"  (mv-let (erp val state)\n"
                f"    (trans-eval '(let (({st.name} (resize-{st.accessor} {new_len} {st.name})))\n"
                f"                   ({st.updater} 0 {k} {st.name})) 'wrb-rsz state t)\n"
                f"    (declare (ignore erp val))\n"
                f"    (value '(value-triple :resized-{st.name}))))"
            )

        if op == "swap_congruent_stobjs":
            st_a, st_b = self.rng.choice(cong_pairs)
            return (
                f"(make-event\n"
                f"  (mv-let (erp val state)\n"
                f"    (trans-eval '(let (({st_a.name} ({st_a.updater} {k} {st_a.name})))\n"
                f"                   (swap-stobjs {st_a.name} {st_b.name})) 'wrb-swp state t)\n"
                f"    (declare (ignore erp val))\n"
                f"    (value '(value-triple :swapped))))"
            )

        if op == "nested_swap_stobj_trigger":
            child = model.stobjs[model.stobjs["nest1"].child_stobj]
            cong = [s for s in model.stobjs.values() if s.congruent_to == child.name][0]
            tmp_st = f"tmp-rb-st-{uid}"
            model.stobjs[tmp_st] = StobjInfo(tmp_st, "scalar", f"{tmp_st}p", f"{tmp_st}-f", f"update-{tmp_st}-f")
            return (
                f"(progn\n"
                f"  (defstobj {tmp_st} ({tmp_st}-f :type integer :initially 0))\n"
                f"  (make-event\n"
                f"    (mv-let (erp val state)\n"
                f"      (trans-eval '(stobj-let (({cong.name} (nest1-c1 nest1))) ({cong.name} {child.name})\n"
                f"                     (swap-stobjs {cong.name} {child.name}) (mv nest1 {child.name})) 'wrb-nswp state t)\n"
                f"      (declare (ignore erp val))\n"
                f"      (value '(value-triple :nested-swapped)))))"
            )

        if op == "populate_stobj_table":
            st = self.rng.choice(live_scalars)
            put_fn = f"put-{st.name}-into-tbl1-{uid}"
            model.fns[put_fn] = FnInfo(put_fn, "defun", 1, 1, ":logic", True, stobj_arg="tbl1")
            prime = ""
            if "read-tbl1-keys" in model.fns and not in_book:
                prime = (
                    f"\n  (make-event (mv-let (erp val state)"
                    f" (trans-eval '(let ((tbl1 ({put_fn} tbl1))) (mv (read-tbl1-keys tbl1) tbl1)) 'wrb-tbl state t)"
                    f" (declare (ignore erp val)) (value '(value-triple :tbl-primed))))"
                )
            return (
                f"(progn\n"
                f"  (defun {put_fn} (tbl1)\n"
                f"    (declare (xargs :stobjs tbl1 :guard t))\n"
                f"    (stobj-let (({st.name} (tbl1-get '{st.name} tbl1 (create-{st.name})))) ({st.name})\n"
                f"      ({st.updater} {k} {st.name})\n"
                f"      tbl1)){prime})"
            )

        if op == "remove_global_stobj":
            st = self.rng.choice([s for s in model.stobjs.values() if s.global_live and not s.non_executable])
            st.global_live = False
            return f"(make-event (er-progn (remove-global-stobj '{st.name} state) (value '(value-triple :rm-{st.name}))))"

        if op == "add_global_stobj":
            st = self.rng.choice([s for s in model.stobjs.values() if not s.global_live and not s.non_executable])
            st.global_live = True
            return f"(make-event (er-progn (add-global-stobj '{st.name} state) (value '(value-triple :add-{st.name}))))"

        if op == "define_stub_ds1":
            impl = f"ds1-impl-{uid}"
            model.has_stub_ds1 = True
            model.ds1_attached = impl
            model.ds1_caller_memo = True
            model.fns["ds1"] = FnInfo("ds1", "defun", 1, 1, ":logic", True)
            model.fns["call-ds1"] = FnInfo("call-ds1", "defun", 1, 1, ":logic", True, memoized=True)
            model.fns[impl] = FnInfo(impl, "defun", 1, 1, ":logic", True)
            warm = "\n  (value-triple (call-ds1 10))" if not in_book else ""
            return (
                f"(progn\n"
                f"  (encapsulate (((ds1 *) => * :formals (x) :guard t))\n"
                f"    (local (defun ds1 (x) (declare (ignore x) (xargs :guard t)) 0)))\n"
                f"  (defun call-ds1 (x) (declare (xargs :guard t)) (ds1 x))\n"
                f"  (memoize 'call-ds1 :aokp t)\n"
                f"  (defun {impl} (x) (declare (xargs :guard t)) (+ (nfix x) {k}))\n"
                f"  (defattach ds1 {impl}){warm})"
            )

        if op == "reattach_ds1":
            impl = f"ds1-impl-{uid}"
            model.ds1_attached = impl
            model.fns[impl] = FnInfo(impl, "defun", 1, 1, ":logic", True)
            warm = "\n  (value-triple (call-ds1 10))" if not in_book else ""
            return (
                f"(progn\n"
                f"  (defun {impl} (x) (declare (xargs :guard t)) (* (nfix x) {k}))\n"
                f"  (defattach ds1 {impl}){warm})"
            )

        if op == "table_defaults":
            val = self.rng.choice(["t", "nil"])
            return f"(table acl2-defaults-table :irrelevant-formals-ok {val})"

        if op == "custom_keyword_hint":
            hfn = f"wrb-kh-{uid}"
            model.fns[hfn] = FnInfo(hfn, "defun", 4, 1, ":program", False)
            model.hint_installed = True
            return (
                f"(progn\n"
                f"  (defun {hfn} (val event-form-p clause world)\n"
                f"    (declare (xargs :mode :program) (ignore val event-form-p clause world))\n"
                f"    (value nil))\n"
                f"  (add-custom-keyword-hint :wrb-hint {hfn}))"
            )

        if op == "defpkg_wrb":
            model.pkgs.add("WRB-PKG1")
            return '(defpkg "WRB-PKG1" \'(nil t cons car cdr +))'

        return None

    def gen_probes(self, base_model: WorldModel) -> List[str]:
        """Generate observational probes P valid in S_base, reusing rolled-back names!"""
        probes: List[str] = []
        used = base_model.used_names()

        # 1. Probe surviving baseline functions & attachments & memoized callers
        for fn in sorted(base_model.fns.values(), key=lambda x: x.name):
            if fn.name in ("f1", "f2", "f3", "m1", "call-ds1") and fn.stobj_arg is None:
                if fn.kind == "defmacro":
                    probes.append(emit_probe_expr(f"base-mac-{fn.name}", f"({fn.name} 11)"))
                elif fn.mode == ":logic" and fn.guard_verified and fn.kind == "defun":
                    args = " ".join(str(i + 5) for i in range(fn.arity))
                    probes.append(emit_probe_expr(f"base-fn-{fn.name}", f"({fn.name} {args})"))
                    if fn.warranted and base_model.include_apply_top:
                        probes.append(emit_probe_expr(f"base-apply-{fn.name}", f"(apply$ '{fn.name} '(7))"))
                        probes.append(emit_probe_expr(f"base-lam-{fn.name}", f"(apply$ '(lambda$ (z) ({fn.name} z)) '(7))"))

        # 2. Reuse free function names (colliding with names that H defined and rolled back!)
        for fn in FN_POOL:
            if fn not in used:
                # Re-define with guard-verified mbe + multi-arg or local-stobj check
                arity = self.rng.choice([1, 2])
                if arity == 1:
                    redef = (
                        f"(defun {fn} (x)\n"
                        f"  (declare (xargs :guard (integerp x) :verify-guards t))\n"
                        f"  (mbe :logic (+ (ifix x) 100) :exec (the integer (+ x 100))))"
                    )
                    probes.append(emit_probe_event(f"redef-{fn}", redef))
                    probes.append(emit_probe_expr(f"eval-{fn}", f"({fn} 23)"))
                    if base_model.include_apply_top:
                        probes.append(emit_probe_expr(f"unwarranted-apply-{fn}", f"(apply$ '(lambda$ (z) ({fn} z)) '(23))"))
                        probes.append(emit_probe_event(f"badge-warrant-{fn}", f"(progn (defbadge {fn}) (defwarrant {fn}))"))
                        probes.append(emit_probe_expr(f"warranted-apply-{fn}", f"(apply$ '{fn} '(23))"))
                else:
                    redef = (
                        f"(defun {fn} (x y)\n"
                        f"  (declare (xargs :guard (and (integerp x) (integerp y)) :verify-guards t))\n"
                        f"  (- (ifix x) (ifix y)))"
                    )
                    probes.append(emit_probe_event(f"redef2-{fn}", redef))
                    probes.append(emit_probe_expr(f"eval2-{fn}", f"({fn} 50 8)"))

        # 3. Probe surviving baseline stobjs (values, array lengths, nested C1 aliasing, stobj-table!)
        for st_name in sorted(base_model.stobjs.keys()):
            st = base_model.stobjs[st_name]
            if not st.global_live or st.non_executable:
                continue
            if st.variant in ("scalar", "congruent"):
                probes.append(emit_probe_expr(f"st-read-{st.name}", f"({st.accessor} {st.name})"))
                probes.append(
                    emit_probe_expr(
                        f"st-upd-{st.name}",
                        f"(let (({st.name} ({st.updater} 777 {st.name}))) (mv ({st.accessor} {st.name}) {st.name}))",
                    )
                )
            elif st.variant == "array":
                probes.append(
                    emit_probe_expr(
                        f"st-arr-{st.name}",
                        f"(list ({st.accessor}-length {st.name}) ({st.accessor}i 0 {st.name}))",
                    )
                )
            elif st.variant == "abs":
                probes.append(
                    emit_probe_expr(
                        f"abs-rw-{st.name}",
                        f"(let (({st.name} ({st.updater} 321 {st.name}))) (mv ({st.accessor} {st.name}) {st.name}))",
                    )
                )
            elif st.variant == "nested" and st.child_stobj in base_model.stobjs:
                probes.append(
                    emit_probe_expr(
                        "nest-c1-disjoint",
                        "(chk-nest1-disjoint nest1)",
                    )
                )
            elif st.variant == "table":
                probes.append(emit_probe_expr("tbl1-keys", "(tbl1-keys tbl1)"))
                probes.append(emit_probe_expr("tbl1-count", "(tbl1-count tbl1)"))
                if "read-tbl1-keys" in base_model.fns:
                    probes.append(emit_probe_expr("tbl1-memo-keys", "(read-tbl1-keys tbl1)"))
                if self.allow_found_triggers:
                    probes.append(emit_probe_expr("tbl1-boundp-st1", "(tbl1-boundp 'st1 tbl1)"))

        # 4. Reuse free stobj names (including nesting a fresh mom over rolled-back st1 -> tests WRB-S3!)
        for name, rec, acc, upd in STOBJ_POOL:
            if name not in base_model.used_names():
                variant = self.rng.choice(["scalar_and_mom", "array"])
                if variant == "scalar_and_mom":
                    probes.append(
                        emit_probe_event(
                            f"redef-st-{name}",
                            f"(defstobj {name} ({acc} :type integer :initially 5))",
                        )
                    )
                    probes.append(emit_probe_expr(f"fresh-st-{name}", f"({acc} {name})"))
                    mom_name = f"mom-{name}"
                    if mom_name not in base_model.used_names():
                        probes.append(
                            emit_probe_event(
                                f"def-{mom_name}",
                                f"(progn\n"
                                f"  (defstobj {mom_name} (k-{name} :type {name}))\n"
                                f"  (defun read-{mom_name}-fresh ()\n"
                                f"    (declare (xargs :guard t))\n"
                                f"    (with-local-stobj {mom_name}\n"
                                f"      (mv-let (v {mom_name})\n"
                                f"        (stobj-let ((c (k-{name} {mom_name}))) (v) ({acc} c) (mv v {mom_name}))\n"
                                f"        v))))",
                            )
                        )
                        probes.append(
                            emit_probe_expr(
                                f"local-{mom_name}",
                                f"(read-{mom_name}-fresh)",
                            )
                        )
                else:
                    probes.append(
                        emit_probe_event(
                            f"redef-arr-{name}",
                            f"(defstobj {name} ({acc} :type (array integer (3)) :initially 9 :resizable t))",
                        )
                    )
                    probes.append(
                        emit_probe_expr(
                            f"fresh-arr-{name}",
                            f"(list ({acc}-length {name}) ({acc}i 0 {name}))",
                        )
                    )

        # 5. Table & world-metadata consistency check
        probes.append(
            emit_probe_expr(
                "defaults-irrel",
                "(cdr (assoc-eq :irrelevant-formals-ok (table-alist 'acl2-defaults-table (w state))))",
            )
        )
        return probes

    def build_scenario(self, seed: int, rollback_op: Optional[str] = None) -> Dict[str, object]:
        self.rng = random.Random(seed)
        op = rollback_op or self.rng.choice(ROLLBACK_OPS)

        base_model = WorldModel()
        use_apply = self.rng.random() < 0.30
        base_model.include_apply_top = use_apply

        # certify-reset requires portcullis-legal baseline (or empty baseline)
        n_base = 0 if op == "certify-reset" else self.rng.randint(0, 3)
        base_events: List[str] = []
        if use_apply and op != "certify-reset":
            base_events.append('(include-book "projects/apply/top" :dir :system)')
        else:
            base_model.include_apply_top = False

        for _ in range(n_base):
            ev = self.gen_step(base_model, in_local_encap=False, in_book=False, is_baseline=True)
            if ev:
                base_events.append(ev)

        hist_model = base_model.clone()
        n_hist = self.rng.randint(2, 6)
        hist_events: List[str] = []
        in_local = op == "encap-local"
        in_book = op in ("certify-reset", "include-fail")
        for _ in range(n_hist):
            ev = self.gen_step(hist_model, in_local_encap=in_local, in_book=in_book, is_baseline=False)
            if ev:
                hist_events.append(ev)
        if not hist_events:
            hist_events.append("(defun f1 (x) (declare (xargs :guard t)) (+ (nfix x) 1))")

        probes = self.gen_probes(base_model)
        return {
            "seed": seed,
            "rollback_op": op,
            "base_events": base_events,
            "hist_events": hist_events,
            "probes": probes,
        }


def render_scripts(scenario: Dict[str, object], workdir: Path) -> Tuple[Path, Path, Optional[Path]]:
    seed = scenario["seed"]
    op = scenario["rollback_op"]
    base_events: List[str] = scenario["base_events"]  # type: ignore
    hist_events: List[str] = scenario["hist_events"]  # type: ignore
    probes: List[str] = scenario["probes"]  # type: ignore

    control_lines = ['(in-package "ACL2")']
    if op == "include-fail":
        control_lines.append("(defun wrb-conflict-anchor () 2)")
    control_lines.extend(base_events)
    control_lines.append('(cw "@PHASE-PROBES-START~%")')
    control_lines.extend(probes)
    control_lines.append('(cw "@PHASE-PROBES-END~%")')
    control_lines.append("(quit)")

    rollback_lines = ['(in-package "ACL2")']
    helper_book_path: Optional[Path] = None

    if op == "include-fail":
        rollback_lines.append("(defun wrb-conflict-anchor () 2)")

    rollback_lines.extend(base_events)

    if op == "ubt":
        rollback_lines.append("(deflabel wrb-rb-mark)")
        rollback_lines.extend(hist_events)
        rollback_lines.append(":ubt! wrb-rb-mark")
    elif op == "encap-local":
        inner = "\n  ".join(f"(local {ev})" for ev in hist_events)
        rollback_lines.append(f"(encapsulate ()\n  {inner}\n  (defun wrb-noop-export () nil))")
        # Also include wrb-noop-export in control so logical worlds match identically!
        idx = control_lines.index('(cw "@PHASE-PROBES-START~%")')
        control_lines.insert(idx, "(defun wrb-noop-export () nil)")
    elif op == "encap-fail":
        inner = "\n      ".join(hist_events)
        rollback_lines.append(
            f"(mv-let (erp val state)\n"
            f"  (ld '((encapsulate ()\n"
            f"          {inner}\n"
            f"          (make-event (er soft 'wrb-abort \"intentional mid-encapsulate rollback\"))))\n"
            f"      :ld-error-action :return! :ld-verbose nil :ld-prompt nil)\n"
            f"  (declare (ignore erp val))\n"
            f"  state)"
        )
    elif op == "progn-fail":
        inner = "\n          ".join(hist_events)
        rollback_lines.append(
            f"(mv-let (erp val state)\n"
            f"  (ld '((progn\n"
            f"          {inner}\n"
            f"          (make-event (er soft 'wrb-abort \"intentional mid-progn rollback\"))))\n"
            f"      :ld-error-action :return! :ld-verbose nil :ld-prompt nil)\n"
            f"  (declare (ignore erp val))\n"
            f"  state)"
        )
    elif op == "ld-fail":
        inner = "\n          ".join(hist_events)
        rollback_lines.append(
            f"(mv-let (erp val state)\n"
            f"  (ld '((ld '({inner}\n"
            f"              (make-event (er soft 'wrb-abort \"intentional ld rollback\")))\n"
            f"            :ld-error-action :error :ld-verbose nil :ld-prompt nil))\n"
            f"      :ld-error-action :return! :ld-verbose nil :ld-prompt nil)\n"
            f"  (declare (ignore erp val))\n"
            f"  state)"
        )
    elif op == "certify-reset":
        book_name = f"wrb_cert_s{seed}"
        helper_book_path = workdir / f"{book_name}.lisp"
        helper_book_path.write_text(
            '(in-package "ACL2")\n' + "\n".join(hist_events) + "\n",
            encoding="utf-8",
        )
        rollback_lines.append(f'(certify-book "{book_name}" 0 t)')
        rollback_lines.append(":u")
    elif op == "include-fail":
        book_name = f"wrb_ib_s{seed}"
        helper_book_path = workdir / f"{book_name}.lisp"
        # Note: helper book defines H first, then conflicting wrb-conflict-anchor
        helper_book_path.write_text(
            '(in-package "ACL2")\n'
            + "\n".join(hist_events)
            + "\n(defun wrb-conflict-anchor () 1)\n",
            encoding="utf-8",
        )
        rollback_lines.append(
            f"(mv-let (erp val state)\n"
            f'  (ld \'((include-book "{book_name}"))\n'
            f"      :ld-error-action :return! :ld-verbose nil :ld-prompt nil)\n"
            f"  (declare (ignore erp val))\n"
            f"  state)"
        )

    rollback_lines.append('(cw "@PHASE-PROBES-START~%")')
    rollback_lines.extend(probes)
    rollback_lines.append('(cw "@PHASE-PROBES-END~%")')
    rollback_lines.append("(quit)")

    control_path = workdir / f"s{seed}_control.lisp"
    rollback_path = workdir / f"s{seed}_rollback.lisp"
    control_path.write_text("\n\n".join(control_lines) + "\n", encoding="utf-8")
    rollback_path.write_text("\n\n".join(rollback_lines) + "\n", encoding="utf-8")
    return control_path, rollback_path, helper_book_path


RAW_CRASH_RE = re.compile(
    r"(RAW LISP ERROR|HARD ACL2 ERROR|debugger invoked on|Error: Attempted to access|"
    r"The assertion .* failed|TYPE-ERROR|MEMORY-FAULT-ERROR|Segmentation fault)",
    re.IGNORECASE,
)


def run_acl2(binary: str, script_path: Path, cwd: Path) -> Tuple[int, str]:
    with script_path.open("rb") as fin:
        proc = subprocess.run(
            [TIMEOUT_BIN, "--kill-after=10s", "120s", binary],
            stdin=fin,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=str(cwd),
            check=False,
        )
    return proc.returncode, proc.stdout.decode("utf-8", errors="replace")


def parse_probe_output(rc: int, out: str) -> Dict[str, object]:
    in_probes = False
    completed = False
    probes: List[str] = []
    probe_crashes: List[str] = []

    for line in out.splitlines():
        if "@PHASE-PROBES-START" in line:
            in_probes = True
            idx = line.find("@PHASE-PROBES-START")
            rest = line[idx + len("@PHASE-PROBES-START"):].strip()
            if rest.startswith("@PROBE "):
                probes.append(rest)
            continue
        if "@PHASE-PROBES-END" in line:
            completed = True
            in_probes = False
            continue
        if "@PROBE " in line and in_probes:
            idx = line.find("@PROBE ")
            probes.append(line[idx:].strip())
        if in_probes and RAW_CRASH_RE.search(line):
            probe_crashes.append(line.strip())

    # Also detect raw crashes during rollback itself (before @PHASE-PROBES-START)!
    pre_probe_part = out.split("@PHASE-PROBES-START")[0]
    rollback_crashes = [
        ln.strip() for ln in pre_probe_part.splitlines() if RAW_CRASH_RE.search(ln)
    ]

    return {
        "rc": rc,
        "completed": completed,
        "probes": probes,
        "probe_crashes": probe_crashes,
        "rollback_crashes": rollback_crashes,
    }


def run_one_seed(
    seed: int,
    allow_found_triggers: bool,
    hosts: List[Tuple[str, str]],
    keep_dir: Optional[Path],
) -> Dict[str, object]:
    gen = ScenarioGenerator(random.Random(seed), allow_found_triggers=allow_found_triggers)
    scenario = gen.build_scenario(seed)
    tmp_ctx = tempfile.TemporaryDirectory(prefix=f"wrb_s{seed}_")
    workdir = Path(tmp_ctx.name)
    try:
        control_path, rollback_path, helper_book = render_scripts(scenario, workdir)
        divergences = []
        host_summaries = {}

        for host_name, binary in hosts:
            # Clean any cert/compiled artifacts before running each host
            for ext in (".cert", ".port", ".fasl", ".da64fsl", ".lx64fsl"):
                for p in workdir.glob(f"*{ext}"):
                    p.unlink(missing_ok=True)

            # If include-fail, pre-certify helper book on this host; if helper fails to certify
            # (e.g., invalid random H combo), skip include-fail for this seed cleanly.
            if scenario["rollback_op"] == "include-fail" and helper_book is not None:
                cert_driver = workdir / f"cert_{host_name}.lisp"
                cert_driver.write_text(
                    f'(in-package "ACL2")\n(certify-book "{helper_book.stem}" 0 t)\n(quit)\n',
                    encoding="utf-8",
                )
                rc_c, _ = run_acl2(binary, cert_driver, workdir)
                if rc_c != 0 or not (workdir / f"{helper_book.stem}.cert").exists():
                    host_summaries[host_name] = {"skipped_uncertifiable_helper": True}
                    continue

            rc_ctrl, out_ctrl = run_acl2(binary, control_path, workdir)
            # Clean cert artifacts produced if any before rollback run (except include-fail helper!)
            if scenario["rollback_op"] == "certify-reset" and helper_book is not None:
                for ext in (".cert", ".port", ".fasl", ".da64fsl", ".lx64fsl"):
                    (workdir / f"{helper_book.stem}{ext}").unlink(missing_ok=True)

            rc_rb, out_rb = run_acl2(binary, rollback_path, workdir)

            p_ctrl = parse_probe_output(rc_ctrl, out_ctrl)
            p_rb = parse_probe_output(rc_rb, out_rb)

            # If certify-reset helper book failed to certify because random H had an uncertifiable
            # event (e.g. unprovedverify-guards), rollback didn't reach post-certify-book reset; skip cleanly.
            if (
                scenario["rollback_op"] == "certify-reset"
                and helper_book is not None
                and not (workdir / f"{helper_book.stem}.cert").exists()
                and not p_rb["rollback_crashes"]
            ):
                host_summaries[host_name] = {"skipped_uncertifiable_helper": True}
                continue

            host_summaries[host_name] = {
                "ctrl_completed": p_ctrl["completed"],
                "rb_completed": p_rb["completed"],
                "probe_count": len(p_ctrl["probes"]),
            }

            if (
                p_ctrl["probes"] != p_rb["probes"]
                or p_ctrl["completed"] != p_rb["completed"]
                or bool(p_ctrl["probe_crashes"]) != bool(p_rb["probe_crashes"])
                or bool(p_rb["rollback_crashes"])
            ):
                divergences.append({
                    "host": host_name,
                    "ctrl": p_ctrl,
                    "rb": p_rb,
                    "out_ctrl_tail": "\n".join(out_ctrl.splitlines()[-35:]),
                    "out_rb_tail": "\n".join(out_rb.splitlines()[-35:]),
                })

        if divergences and keep_dir is not None:
            dest = keep_dir / f"divergence_seed_{seed}_{scenario['rollback_op']}"
            if dest.exists():
                shutil.rmtree(dest)
            shutil.copytree(workdir, dest)
            # Remove compiled/cert binaries from saved folder
            for ext in (".cert", ".port", ".fasl", ".da64fsl", ".lx64fsl"):
                for p in dest.glob(f"*{ext}"):
                    p.unlink(missing_ok=True)

        return {
            "seed": seed,
            "rollback_op": scenario["rollback_op"],
            "hosts": host_summaries,
            "divergences": divergences,
        }
    finally:
        tmp_ctx.cleanup()


def build_regression_cases(workdir: Path) -> List[Tuple[str, Path, Path, Optional[Path]]]:
    """
    Deterministic regression suite verifying the observational-rollback-equivalence
    oracle flags WRB-S1, WRB-S2, WRB-S3, WRB-S4, WRB-R1, WRB-R2, and WRB-R3.
    Returns list of (case_name, control_lisp, rollback_lisp, optional_helper_book).
    """
    cases = []

    def add_case(name: str, ctrl: str, rb: str, helper: Optional[Tuple[str, str]] = None):
        cdir = workdir / name
        cdir.mkdir(parents=True, exist_ok=True)
        cpath = cdir / "control.lisp"
        rpath = cdir / "rollback.lisp"
        cpath.write_text(ctrl, encoding="utf-8")
        rpath.write_text(rb, encoding="utf-8")
        hpath = None
        if helper is not None:
            hpath = cdir / helper[0]
            hpath.write_text(helper[1], encoding="utf-8")
        cases.append((name, cpath, rpath, hpath))

    # 1. WRB-S1: Nested stobj C1 aliasing across :ubt!
    base_s1 = """(in-package "ACL2")
(defstobj kid  (kfld  :type integer :initially 0))
(defstobj kid2 (kfld2 :type integer :initially 0) :congruent-to kid)
(defstobj parent (k1 :type kid) (k2 :type kid))
(defun swap-k1 (parent kid) (declare (xargs :stobjs (parent kid)))
  (stobj-let ((kid2 (k1 parent))) (kid2 kid) (swap-stobjs kid2 kid) (mv parent kid)))
(defun swap-k2 (parent kid) (declare (xargs :stobjs (parent kid)))
  (stobj-let ((kid2 (k2 parent))) (kid2 kid) (swap-stobjs kid2 kid) (mv parent kid)))
(defun chk-disjoint (parent) (declare (xargs :stobjs parent))
  (let* ((parent (stobj-let ((kid (k1 parent))) (kid) (update-kfld 111 kid) parent))
         (parent (stobj-let ((kid (k2 parent))) (kid) (update-kfld 222 kid) parent)))
    (stobj-let ((kid (k1 parent))) (v) (kfld kid) (mv v parent))))
"""
    probe_s1 = """(cw "@PHASE-PROBES-START~%")
(mv-let (erp val state)
  (trans-eval '(chk-disjoint parent) 'probe state t)
  (prog2$ (cw "@PROBE s1-c1-disjoint erp=~x0 val=~x1~%" erp val) state))
(cw "@PHASE-PROBES-END~%")
(quit)
"""
    rb_s1 = base_s1 + """(deflabel rb-mark)
(defstobj tmp dummy)
(swap-k1 parent kid)
:ubt! rb-mark
(swap-k2 parent kid)
""" + probe_s1
    ctrl_s1 = base_s1 + "(swap-k2 parent kid)\n" + probe_s1
    add_case("WRB-S1-nested-stobj-alias", ctrl_s1, rb_s1)

    # 2. WRB-S2: stobj-table retraction fails to call memoize-flush
    base_s2 = """(in-package "ACL2")
(defstobj parent (tbl :type (stobj-table)))
(defun m-keys (parent) (declare (xargs :stobjs parent)) (tbl-keys parent))
(memoize 'm-keys)
"""
    probe_s2 = """(cw "@PHASE-PROBES-START~%")
(mv-let (erp val state)
  (trans-eval '(list (m-keys parent) (tbl-keys parent)) 'probe state t)
  (prog2$ (cw "@PROBE s2-memo-vs-actual erp=~x0 val=~x1~%" erp val) state))
(cw "@PHASE-PROBES-END~%")
(quit)
"""
    rb_s2 = base_s2 + """(encapsulate ()
  (local (defstobj kid (kfld :type integer :initially 0)))
  (local (defun put-k (parent) (declare (xargs :stobjs parent))
           (stobj-let ((kid (tbl-get 'kid parent (create-kid)))) (kid) (update-kfld 9 kid) parent)))
  (local (make-event (mv-let (erp val state)
                       (trans-eval '(let ((parent (put-k parent))) (mv (m-keys parent) parent)) 'h state t)
                       (declare (ignore erp val)) (value '(value-triple :ok))))))
""" + probe_s2
    add_case("WRB-S2-stobj-table-memoize", base_s2 + probe_s2, rb_s2)

    # 3. WRB-S3: failed include-book poisons redundant-raw-lisp-discriminator (:creator)
    helper_s3 = (
        "bad_kid_reg.lisp",
        '(in-package "ACL2")\n'
        "(defstobj kid (bad-fld :type integer :initially 0) :renaming ((create-kid create-bogus-reg)))\n",
    )
    base_s3 = """(in-package "ACL2")
(defstobj bogus-reg (bfld :type integer :initially 99))
(defstobj kid (kfld :type integer :initially 0))
(make-event (er-progn (remove-global-stobj 'kid state) (value '(value-triple :rm))))
"""
    probe_s3 = """(make-event (er-progn (add-global-stobj 'kid state) (value '(value-triple :add))))
(defstobj mom (k :type kid))
(defun read-mom-k (mom) (declare (xargs :stobjs mom))
  (stobj-let ((kid (k mom))) (v) (kfld kid) v))
(defun read-fresh-mom () (declare (xargs :guard t))
  (with-local-stobj mom (mv-let (v mom) (mv (read-mom-k mom) mom) v)))
(cw "@PHASE-PROBES-START~%")
(mv-let (erp val state)
  (trans-eval '(read-fresh-mom) 'probe state t)
  (prog2$ (cw "@PROBE s3-fresh-mom-kid erp=~x0 val=~x1~%" erp val) state))
(cw "@PHASE-PROBES-END~%")
(quit)
"""
    rb_s3 = base_s3 + """(make-event
  (mv-let (erp val state) (include-book "bad_kid_reg")
    (declare (ignore erp val)) (value '(value-triple :failed-ib))))
""" + probe_s3
    add_case("WRB-S3-failed-include-creator", base_s3 + probe_s3, rb_s3, helper=helper_s3)

    # 4. WRB-S4: rolled-back (local (include-book ...)) resets (st-lst 'st) via raw defg
    helper_s4 = (
        "st_lst_reg.lisp",
        '(in-package "ACL2")\n(defstobj st (fld :type integer :initially 0))\n',
    )
    base_s4 = """(in-package "ACL2")
(defstobj st (fld :type integer :initially 0))
(defun read-st (st) (declare (xargs :stobjs st)) (fld st))
(memoize 'read-st)
"""
    probe_s4 = """(cw "@PHASE-PROBES-START~%")
(mv-let (erp val state)
  (trans-eval '(let* ((st (update-fld 0 st))
                      (v0 (read-st st))
                      (st (update-fld 42 st))
                      (v1 (read-st st))
                      (actual (fld st)))
                 (mv (list v0 v1 actual) st))
              'probe state t)
  (prog2$ (cw "@PROBE s4-st-lst-flush erp=~x0 val=~x1~%" erp val) state))
(cw "@PHASE-PROBES-END~%")
(quit)
"""
    rb_s4 = base_s4 + '(encapsulate () (local (include-book "st_lst_reg")))\n' + probe_s4
    add_case("WRB-S4-st-lst-defg-wipe", base_s4 + probe_s4, rb_s4, helper=helper_s4)

    # 5. WRB-R1: stobj-table tbl-boundp raw Lisp crash on rolled-back stobj key
    base_r1 = """(in-package "ACL2")
(defstobj parent (tbl :type (stobj-table)))
(defun chk-k (k parent) (declare (xargs :stobjs parent :guard t)) (tbl-boundp k parent))
"""
    probe_r1 = """(cw "@PHASE-PROBES-START~%")
(mv-let (erp val state)
  (trans-eval '(chk-k 'kid parent) 'probe state t)
  (prog2$ (cw "@PROBE r1-boundp erp=~x0 val=~x1~%" erp val) state))
(cw "@PHASE-PROBES-END~%")
(quit)
"""
    rb_r1 = base_r1 + "(encapsulate () (local (defstobj kid (kfld :type integer :initially 0))))\n" + probe_r1
    add_case("WRB-R1-stobj-table-guard-crash", base_r1 + '(cw "@PHASE-PROBES-START~%")\n(cw "@PROBE r1-boundp erp=NIL val=(NIL)~%")\n(cw "@PHASE-PROBES-END~%")\n(quit)\n', rb_r1)

    # 6. WRB-R2: *non-executable-user-stobj-lst* desync across stobj undo
    base_r2 = """(in-package "ACL2")
(defstobj st (fld :type integer :initially 42))
(make-event (er-progn (remove-global-stobj 'st state) (value '(value-triple :rm))))
"""
    probe_r2 = """(cw "@PHASE-PROBES-START~%")
(mv-let (erp val state)
  (add-global-stobj 'st state)
  (declare (ignore val))
  (prog2$ (cw "@PROBE r2-add-global erp=~x0~%" erp) state))
(cw "@PHASE-PROBES-END~%")
(quit)
"""
    rb_r2 = base_r2 + """(encapsulate ()
  (local (defstobj tmp dummy))
  (local (make-event (er-progn (add-global-stobj 'st state) (value '(value-triple :readd))))))
""" + probe_r2
    add_case("WRB-R2-nonexec-stobj-lst-desync", base_r2 + probe_r2, rb_r2)

    # 7. WRB-R3: redef! + :u wipes *current-stobj-gensym-ht* for surviving stobj
    base_r3 = """(in-package "ACL2")
(defstobj kid (kfld :type integer :initially 0))
(defstobj parent (tbl :type (stobj-table)))
(defun put-k (v parent) (declare (xargs :stobjs parent :guard (integerp v)))
  (stobj-let ((kid (tbl-get 'kid parent (create-kid)))) (kid) (update-kfld v kid) parent))
(make-event (mv-let (erp val state) (trans-eval '(put-k 99 parent) 'b state t)
              (declare (ignore erp val)) (value '(value-triple :ok))))
"""
    probe_r3 = """(cw "@PHASE-PROBES-START~%")
(mv-let (erp val state)
  (trans-eval '(list (tbl-keys parent) (tbl-count parent)) 'probe state t)
  (prog2$ (cw "@PROBE r3-live-table erp=~x0 val=~x1~%" erp val) state))
(cw "@PHASE-PROBES-END~%")
(quit)
"""
    rb_r3 = base_r3 + """(redef!)
(deflabel rb-mark)
(defstobj kid (kfld :type integer :initially 5))
:ubt! rb-mark
(redef-)
""" + probe_r3
    add_case("WRB-R3-redef-undo-gensym-wipe", base_r3 + probe_r3, rb_r3)

    return cases


def main() -> int:
    parser = argparse.ArgumentParser(description="ACL2 World-Rollback State-Machine Fuzzer")
    parser.add_argument("--mode", choices=["regression", "fuzz", "both"], default="both")
    parser.add_argument("--seed-start", type=int, default=1000)
    parser.add_argument("--count", type=int, default=180)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--allow-found-triggers", action="store_true")
    parser.add_argument("--out-dir", type=str, default="fuzz_artifacts")
    args = parser.parse_args()

    hosts = [("SBCL", SBCL_ACL2), ("CCL", CCL_ACL2)]
    out_dir = Path(args.out_dir).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.mode in ("regression", "both"):
        print("=== [Phase 1] Running Positive Oracle Validation Suite (7 Found Bugs x 2 Hosts) ===")
        with tempfile.TemporaryDirectory(prefix="wrb_reg_") as reg_tmp:
            cases = build_regression_cases(Path(reg_tmp))
            for name, cpath, rpath, hpath in cases:
                flagged_hosts = []
                for hname, binary in hosts:
                    cdir = cpath.parent
                    for ext in (".cert", ".port", ".fasl", ".da64fsl", ".lx64fsl"):
                        for p in cdir.glob(f"*{ext}"):
                            p.unlink(missing_ok=True)
                    if hpath is not None:
                        cdrv = cdir / f"cert_{hname}.lisp"
                        cdrv.write_text(
                            f'(in-package "ACL2")\n(certify-book "{hpath.stem}" 0 t :ttags nil)\n(quit)\n',
                            encoding="utf-8",
                        )
                        run_acl2(binary, cdrv, cdir)
                    rc_c, out_c = run_acl2(binary, cpath, cdir)
                    rc_r, out_r = run_acl2(binary, rpath, cdir)
                    pc = parse_probe_output(rc_c, out_c)
                    pr = parse_probe_output(rc_r, out_r)
                    diverged = (
                        pc["probes"] != pr["probes"]
                        or pc["completed"] != pr["completed"]
                        or bool(pc["probe_crashes"]) != bool(pr["probe_crashes"])
                        or bool(pr["rollback_crashes"])
                    )
                    if diverged:
                        flagged_hosts.append(hname)
                print(f"  [ORACLE-FLAGGED] {name:34s} -> {', '.join(flagged_hosts)}")
                if len(flagged_hosts) != len(hosts):
                    print(f"ERROR: Oracle missed {name} on at least one host!", file=sys.stderr)
                    return 1

    if args.mode in ("fuzz", "both"):
        seeds = list(range(args.seed_start, args.seed_start + args.count))
        print(
            f"\n=== [Phase 2] Running Random State-Machine Fuzzer "
            f"({len(seeds)} seeds x 2 hosts x 2 worlds = {len(seeds)*4} ACL2 runs, "
            f"allow_found_triggers={args.allow_found_triggers}) ==="
        )
        t0 = time.time()
        op_counts: Dict[str, int] = {}
        total_divergences = 0
        results = []

        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            futs = {
                pool.submit(run_one_seed, s, args.allow_found_triggers, hosts, out_dir): s
                for s in seeds
            }
            done_n = 0
            for fut in concurrent.futures.as_completed(futs):
                res = fut.result()
                results.append(res)
                done_n += 1
                op = res["rollback_op"]
                op_counts[op] = op_counts.get(op, 0) + 1
                if res["divergences"]:
                    total_divergences += 1
                    print(
                        f"  [DIVERGENCE] seed={res['seed']} op={op} "
                        f"hosts={[d['host'] for d in res['divergences']]}"
                    )
                if done_n % 30 == 0 or done_n == len(seeds):
                    elapsed = time.time() - t0
                    print(f"  progress: {done_n}/{len(seeds)} seeds completed in {elapsed:.1f}s (divergences={total_divergences})")

        summary_path = out_dir / "summary.json"
        summary_data = {
            "seed_start": args.seed_start,
            "count": args.count,
            "allow_found_triggers": args.allow_found_triggers,
            "elapsed_sec": round(time.time() - t0, 2),
            "op_counts": op_counts,
            "divergent_seeds": [r for r in sorted(results, key=lambda x: x["seed"]) if r["divergences"]],
        }
        summary_path.write_text(json.dumps(summary_data, indent=2), encoding="utf-8")
        print(f"\nFuzzer summary written to {summary_path} (op_counts={op_counts}, divergences={total_divergences})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
