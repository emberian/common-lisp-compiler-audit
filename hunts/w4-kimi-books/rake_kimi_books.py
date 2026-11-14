#!/usr/bin/env python3
"""
Wave-4 Lane 4 (`w4-kimi-books`): Kimi K3 (`claude-kimi`) Rake Driver for ACL2 Community Books.

Strictly follows the invocation protocol:
- Runs each slice from an isolated empty `/tmp/w4-kimi-books-XXXXXX` directory (`cwd=kdir`)
  which is deleted in `finally:`.
- Disables all MCP servers (`--strict-mcp-config --mcp-config '{"mcpServers":{}}'`).
- Restricts tools to read-only (`--allowedTools "Read,Grep,Glob"`).
- Redirects stdin from `/dev/null` (`stdin=subprocess.DEVNULL`).
- Enforces `/opt/homebrew/bin/timeout --kill-after=10s 360s` + Python `timeout=375`.
- Runs up to 3 slices in parallel via `ThreadPoolExecutor(max_workers=3)`.
"""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

SYS.dont_write_bytecode = True if hasattr((SYS := sys), "dont_write_bytecode") else None

BOOKS = "/Users/ember/dev/acl2-fix/head-worktree/books"
CLAUDE_KIMI = "/Users/ember/.local/bin/claude-kimi"
TIMEOUT_BIN = "/opt/homebrew/bin/timeout"

