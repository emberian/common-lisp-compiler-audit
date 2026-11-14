#!/usr/bin/env python3
"""
Mechanical fuzzer for ACL2s (defdata, definec/defunc, property/cgen, ccg).
Runs generated test batches against SBCL 2.6.10 and CCL 1.14 under a shadow
ACL2_SYSTEM_BOOKS directory (/tmp/w3-acl2s-harness/books) without touching head-worktree.
"""

import argparse
import os
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path

SBCL_ACL2 = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2 = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"
SHADOW_BOOKS = "/tmp/w3-acl2s-harness/books"
TIMEOUT_BIN = "/opt/homebrew/bin/timeout"

PREAMBLE = """
(defpkg "FTY" *acl2-exports*)
(ld "std/package.lsp" :dir :system)
(ld "data-structures/portcullis.acl2" :dir :system)
(ld "coi/symbol-fns/portcullis.acl2" :dir :system)
(ld "acl2s/package.lsp" :dir :system)
(include-book "std/util/defredundant" :dir :system :uncertified-okp t)
(include-book "make-event/acl2x-help" :dir :system :uncertified-okp t)
(include-book "acl2s/ccg/ccg" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/defdata/top" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/cgen/top" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/defunc" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/definec" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/properties" :dir :system :ttags :all :uncertified-okp t)
(in-package "ACL2S")
"""


def gen_defdata_cases(rng, count=25):
    cases = []
    prim_types = ["nat", "pos", "int", "rational", "boolean", "symbol", "string", "all"]
    weird_names = ["d", "x", "y", "res", "a", "b", "ans", "val", "key"]
    # Pre-seed interesting adversarial edge cases + random mutations
    fixed = [
        ("dd_rec_d_name", "(defdata d (record (a . nat) (b . pos)))", "dp"),
        ("dd_rec_dup_field", "(defdata dd_dupf (record (a . nat) (a . pos)))", "dd_dupfp"),
        ("dd_rec_d_field", "(defdata dd_df (record (d . nat) (x . pos)))", "dd_dfp"),
        ("dd_enum_d_type", "(defdata d_enum (enum '(a b c)))", "d_enump"),
        ("dd_map_alias", "(defdata dd_ln (listof nat)) (defdata dd_mln (map dd_ln pos))", "dd_mlnp"),
        ("dd_oneof_dup", "(defdata dd_ondup (oneof nat nat))", "dd_ondupp"),
        ("dd_range_eq", "(defdata dd_rngeq (range integer (0 <= _ <= 0)))", "dd_rngeqp"),
        ("dd_range_neg", "(defdata dd_rngneg (range rational (-1 < _ < 0)))", "dd_rngnegp"),
        ("dd_mut_rec_rec", "(defdata (dd_ma (record (x . nat) (nxt . dd_mb))) (dd_mb (oneof nil dd_ma)))", "dd_map"),
        ("dd_mut_self", "(defdata (dd_sa (oneof nil (cons nat dd_sb))) (dd_sb (oneof nil (cons pos dd_sa))))", "dd_sap"),
        ("dd_alias_prim", "(defdata dd_ap nat)", "dd_app"),
    ]
    for cid, form, pred in fixed:
        cases.append((cid, form, f"(thm nil) ; canary after {cid}\n(value-triple :CASE-{cid}-DONE)"))

    for i in range(count):
        tname = f"fzt_{i}"
        kind = rng.choice(["record", "oneof", "listof", "alistof", "map", "range", "enum", "mut"])
        if kind == "record":
            k = rng.randint(1, 4)
            fields = []
            for j in range(k):
                fn = rng.choice(weird_names) if rng.random() < 0.4 else f"fld{j}"
                ft = rng.choice(prim_types)
                fields.append(f"({fn} . {ft})")
            form = f"(defdata {tname} (record {' '.join(fields)}))"
        elif kind == "oneof":
            k = rng.randint(1, 4)
            elems = [rng.choice(prim_types + ["nil", "'foo", "0", "-1"]) for _ in range(k)]
            form = f"(defdata {tname} (oneof {' '.join(elems)}))"
        elif kind == "listof":
            form = f"(defdata {tname} (listof {rng.choice(prim_types)}))"
        elif kind == "alistof":
            form = f"(defdata {tname} (alistof {rng.choice(prim_types)} {rng.choice(prim_types)}))"
        elif kind == "map":
            form = f"(defdata {tname} (map {rng.choice(prim_types)} {rng.choice(prim_types)}))"
        elif kind == "range":
            dom = rng.choice(["integer", "rational"])
            lo = rng.randint(-5, 5)
            hi = rng.randint(-5, 5)
            op1 = rng.choice(["<", "<="])
            op2 = rng.choice(["<", "<="])
            form = f"(defdata {tname} (range {dom} ({lo} {op1} _ {op2} {hi})))"
        elif kind == "enum":
            elems = rng.sample(["'a", "'b", "0", "1", "nil", "t", "\"s\""], rng.randint(1, 4))
            form = f"(defdata {tname} (enum '({' '.join(e.lstrip(chr(39)) for e in elems)})))"
        else:
            tname2 = f"fzt_{i}_b"
            form = f"(defdata ({tname} (oneof nil (cons {rng.choice(prim_types)} {tname2}))) ({tname2} (oneof nil (cons {rng.choice(prim_types)} {tname}))))"
        cases.append((f"rand_dd_{i}", form, f"(value-triple :CASE-rand_dd_{i}-DONE)"))
    return cases


