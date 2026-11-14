#!/usr/bin/env python3
"""w4-ar-books: counterexample-guided false-theorem fuzzer for ACL2 community
book proof engines (arithmetic-5 meta/bind-free rules, osets/omaps/obags,
data-structures), run on saved_acl2 (SBCL / CCL).

Pipeline per batch:
  1. Generate random conjectures (Python).
  2. Session A (guard-checking :none): evaluate every conjecture on a grid of
     concrete witnesses (rationals, complex rationals, non-numbers) and keep
     only conjectures that are FALSE on at least one witness.
  3. Session B: with the target library included (certified copy in /tmp,
     :ttags nil), try to prove every false conjecture under a prover step
     limit.  Any Q.E.D. is a proof of a false statement => (defthm nil-proved nil).

Usage:
  PYTHONDONTWRITEBYTECODE=1 python3 probe_books_engines.py \
      --books /tmp/w4-ar-books-XXXX/books --lib arith5 --seed 1 --cases 300
"""
import argparse
import os
import random
import re
import subprocess
import sys
import tempfile

SBCL = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"
TIMEOUT = "/opt/homebrew/bin/timeout"

LIBS = {
    "arith5": ['(include-book "arithmetic-5/top" :dir :system)'],
    "arith5-nl": ['(include-book "arithmetic-5/top" :dir :system)',
                  '(set-default-hints \'((acl2::nonlinearp-default-hint '
                  'acl2::stable-under-simplificationp acl2::hist acl2::pspv)))'],
    "osets": ['(include-book "std/osets/top" :dir :system)'],
    "none": [],
}

VARS = ["x", "y", "z", "n"]
CONSTS = ["0", "1", "-1", "2", "-2", "1/2", "-3/2", "3", "#c(0 1)", "#c(1 -1/2)", "4"]
WITNESS = ["0", "1", "-1", "2", "1/2", "-3/2", "3", "-2", "#c(0 1)", "#c(1 1)",
           "#c(-1/2 2)", "'a", "nil", "5/3", "-7", "#c(2 -3)"]


def gen_num(r, d):
    if d <= 0 or r.random() < 0.3:
        return r.choice(VARS) if r.random() < 0.7 else r.choice(CONSTS)
    op = r.choice(["+", "+", "-", "*", "*", "/", "unary--", "expt", "floor", "mod",
                   "numerator", "denominator", "abs", "fix", "realpart",
                   "imagpart", "ifix", "rfix", "nfix", "logand", "ash", "truncate", "rem"])
    if op in ("+", "*"):
        return f"({op} {gen_num(r, d-1)} {gen_num(r, d-1)})"
    if op == "-":
        return f"(- {gen_num(r, d-1)} {gen_num(r, d-1)})"
    if op == "/":
        return f"(/ {gen_num(r, d-1)})" if r.random() < 0.5 else f"(/ {gen_num(r, d-1)} {gen_num(r, d-1)})"
    if op == "unary--":
        return f"(- {gen_num(r, d-1)})"
    if op == "expt":
        e = r.choice(["n", "-1", "2", "-2", "0", "(- n)", "(+ 1 n)", "3", "x"])
        b = r.choice(["2", "x", "y", "1/2", "-1", "0", gen_num(r, d-1)])
        return f"(expt {b} {e})"
    if op in ("floor", "mod", "truncate", "rem"):
        return f"({op} {gen_num(r, d-1)} {r.choice(['2','x','y','1/2','-3','0', gen_num(r, d-1)])})"
    if op == "logand":
        return f"(logand {gen_num(r, d-1)} {gen_num(r, d-1)})"
    if op == "ash":
        return f"(ash {gen_num(r, d-1)} {r.choice(['1','-1','2','n','(- n)'])})"
    return f"({op} {gen_num(r, d-1)})"


def gen_rel(r, d):
    k = r.random()
    a, b = gen_num(r, d), gen_num(r, d)
    if k < 0.35:
        return f"(< {a} {b})"
    if k < 0.55:
        return f"(<= {a} {b})"
    if k < 0.8:
        return f"(equal {a} {b})"
    p = r.choice(["integerp", "rationalp", "acl2-numberp", "natp", "posp", "complex-rationalp", "evenp", "zerop"])
    return f"({p} {a})"


def gen_conj(r):
    hyps = []
    for v in VARS:
        t = r.random()
        if t < 0.25:
            hyps.append(f"(rationalp {v})")
        elif t < 0.45:
            hyps.append(f"(integerp {v})")
        elif t < 0.55:
            hyps.append(f"(acl2-numberp {v})")
        elif t < 0.6:
            hyps.append(f"(natp {v})")
    for _ in range(r.randint(0, 2)):
        hyps.append(gen_rel(r, 2))
    concl = gen_rel(r, 3)
    if not hyps:
        return concl
    return f"(implies (and {' '.join(hyps)}) {concl})"