SLICES: list[dict[str, object]] = [
    {
        "id": "s1_bitsets_strings_raw",
        "title": "books/std/bitsets & books/std/strings raw Lisp optimizations vs :logic",
        "focus": (
            "Audit raw Common Lisp overrides vs :logic definitions and ACL2 guards. "
            "Check negative integers, bignums exceeding fixnum (> 2^60), non-fixnum slice indices, "
            "(safety 0) declarations, non-simple strings (adjustable/fill-pointer/displaced if reachable or via coerce), "
            "improper/dotted printtrees, fixnum overflow on lengths, host reader conditionals (#+/#- Clozure x86-64 vs arm64!), "
            "and missing invariant-risk declarations."
        ),
        "files": [
            f"{BOOKS}/std/bitsets/bignum-extract.lisp",
            f"{BOOKS}/std/bitsets/bignum-extract-opt.lisp",
            f"{BOOKS}/std/bitsets/bignum-extract-opt-raw.lsp",
            f"{BOOKS}/std/bitsets/bitsets.lisp",
            f"{BOOKS}/std/bitsets/sbitsets.lisp",
            f"{BOOKS}/std/bitsets/bitsets-opt.lisp",
            f"{BOOKS}/std/bitsets/bitsets-opt-raw.lsp",
            f"{BOOKS}/std/strings/fast-cat.lisp",
            f"{BOOKS}/std/strings/fast-cat-raw.lsp",
        ],
    },
    {
        "id": "s2_stdio_printtree_raw",
        "title": "books/std/io & printtree raw Lisp readers/serializers/channels",
        "focus": (
            "Audit raw Lisp reader/string/IO implementations vs :logic specifications and ACL2 state invariants. "
            "Check read-string-raw.lsp, read-string-light-raw.lsp, unsound-read-raw.lsp, printtree-concat.lisp: "
            "package lookup edge cases, *read-eval* / sharp-macro reader syntax (#., #1=, #C, ratios, non-ACL2 objects, "
            "bad-lisp-objectp bypasses), live-state-p / oracle discrepancies, missing invariant-risk on :logic functions "
            "with side effects or global variables (*read-string-should-check-bad-lisp-object*, hons/memo tables), "
            "and (safety 0) printtree bounds/type assumptions."
        ),
        "files": [
            f"{BOOKS}/std/strings/printtree.lisp",
            f"{BOOKS}/std/strings/printtree-concat.lisp",
            f"{BOOKS}/std/io/read-string.lisp",
            f"{BOOKS}/std/io/read-string-raw.lsp",
            f"{BOOKS}/std/io/read-string-light.lisp",
            f"{BOOKS}/std/io/read-string-light-raw.lsp",
            f"{BOOKS}/std/io/unsound-read.lisp",
            f"{BOOKS}/std/io/unsound-read-raw.lsp",
            f"{BOOKS}/std/io/read-file-objects.lisp",
        ],
    },
    {
        "id": "s3_stobjs_std_tools",
        "title": "books/std/stobjs & books/tools stobj/absstobj/cloning machinery",
        "focus": (
            "Audit defabsstobj, stobj cloning, 1d/2d/bit arrays, stobj-frame, and stobj-swap macros/theorems. "
            "Check unsoundness, guard-verification bypasses, malformed export/corr/creator/preserved obligations, "
            "fixnum/type declaration mismatches on array dimensions or resize lengths, congruent stobj aliasing, "
            "non-executable stobj edge cases, and macro hygiene/duplicate-field bugs."
        ),
        "files": [
            f"{BOOKS}/std/stobjs/absstobjs.lisp",
            f"{BOOKS}/std/stobjs/clone.lisp",
            f"{BOOKS}/std/stobjs/2d-arr.lisp",
            f"{BOOKS}/std/stobjs/1d-arr.lisp",
            f"{BOOKS}/std/stobjs/bitarr.lisp",
            f"{BOOKS}/std/stobjs/updater-independence.lisp",
            f"{BOOKS}/tools/clone-stobj.lisp",
            f"{BOOKS}/tools/stobj-frame.lisp",
            f"{BOOKS}/centaur/misc/stobj-swap.lisp",
        ],
    },
    {
        "id": "s4a_tools_eval_instance",
        "title": "books/tools evaluator, functional-instance, er-soft-logic, elide-event, remove-hyps",
        "focus": (
            "Audit defevaluator-fast, def-functional-instance, er-soft-logic, elide-event, and remove-hyps. "
            "Check: malformed input or variable/keyword collisions in def-functional-instance, elide-event, "
            "and remove-hyps (e.g. let/let* bindings, ignorable declarations, docstring/keyword parsing, "
            "f-put-global state mutation without invariant-risk, thm vs defthm handling), and guard/fmt bugs in er-soft-logic."
        ),
        "files": [
            f"{BOOKS}/tools/defevaluator-fast.lisp",
            f"{BOOKS}/tools/def-functional-instance.lisp",
            f"{BOOKS}/tools/er-soft-logic.lisp",
            f"{BOOKS}/tools/elide-event.lisp",
            f"{BOOKS}/tools/remove-hyps.lisp",
        ],
    },
    {
        "id": "s4b_tools_world_prove",
        "title": "books/tools with-supporters, prove$, and rewrite$",
        "focus": (
            "Audit with-supporters, prove-dollar, and rewrite-dollar. "
            "Check: world/theory/local leaks or missing supporter tracking in with-supporters, "
            "guard/state/ttree/ens/revert-world/step-limit/time-limit/catch-hard-error bugs in prove$ and rewrite$."
        ),
        "files": [
            f"{BOOKS}/tools/with-supporters.lisp",
            f"{BOOKS}/tools/prove-dollar.lisp",
            f"{BOOKS}/tools/rewrite-dollar.lisp",
        ],
    },
    {
        "id": "s5_std_util_macros",
        "title": "books/std/util macro, guard, and contract generators",
        "focus": (
            "Audit define, formals, returnspecs, defrule, defaggregate, deflist, defalist, defprojection, defenum. "
            "Check: duplicate formals or return binders, contradictory or dropped guards, mbe / inline / $inline "
            "wrappers, stobj / mv return-spec arity mismatches, fty / fixequiv congruence generation on malformed "
            "predicates, and macro expansion crashes or silent contract inversions on valid user inputs."
        ),
        "files": [
            f"{BOOKS}/std/util/define.lisp",
            f"{BOOKS}/std/util/formals.lisp",
            f"{BOOKS}/std/util/returnspecs.lisp",
            f"{BOOKS}/std/util/defrule.lisp",
            f"{BOOKS}/std/util/defaggregate.lisp",
            f"{BOOKS}/std/util/deflist.lisp",
            f"{BOOKS}/std/util/defalist.lisp",
            f"{BOOKS}/std/util/defprojection.lisp",
            f"{BOOKS}/std/util/defenum.lisp",
        ],
    },
    {
        "id": "s6_bstar_tools_raw_oracles",
        "title": "books/std/util/bstar & books/tools raw Lisp oracle/timelimit/advise/gc hooks",
        "focus": (
            "Audit bstar binders and books/tools raw Lisp files (oracle-timelimit, oracle-eval-real, "
            "time-dollar-with-gc, advise, plev-ccl). Check: raw Lisp vs :logic return value/arity/mv mismatches, "
            "state/oracle corruption when called from :logic or :program/make-event without invariant-risk, "
            "uncaught storage-condition/timeout unwinds leaving mutated globals or special variables, "
            "advise-raw arbitrary Lisp execution or logic-function mutation, and CCL/SBCL host crashes."
        ),
        "files": [
            f"{BOOKS}/std/util/bstar.lisp",
            f"{BOOKS}/tools/oracle-timelimit.lisp",
            f"{BOOKS}/tools/oracle-timelimit-raw.lsp",
            f"{BOOKS}/tools/oracle-eval-real.lisp",
            f"{BOOKS}/tools/time-dollar-with-gc.lisp",
            f"{BOOKS}/tools/time-dollar-with-gc-raw.lsp",
            f"{BOOKS}/tools/advise.lisp",
            f"{BOOKS}/tools/advise-raw.lsp",
            f"{BOOKS}/tools/plev-ccl-raw.lsp",
        ],
    },
    {
        "id": "s7_centaur_aig_misc_bitops",
        "title": "books/centaur/{aig,misc,bitops} raw Lisp & bitops mbe optimizations",
        "focus": (
            "Audit aig-vars-fast (+ raw), count-branches-fast, fast-cons-memo (+ raw), seed-random (+ raw), "
            "sparseint, fast-logext, and fast-part-select. Do NOT report fast-alist-pop* (already known). "
            "Check: raw Lisp hash-table / array / state / random-state mutations lacking invariant-risk, "
            ":logic vs raw return order/type mismatches on non-boolean AIG atoms or cyclic/non-normed inputs, "
            "fixnum overflow in raw counters, and mbe :exec vs :logic discrepancies in bitops/sparseint."
        ),
        "files": [
            f"{BOOKS}/centaur/aig/aig-vars-fast.lisp",
            f"{BOOKS}/centaur/aig/aig-vars-fast-raw.lsp",
            f"{BOOKS}/centaur/aig/count-branches-fast.lsp",
            f"{BOOKS}/centaur/misc/fast-cons-memo.lisp",
            f"{BOOKS}/centaur/misc/fast-cons-memo-raw.lsp",
            f"{BOOKS}/centaur/misc/seed-random.lisp",
            f"{BOOKS}/centaur/misc/seed-random-raw.lsp",
            f"{BOOKS}/centaur/bitops/fast-logext.lisp",
            f"{BOOKS}/centaur/bitops/fast-part-select.lisp",
        ],
    },
    {
        "id": "s8_ubdds_make_event_misc_raw",
        "title": "books/centaur/ubdds, books/make-event & books/misc raw Lisp / defttag macros",
        "focus": (
            "Audit ubdds core/extra-operations, make-event (defconst-fast, dotimes, eval-check), and misc "
            "(defattach-bang, wet, profiling + raw, oprof + raw). Check: raw Lisp vs :logic mismatches, "
            "missing invariant-risk on raw side-effecting functions callable from :program + make-event, "
            "skip-checks / defttag leaks in defattach-bang or dotimes, and unhandled raw Lisp crashes on SBCL/CCL."
        ),
        "files": [
            f"{BOOKS}/centaur/ubdds/core.lisp",
            f"{BOOKS}/make-event/defconst-fast.lisp",
            f"{BOOKS}/make-event/dotimes.lisp",
            f"{BOOKS}/misc/defattach-bang.lisp",
            f"{BOOKS}/misc/wet.lisp",
            f"{BOOKS}/misc/profiling.lisp",
            f"{BOOKS}/misc/profiling-raw.lsp",
            f"{BOOKS}/misc/oprof.lisp",
            f"{BOOKS}/misc/oprof-raw.lsp",
        ],
    },
]