def gen_definec_cases(rng, count=25):
    cases = []
    # Oracle: check formal count/order mismatch, bad MBE, empty/contradictory contract, capture
    fixed = [
        ("dc_dup_swap", "(definec dc_swap (x :int y :int x :pos) :int (- x y))",
         "(value-triple (list :FORMALS (acl2::formals 'dc_swap (w state)) :RES (dc_swap 10 1)))"),
        ("dc_dup_disj", "(definec dc_disj (x :nat y :nat x :string) :nat (mbe :logic (+ x y) :exec (car x)))",
         "(value-triple (list :FORMALS (acl2::formals 'dc_disj (w state)) :VERIFIED (acl2::getpropc 'dc_disj 'acl2::guard-verified nil (w state))))"),
        ("dc_multi_kw", "(definec dc_mkw (x :nat :pos y :int) :int (- x y))",
         "(value-triple (list :FORMALS (acl2::formals 'dc_mkw (w state)) :RES (dc_mkw 10 1)))"),
        ("dc_capture_res", "(definec dc_cres (res :nat _ret :nat) :nat (+ res _ret))",
         "(value-triple (dc_cres 2 3))"),
        ("dc_capture_x", "(definec dc_cx (x :nat y :pos) :pos (+ x y))",
         "(value-triple (dc_cx 2 3))"),
        ("dc_false_ret", "(definec dc_badret (x :nat) :pos x)",
         "(value-triple :CASE-dc_false_ret-AFTER)"),
        ("dc_nonterm_strict", "(definec dc_nonterm (x :nat) :nat (1+ (dc_nonterm x)))",
         "(value-triple (list :EXISTS (acl2::logical-namep 'dc_nonterm (w state))))"),
    ]
    for cid, form, oracle in fixed:
        cases.append((cid, form, f"{oracle}\n(value-triple :CASE-{cid}-DONE)"))

    vars_pool = ["x", "y", "z", "res", "_ret", "d", "ans"]
    types_pool = [":nat", ":pos", ":int", ":rational", ":bool", ":string", ":all"]
    for i in range(count):
        fn = f"fzdc_{i}"
        nargs = rng.randint(1, 3)
        params = []
        used = []
        for _ in range(nargs):
            v = rng.choice(vars_pool)
            used.append(v)
            t = rng.choice(types_pool)
            params.append(f"{v} {t}")
        ret_t = rng.choice(types_pool)
        # Keep all used vars referenced so ignore warning doesn't block interesting bugs
        uniq = list(dict.fromkeys(used))
        body_sum = "(+ " + " ".join(f"(if (integerp {v}) {v} 0)" for v in uniq) + ")"
        if rng.random() < 0.25:
            body = f"(mbe :logic {body_sum} :exec (car {uniq[0]}))"
        elif rng.random() < 0.25:
            body = f"(if (zp {uniq[0]}) 0 (1+ ({fn} {' '.join(f'(1- {v})' if idx == 0 else v for idx, v in enumerate(uniq))})))"
        else:
            body = body_sum
        form = f"(definec {fn} ({' '.join(params)}) {ret_t} {body})"
        used_lisp = "(" + " ".join(used) + ")"
        oracle = (
            f"(value-triple (list :FN '{fn} "
            f":DECLARED '{used_lisp} "
            f":ACTUAL (and (acl2::logical-namep '{fn} (w state)) (acl2::formals '{fn} (w state)))))"
        )
        cases.append((f"rand_dc_{i}", form, f"{oracle}\n(value-triple :CASE-rand_dc_{i}-DONE)"))
    return cases