def acl2_run(binary, script, timeout_s, books):
    env = dict(os.environ)
    env["ACL2_SYSTEM_BOOKS"] = books
    with tempfile.NamedTemporaryFile("w", suffix=".lsp", delete=False,
                                     dir=os.path.dirname(books.rstrip("/"))) as f:
        f.write(script)
        path = f.name
    try:
        p = subprocess.run([TIMEOUT, "--kill-after=10s", f"{timeout_s}s", binary],
                           stdin=open(path), capture_output=True, text=True,
                           env=env, cwd=os.path.dirname(books.rstrip("/")))
        return p.stdout + p.stderr
    finally:
        os.unlink(path)


def falsity_script(conjs):
    out = ["(set-guard-checking :none)", "(set-inhibit-output-lst '(warning observation prove summary event proof-tree))"]
    for i, c in enumerate(conjs):
        clauses = []
        for _ in range(60):
            pass
        out.append(f"(defun cfn{i} (x y z n) (declare (xargs :mode :program)) {c})")
    out.append("(defun ws () (declare (xargs :mode :program)) (list " + " ".join(WITNESS) + "))")
    # brute force over all 16^4 = 65536 points is too much; use random sample of points
    return out


def build_eval(conjs, r):
    pts = []
    for _ in range(80):
        pts.append(tuple(r.choice(WITNESS) for _ in VARS))
    # always include some structured points
    for w in WITNESS:
        pts.append((w, w, w, w))
    lines = ["(set-guard-checking :none)",
             "(set-inhibit-output-lst '(warning warning! observation prove summary event proof-tree))"]
    for i, c in enumerate(conjs):
        lines.append(f"(defun cfn{i} (x y z n) (declare (xargs :mode :program) (ignorable x y z n)) {c})")
    for i, _ in enumerate(conjs):
        tests = " ".join(f"(cfn{i} {a} {b} {cc} {d})" for (a, b, cc, d) in pts)
        # quote symbols properly: WITNESS already contains 'a / nil
        lines.append(f"(cw \"@FALSE ~x0 ~x1~%\" {i} (not (and {tests})))")
    return "\n".join(lines) + "\n(good-bye)\n"


def build_prove(conjs, idxs, lib, steps):
    lines = list(LIBS[lib])
    lines.append("(set-inhibit-output-lst '(warning warning! observation prove proof-builder summary event proof-tree history))")
    for i in idxs:
        lines.append(f"(with-prover-step-limit {steps} (defthm cand{i} {conjs[i]} :rule-classes nil))")
    lines.append("(cw \"@CHK ~x0~%\" (list " +
                 " ".join(f"(cons {i} (if (getpropc 'cand{i} 'theorem) t nil))" for i in idxs) + "))")
    lines.append("(cw \"@SKIP ~x0 ~x1~%\" (global-val 'skip-proofs-seen (w state)) (global-val 'ttags-seen (w state)))")
    return "\n".join(lines) + "\n(good-bye)\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--books", required=True)
    ap.add_argument("--lib", default="arith5")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--cases", type=int, default=200)
    ap.add_argument("--steps", type=int, default=40000)
    ap.add_argument("--runtime", default="sbcl")
    ap.add_argument("--out", default=None)
    a = ap.parse_args()
    r = random.Random(a.seed)
    conjs = [gen_conj(r) for _ in range(a.cases)]
    binary = SBCL if a.runtime == "sbcl" else CCL
    ev = acl2_run(binary, build_eval(conjs, r), 300, a.books)
    false_idx = [int(m.group(1)) for m in re.finditer(r"@FALSE (\d+) T", ev)]
    evald = len(re.findall(r"@FALSE \d+ ", ev))
    print(f"[eval] evaluated={evald}/{len(conjs)} false={len(false_idx)}", flush=True)
    if evald < len(conjs):
        print(ev[-3000:])
    proved = []
    B = 40
    for k in range(0, len(false_idx), B):
        chunk = false_idx[k:k+B]
        out = acl2_run(binary, build_prove(conjs, chunk, a.lib, a.steps), 600, a.books)
        m = re.search(r"@CHK (.*)", out)
        sk = re.search(r"@SKIP (.*)", out)
        if not m:
            print("[prove] no @CHK; tail:\n" + out[-2000:])
            continue
        for i in chunk:
            if re.search(rf"\({i} \. T\)", m.group(1)):
                proved.append(i)
                print(f"!!! FALSE CONJECTURE PROVED cand{i}: {conjs[i]}  skip/ttags={sk.group(1) if sk else '?'}", flush=True)
        print(f"[prove] chunk {k//B}: done ({len(proved)} hits so far)", flush=True)
    print(f"[summary] seed={a.seed} cases={len(conjs)} false={len(false_idx)} proved_false={len(proved)}")
    if a.out:
        with open(a.out, "w") as f:
            for i in proved:
                f.write(conjs[i] + "\n")


if __name__ == "__main__":
    main()