def build_prompt(slice_spec: dict[str, object]) -> str:
    files_block = "\n".join(f"- {p}" for p in slice_spec["files"])  # type: ignore[index]
    return (
        f"Perform a deep formal-methods security & soundness source audit ONLY on these exact ACL2 Community Books files:\n"
        f"{files_block}\n\n"
        f"Audit Focus:\n{slice_spec['focus']}\n\n"
        f"CRITICAL EXECUTION RULES (360s hard timeout!):\n"
        f"1. Read ONLY the listed files above (do NOT glob/search the whole repository).\n"
        f"2. BATCH YOUR READS IN PARALLEL: In Turn 1, invoke `Read` on ALL listed files in ONE parallel tool-call batch "
        f"(pass `limit: 400` so large files don't overflow). Do at most ONE follow-up `Read`/`Grep` batch in Turn 2 if needed, "
        f"then immediately write your report in Turn 3.\n"
        f"3. Look for concrete bugs: (a) :logic vs raw Lisp / :exec mismatch proving NIL, "
        f"(b) missing ACL2 `invariant-risk` property on raw-Lisp functions that mutate globals/tables/state (allowing NIL via :program + make-event), "
        f"(c) `skip-proofs` / `defattach :skip-checks t` / `defttag` macros that accept malformed user input to prove NIL or crash guard-verified code, "
        f"(d) raw Lisp `(safety 0)` / `(the fixnum ...)` / host `#+` conditionals (hosts are SBCL 2.6.10 arm64 and Clozure CL 1.14 arm64, NOT x86-64!) causing wrong results or memory faults on guard-legal inputs, "
        f"(e) macro parameter/contract/guard bugs.\n"
        f"4. Output concise Markdown UNDER 260 LINES total. For each candidate bug, give:\n"
        f"   - Title & Severity (Soundness / Trust-Tagged-Soundness / Guard-Bypass-Crash / Contract-Bug)\n"
        f"   - Exact File:Line\n"
        f"   - Exact Root Cause\n"
        f"   - Concrete minimal ACL2 witness expression / reproducer sketch to test in `saved_acl2`.\n"
        f"If a file is clean after reading, list it briefly under 'Clean Files'."
    )