def gen_property_cases(rng, count=20):
    cases = []
    # Known FALSE properties: MUST NOT succeed!
    fixed = [
        ("prop_false_nil", "(property prop_f1 () nil)", "MUST_FAIL"),
        ("prop_false_dup_disj", "(property prop_f2 (x :nat x :string) nil)", "CANARY"),
        ("prop_false_lt", "(property prop_f3 (x :nat) (< x 0))", "MUST_FAIL"),
        ("prop_false_arith", "(property prop_f4 (x :int) (> (* x x) 0))", "MUST_FAIL"),
        ("prop_expt_cgen", "(property prop_expt (x :nat) (natp (expt 2 (expt 2 x))))", "CHECK"),
        ("prop_let_implies", "(property prop_limp (x :nat) (let ((implies 1)) (posp (+ x implies))))", "CHECK"),
    ]
    for cid, form, mode in fixed:
        cases.append((cid, form, f"(value-triple (list :PROP-MODE '{mode} :CASE-{cid}-DONE))"))

    for i in range(count):
        pname = f"fzprop_{i}"
        v = rng.choice(["x", "y", "res", "d"])
        t1 = rng.choice([":nat", ":pos", ":int", ":string", ":bool"])
        if rng.random() < 0.5:
            # Known false property
            rhs = rng.choice(["nil", "(= 0 1)", "(and (natp x) (< x 0))"])
            form = f"(property {pname} ({v} {t1}) {rhs})"
            mode = "MUST_FAIL"
        else:
            # Random arithmetic / list check
            rhs = rng.choice([
                f"(equal {v} {v})",
                f"(implies (natp {v}) (<= 0 {v}))",
                f"(implies (and (natp {v}) (< {v} 10)) (< (* {v} {v}) 100))",
                f"(implies (stringp {v}) (natp (length {v})))",
            ])
            form = f"(property {pname} ({v} {t1}) {rhs})"
            mode = "CHECK"
        cases.append((f"rand_prop_{i}", form, f"(value-triple (list :PROP-MODE '{mode} :CASE-rand_prop_{i}-DONE))"))
    return cases


def gen_ccg_cases(rng, count=15):
    cases = []
    cases.append(("ccg_mode", "(acl2::set-termination-method :ccg)", "(value-triple :CASE-ccg_mode-DONE)"))
    fixed = [
        ("ccg_nonterm_1", "(defun ccg_nt1 (x) (declare (xargs :mode :logic)) (1+ (ccg_nt1 x)))", "MUST_FAIL"),
        ("ccg_nonterm_2", "(defun ccg_nt2 (x) (declare (xargs :mode :logic)) (if (integerp x) (1+ (ccg_nt2 (+ x 1))) 0))", "MUST_FAIL"),
        ("ccg_loop_rec", "(defun ccg_lrec (n) (declare (xargs :mode :logic :loop$-recursion t :measure (nfix n))) (if (zp n) 0 (loop$ for i in (list (1- n)) sum (ccg_lrec i))))", "CHECK"),
    ]
    for cid, form, mode in fixed:
        cases.append((cid, form, f"(value-triple (list :CCG-MODE '{mode} :EXISTS (acl2::logical-namep '{cid} (w state)) :CASE-{cid}-DONE))"))

    for i in range(count):
        fn = f"fzccg_{i}"
        step = rng.choice(["(1- x)", "(1+ x)", "x", "(cdr x)", "(floor x 2)"])
        guard = rng.choice(["(zp x)", "(endp x)", "(<= x 0)", "(= x 0)"])
        form = f"(defun {fn} (x) (declare (xargs :mode :logic)) (if {guard} 0 (1+ ({fn} {step}))))"
        must_fail = step in ("(1+ x)", "x")
        cases.append((f"rand_ccg_{i}", form, f"(value-triple (list :CCG-NAME '{fn} :MUST-FAIL {str(must_fail).upper()} :EXISTS (acl2::logical-namep '{fn} (w state)) :CASE-rand_ccg_{i}-DONE))"))
    return cases


