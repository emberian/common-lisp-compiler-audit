#!/usr/bin/env python3
"""
Wave-4 Lane 5: claude-kimi (Kimi K3.1-pro) Rake Harness over ACL2 8.7+ Core
Subsystems and SBCL 2.6.10 / CCL 1.14 Compiler Surfaces.

Follows the strict claude-kimi invocation protocol:
- Pre-slices large monoliths into ~1,200-1,500 line temp chunks in /tmp/w4-core-chunks/
  with exact original file:line headers so Kimi K3.1-pro reads 1-2 chunks in 1-2 Read
  calls and finishes well under the 360s timeout.
- Invokes /Users/ember/.local/bin/claude-kimi from an empty /tmp scratch directory.
- Disables all MCP servers (--strict-mcp-config --mcp-config '{"mcpServers":{}}').
- Restricts tools to read-only ("Read,Grep,Glob") and closes stdin (< /dev/null).
"""

import concurrent.futures
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CLAUDE_KIMI = "/Users/ember/.local/bin/claude-kimi"
TIMEOUT_BIN = "/opt/homebrew/bin/timeout"
CHUNK_DIR = Path("/tmp/w4-core-chunks")
OUT_DIR = Path("/tmp/w4-kimi-core-out")

ACL2 = "/Users/ember/dev/acl2-fix/head-worktree"
CCL = "/Users/ember/dev/ccl/compiler"
SBCL = "/tmp/w4-sbcl-src"