def run_slice(slice_spec: dict[str, object], out_dir: Path, effort: str = "medium") -> dict[str, object]:
    sid = str(slice_spec["id"])
    prompt = build_prompt(slice_spec)
    kdir = Path(tempfile.mkdtemp(prefix=f"w4-kimi-books-{sid}-", dir="/tmp"))
    out_file = out_dir / f"{sid}.md"
    t0 = time.monotonic()
    cmd = [
        TIMEOUT_BIN,
        "--kill-after=10s",
        "360s",
        CLAUDE_KIMI,
        "-p",
        prompt,
        "--effort",
        effort,
        "--allowedTools",
        "Read,Grep,Glob",
        "--strict-mcp-config",
        "--mcp-config",
        '{"mcpServers":{}}',
    ]
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(kdir),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=375,
        )
        rc = proc.returncode
        output = proc.stdout or ""
    except subprocess.TimeoutExpired as exc:
        rc = 124
        output = (exc.stdout.decode("utf-8", "replace") if isinstance(exc.stdout, bytes) else (exc.stdout or "")) + "\n[TIMEOUT]\n"
    finally:
        shutil.rmtree(kdir, ignore_errors=True)

    elapsed = round(time.monotonic() - t0, 1)
    out_file.write_text(output, encoding="utf-8")
    return {
        "id": sid,
        "title": slice_spec["title"],
        "rc": rc,
        "elapsed_s": elapsed,
        "lines": len(output.splitlines()),
        "bytes": len(output.encode("utf-8")),
        "out_file": str(out_file),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--effort", type=str, default="medium", choices=["low", "medium", "high"])
    ap.add_argument("--out-dir", type=Path, default=Path("/tmp/w4-kimi-books-out"))
    ap.add_argument("--only", nargs="*", default=None)
    args = ap.parse_args()

    selected = [s for s in SLICES if not args.only or s["id"] in args.only]
    missing = [f for s in selected for f in s["files"] if not os.path.isfile(f)]  # type: ignore[index]
    if missing:
        print("ERROR: missing slice files:", file=sys.stderr)
        for m in missing:
            print("  ", m, file=sys.stderr)
        return 1

    args.out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Launching {len(selected)} claude-kimi slices (max_workers={args.workers}, effort={args.effort}) -> {args.out_dir}", flush=True)

    results: list[dict[str, object]] = []
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futs = {pool.submit(run_slice, s, args.out_dir, args.effort): s["id"] for s in selected}
        for fut in as_completed(futs):
            res = fut.result()
            results.append(res)
            print(
                f"  [DONE] {res['id']}: rc={res['rc']} elapsed={res['elapsed_s']}s lines={res['lines']} bytes={res['bytes']}",
                flush=True,
            )

    results.sort(key=lambda r: str(r["id"]))
    print("All slices finished.")
    return 0 if all(r["rc"] == 0 for r in results) else 2


if __name__ == "__main__":
    raise SystemExit(main())