def run_batch(acl2_bin, script_text, timeout_s=90):
    with tempfile.NamedTemporaryFile("w", suffix=".lisp", delete=False) as tf:
        tf.write(script_text)
        tf_path = tf.name
    try:
        cmd = [TIMEOUT_BIN, "--kill-after=10s", f"{timeout_s}s", acl2_bin]
        env = os.environ.copy()
        env["ACL2_SYSTEM_BOOKS"] = SHADOW_BOOKS
        wrapper_input = (
            PREAMBLE
            + f'\n(ld "{tf_path}" :ld-error-action :continue)\n'
            + '(in-package "ACL2S")\n'
            + '(thm nil)\n'
            + '(value-triple :FINAL-CANARY-DONE)\n'
        )
        proc = subprocess.run(
            cmd,
            input=wrapper_input,
            text=True,
            capture_output=True,
            env=env,
        )
        return proc.returncode, proc.stdout, proc.stderr
    finally:
        if os.path.exists(tf_path):
            os.unlink(tf_path)


def analyze_output(stdout, label=""):
    findings = []
    # Split by >>> CASE markers to attribute crashes/errors to exact cases
    parts = re.split(r">>> CASE ([^\r\n]+)", stdout)
    abort_cases = []
    mismatches = []
    for i in range(1, len(parts), 2):
        cid = parts[i].strip()
        body = parts[i + 1]
        if "ABORTING from raw Lisp" in body or "Unhandled memory fault" in body or "CORRUPTION WARNING" in body:
            err_lines = [ln.strip() for ln in body.splitlines() if "Error:" in ln or "ABORTING" in ln or "fault" in ln.lower()]
            abort_cases.append((cid, err_lines[:3]))
        if "CHOKE-ON-LOOP$-RECURSION" in body:
            findings.append(("CRASH_CCG_LOOP", f"{cid}: CCG hit CHOKE-ON-LOOP$-RECURSION defensive error"))
        m = re.search(r":DECLARED\s+'?\(([^)]+)\)\s+:ACTUAL\s+\(([^)]+)\)", body)
        if m:
            decl = m.group(1).split()
            actual = m.group(2).split()
            if decl != actual:
                mismatches.append((cid, decl, actual))
        if "MUST_FAIL" in body and "PROPERTY CHECKING SUCCESSFUL" in body:
            findings.append(("UNSOUND_PROPERTY", f"{cid} proved a MUST_FAIL false property!"))
        m2 = re.search(r":CCG-NAME\s+'?(FZCCG_\d+)\s+:MUST-FAIL\s+T\s+:EXISTS\s+T", body)
        if m2:
            findings.append(("UNSOUND_CCG_NONTERM", f"{m2.group(1)} was admitted despite MUST-FAIL T!"))
    for cid, errs in abort_cases:
        findings.append(("RAW_LISP_ABORT", f"{cid}: {errs}"))
    for cid, decl, actual in mismatches:
        findings.append(("DEFINEC_FORMALS_MISMATCH", f"{cid}: declared {decl} != actual {actual}"))
    # Check final canary (thm nil)
    tail = stdout.split(":FINAL-CANARY-DONE")[0][-1500:] if ":FINAL-CANARY-DONE" in stdout else stdout[-1500:]
    if "Q.E.D." in tail and "(THM NIL)" in tail.upper():
        findings.append(("CRITICAL_SOUNDNESS", "(thm nil) proved Q.E.D.!!"))
    return findings


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--runtime", choices=["sbcl", "ccl", "both"], default="both")
    ap.add_argument("--cases", type=int, default=20)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    all_cases = (
        gen_defdata_cases(rng, args.cases)
        + gen_definec_cases(rng, args.cases)
        + gen_property_cases(rng, args.cases)
        + gen_ccg_cases(rng, args.cases)
    )
    script = '(in-package "ACL2S")\n' + "\n".join(
        f"(cw \"~%>>> CASE {cid}~%\")\n{form}\n{oracle}"
        for cid, form, oracle in all_cases
    )

    runtimes = []
    if args.runtime in ("sbcl", "both"):
        runtimes.append(("SBCL-2.6.10", SBCL_ACL2))
    if args.runtime in ("ccl", "both"):
        runtimes.append(("CCL-1.14", CCL_ACL2))

    out_dir = Path("/Users/ember/dev/compiler-audit/hunts/acl2s")
    for label, bin_path in runtimes:
        print(f"=== Running fuzz batch (seed={args.seed}, cases={len(all_cases)}) on {label} ===")
        rc, out, err = run_batch(bin_path, script, timeout_s=120)
        (out_dir / f"last_fuzz_{label.lower()}.log").write_text(out)
        findings = analyze_output(out, label)
        print(f"[{label}] rc={rc}, stdout_len={len(out)}, findings={len(findings)}")
        for kind, detail in findings:
            print(f"  - [{kind}] {detail}")
        if err.strip():
            print(f"  [stderr preview] {err[:300]}")


if __name__ == "__main__":
    main()