# Each entry: (rake_id, [(orig_path, start_line, end_line), ...], focus_prompt)
RAKES = [
    (
        "01-acl2-tau-bounders-rules",
        [
            (f"{ACL2}/tau.lisp", 1600, 3050),
            (f"{ACL2}/tau.lisp", 9900, 11300),
        ],
        "Audit these two slices of ACL2 8.7+ tau.lisp (interval arithmetic/tau-bounders and conjunctive/big-switch/signature tau rules). Look for: (1) unsound interval endpoints, strict vs non-strict (< vs <=) inversions, or non-integer/rational/complex confusion in tau-bounder-*; (2) dropped ttree assumptions or rune tracking; (3) unsound rule admission or application in conjunctive/big-switch/signature rules.",
    ),
    (
        "02-acl2-bdd-nonlinear",
        [
            (f"{ACL2}/bdd.lisp", 1840, 3235),
            (f"{ACL2}/non-linear.lisp", 55, 986),
        ],
        "Audit ACL2 8.7+ bdd.lisp (:bdd hint prover, combine-op-csts, combine-if-csts, bdd-clause) and non-linear.lisp (var-with-divisionp, invert-var, inverse-vars-p, inverse-polys, add-inverse-polys, add-polys-from-type-set). Look for: (1) propositional (iff) vs equal confusion on non-Boolean terms; (2) dropped ttree ('assumption / lemma) tags; (3) unsound non-linear bounds or hard errors (good-pot-varp / er hard) reachable from valid user theorems.",
    ),
    (
        "03-acl2-linear-ab",
        [
            (f"{ACL2}/linear-a.lisp", 2200, 2820),
            (f"{ACL2}/linear-b.lisp", 35, 620),
        ],
        "Audit ACL2 8.7+ linear-a.lisp (impossible-polyp, poly-weakerp, cancel-polys, find-equational-poly, add-poly) and linear-b.lisp (polys-from-type-set, eval-ground-subexpressions1, poly-set, linearize1). Look for: (1) dropped ttree assumptions when merging/subsuming/canceling polys or evaluating ground subexpressions; (2) complex/non-number vs rational confusion in linearize1 or find-equational-poly; (3) parent-tree (pt) bugs causing false contradictions.",
    ),
    (
        "04-acl2-apply-float",
        [
            (f"{ACL2}/apply.lisp", 1800, 2380),
            (f"{ACL2}/float-a.lisp", 380, 959),
        ],
        "Audit ACL2 8.7+ apply.lisp (ok-defbadge, chk-acceptable-defwarrant1, badge-table-guard1, check-ilks) and float-a.lisp (constrained/df IEEE float operations, rounding, NaN/Inf/-0.0 handling). Look for: (1) unsoundness or tameness/ilk/warrant bypass in apply$/badge-table-guard; (2) raw Lisp crash or axiom vs executable-counterpart mismatch on NaN, Inf, -0.0, denormals, or rounding modes in float-a.lisp.",
    ),
    (
        "05-acl2-par-iface",
        [
            (f"{ACL2}/parallel-raw.lisp", 1, 1435),
            (f"{ACL2}/interface-raw.lisp", 1120, 2350),
        ],
        "Audit ACL2 8.7+ parallel-raw.lisp (pand, por, plet, spec-mv-let) and interface-raw.lisp (stobj-let raw translation, df-call, raw execution wrappers). Look for logic-vs-raw evaluation discrepancies, multiple-value or stobj corruption, or state rollback bugs.",
    ),
    (
        "06-ccl-front-opt",
        [
            (f"{CCL}/nx1.lisp", 1400, 1980),
            (f"{CCL}/optimizers.lisp", 1500, 2100),
        ],
        "Audit Clozure CL (CCL 1.14) nx1.lisp and optimizers.lisp for zero-UB ANSI Common Lisp wrong-code or compile-time crash bugs (valid at safety 1 or safety 3). Exclude already-known: CCL-CG-2 ((space 0) -> (safety 0) in nx1-expand-inline-call), CCL-OPT-1 (require-type MV leak at safety 0), CCL-OPT-2 (unary truncate MV drop). Check argument evaluation order, multiple-value dropping/leaking, side-effecting arg elision, ash/boole/ldb/dpb/aref/coerce/complex transforms.",
    ),
    (
        "07-ccl-arm64-x86-p2",
        [
            (f"{CCL}/ARM64/arm642.lisp", 3200, 3800),
            (f"{CCL}/X86/x862.lisp", 2650, 3250),
        ],
        "Audit Clozure CL (CCL 1.14) ARM64/arm642.lisp and X86/x862.lisp pass-2 codegen handlers for zero-UB wrong-code or compile crashes (bad regspec: NIL, temp register clobbering of live inputs, wrong immediate bounds, misplaced parens, condition-code inversions, for-effect target=NIL crashes). Exclude already-known CCL-CG-1 (four-untargeted-reg-forms ddest), CCL-CG-4a/4b, HC-W3-6/7/8/9, and our new vref1/vset1 constant-index offset bugs.",
    ),
    (
        "08-sbcl-tran-arm64",
        [
            (f"{SBCL}/float-tran.lisp", 1200, 1800),
            (f"{SBCL}/arm64/float.lisp", 450, 1086),
        ],
        "Audit SBCL 2.6.10 float-tran.lisp and arm64/float.lisp for zero-UB ANSI Common Lisp miscompilations (valid at safety 3 or safety 1): IEEE -0.0 / NaN / Inf sign or branch inversion, wrong interval derivation in derive-type, register aliasing in ARM64 float/complex VOPs (missing :from (:argument ...) when output overwrites input before last read), or constant folding mismatches.",
    ),
    (
        "09-sbcl-array-modarith",
        [
            (f"{SBCL}/array-tran.lisp", 1800, 2400),
            (f"{SBCL}/modarith.lisp", 350, 950),
        ],
        "Audit SBCL 2.6.10 array-tran.lisp and modarith.lisp for zero-UB ANSI Common Lisp miscompilations (valid at safety 3 or safety 1): modular arithmetic width/sign/carry bugs on logand/logior/logxor/ash/+/-/*, wrong array-tran transforms on displaced/fill-pointer/upgraded/multi-dimensional arrays, or dropped bounds/type checks at safety 3.",
    ),
]


def write_chunks() -> dict[str, list[Path]]:
    if CHUNK_DIR.exists():
        shutil.rmtree(CHUNK_DIR)
    CHUNK_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    rake_files: dict[str, list[Path]] = {}
    for rake_id, specs, _ in RAKES:
        paths: list[Path] = []
        for idx, (orig, start, end) in enumerate(specs, 1):
            src = Path(orig)
            lines = src.read_text(errors="replace").splitlines()
            s = max(1, start)
            e = min(len(lines), end)
            chunk_path = CHUNK_DIR / f"{rake_id}_part{idx}_{src.name}"
            header = f";;; SOURCE: {orig} (lines {s}..{e} of {len(lines)})\n"
            body = "\n".join(
                f"{line_no:6d}: {lines[line_no - 1]}" for line_no in range(s, e + 1)
            )
            chunk_path.write_text(header + body + "\n")
            paths.append(chunk_path)
        rake_files[rake_id] = paths
    return rake_files


def run_one(rake_id: str, chunk_paths: list[Path], focus: str) -> tuple[str, int, float, int]:
    kdir = tempfile.mkdtemp(prefix=f"w4-kimi-{rake_id}-", dir="/tmp")
    out_file = OUT_DIR / f"{rake_id}.txt"
    files_list = "\n".join(f"- {p}" for p in chunk_paths)
    prompt = (
        f"Read ALL of the following pre-sliced source files completely in your first turn "
        f"(use Read with limit=2000 on each file; do NOT run extra searches):\n"
        f"{files_list}\n\n"
        f"TASK: {focus}\n\n"
        f"OUTPUT RULES:\n"
        f"- Report ONLY concrete candidate bugs backed by exact original source file + line numbers.\n"
        f"- For each candidate, provide: (1) Exact original file:line, (2) Exact buggy code & root cause, "
        f"(3) Concrete witness input / minimal Lisp or ACL2 expression that triggers it.\n"
        f"- Maximum 220 lines total. Be terse, technical, and high-signal."
    )
    cmd = [
        TIMEOUT_BIN,
        "--kill-after=10s",
        "360s",
        CLAUDE_KIMI,
        "-p",
        prompt,
        "--allowedTools",
        "Read,Grep,Glob",
        "--strict-mcp-config",
        "--mcp-config",
        '{"mcpServers":{}}',
    ]
    t0 = time.time()
    try:
        with open(os.devnull, "rb") as devnull:
            res = subprocess.run(
                cmd,
                cwd=kdir,
                stdin=devnull,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=375,
            )
        elapsed = time.time() - t0
        text = res.stdout or ""
        if res.stderr:
            text += "\n--- STDERR ---\n" + res.stderr
        out_file.write_text(text)
        line_cnt = len((res.stdout or "").splitlines())
        print(f"[DONE] {rake_id}: rc={res.returncode} elapsed={elapsed:.1f}s stdout_lines={line_cnt} -> {out_file}", flush=True)
        return (rake_id, res.returncode, elapsed, line_cnt)
    except Exception as exc:
        elapsed = time.time() - t0
        out_file.write_text(f"EXCEPTION after {elapsed:.1f}s: {exc}\n")
        print(f"[ERR] {rake_id}: {exc}", flush=True)
        return (rake_id, -1, elapsed, 0)
    finally:
        shutil.rmtree(kdir, ignore_errors=True)


def main() -> int:
    filters = sys.argv[1:]
    selected = [
        r for r in RAKES
        if not filters or any(r[0].startswith(f) or f in r[0] for f in filters)
    ]
    rake_files = write_chunks()
    print(f"Prepared {len(selected)}/{len(RAKES)} pre-sliced chunk groups in {CHUNK_DIR}; launching claude-kimi (max_workers=3)...", flush=True)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futs = [
            pool.submit(run_one, rake_id, rake_files[rake_id], focus)
            for rake_id, _, focus in selected
        ]
        for fut in concurrent.futures.as_completed(futs):
            results.append(fut.result())

    print("\n=== SUMMARY ===", flush=True)
    for rake_id, rc, elapsed, lines in sorted(results):
        print(f"  {rake_id}: rc={rc}, {elapsed:.1f}s, stdout_lines={lines}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
