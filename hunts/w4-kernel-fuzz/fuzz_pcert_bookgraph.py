#!/usr/bin/env python3
"""
Wave-4 Deep Kernel Fuzzer §5.2: Provisional Certification (`:pcert`), `.acl2x`,
`@expansion.lsp`, Portcullis Packages, and Multi-Book DAG Inclusion
==============================================================================

Implements the stateful book-graph fuzzer specified in ACL2-KERNEL-DEEP.md §5.2,
while explicitly EXCLUDING known Wave-3 bugs:
  - Excludes KD-1 (`defconst` inside `with-output`, `with-prover-step-limit`,
    `with-guard-checking-event` / `with-guard-checking`).
  - Excludes KD-3 (mutating sub-book `.lisp` between `:pcert :convert` and
    `:pcert :complete`).

Novel axes fuzzed across 2-node, 3-node, and 4-node diamond book DAGs:
  1. Interleaved `:pcert :create` -> `:pcert :convert` -> `:pcert :complete`
     orders (topological, reverse-topological, diamond-mixed) with `local` vs
     non-`local` `include-book` edges.
  2. Double certification (`.acl2x` via `set-write-acl2x`) interacted with
     `:pcert {:create, :convert, :complete}` and `:save-expansion-file {t, nil}`.
  3. Non-trivial portcullis commands (`k > 0` with `defpkg` + symbol imports)
     combined with `make-event`, elided `defconst`, `defun`, `defun-sk`,
     constrained `encapsulate`, and `table` events.
  4. Cross-session `include-book` verification under `:load-compiled-file` in
     `{t, :comp, nil}` plus executable evaluation check and `(thm nil)`
     soundness check.

All files are created strictly inside ephemeral `/tmp/w4-kf-pcert-XXXXXX`
directories and deleted unconditionally on exit.
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
from typing import Dict, List, Optional, Sequence, Tuple

sys.dont_write_bytecode = True

TIMEOUT_BIN = "/opt/homebrew/bin/timeout"
DEFAULT_SBCL_ACL2 = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
DEFAULT_CCL_ACL2 = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"

CRASH_PATTERNS = [
    re.compile(r"^!!!W4-KF-PCERT-SOUNDNESS-BUG", re.MULTILINE),
    re.compile(r"^!!!W4-KF-PCERT-EVAL-MISMATCH", re.MULTILINE),
    re.compile(r"^!!!W4-KF-PCERT-UNEXPECTED-ERR", re.MULTILINE),
    re.compile(r"HARD ACL2 ERROR"),
    re.compile(r"Implementation error:"),
    re.compile(r"ABORTING from raw Lisp"),
    re.compile(r"ACL2 Halted"),
    re.compile(r"debugger invoked on"),
    re.compile(r"Unhandled memory fault"),
    re.compile(r"^> Error:", re.MULTILINE),
]


@dataclass
class BookNode:
    name: str
    includes: List[Tuple[str, bool]]  # (book_name, is_local)
    body_forms: List[str]
    cert_mode: str  # "normal", "pcert", "acl2x_normal", "acl2x_pcert"
    save_expansion: bool
    use_pkg_portcullis: bool
    pkg_name: Optional[str]
    expected_fn: str
    expected_val_at_5: int


def make_body_variant(
    variant: str,
    prefix: str,
    const_val: int,
    dep_expr: str,
    dep_val_at_5: int,
    pkg_name: Optional[str],
) -> Tuple[List[str], str, int]:
    """
    Generates a valid, provable book body WITHOUT KD-1 wrappers around elided defconsts.
    Returns (forms, exported_fn_name, expected_value_of_(exported_fn 5)).
    """
    fn_name = f"{prefix}-fn"
    c_name = f"*{prefix}-c*"
    forms: List[str] = []

    if variant == "progn_defconst_me":
        # make-event -> progn containing quoted-pair defconst (elided!) + defun using it
        forms.append(
            f"(make-event '(progn"
            f"  (defconst {c_name} '({const_val} . 10))"
            f"  (defun {fn_name} (x) (+ (car {c_name}) {dep_expr}))))"
        )
        val5 = const_val + dep_val_at_5

    elif variant == "encap_empty_defconst_me":
        # make-event -> (encapsulate () (local ...) (defconst ...) (defun ...))
        forms.append(
            f"(make-event '(encapsulate ()"
            f"  (local (defun {prefix}-loc (z) (+ (ifix z) 1)))"
            f"  (defconst {c_name} '({const_val} . 20))"
            f"  (defun {fn_name} (x) (+ (car {c_name}) {dep_expr}))))"
        )
        val5 = const_val + dep_val_at_5

    elif variant == "constrained_encap_and_sk":
        # Constrained encapsulate + defun-sk + executable defun inside make-event
        forms.append(
            f"(encapsulate ((( {prefix}-cfn *) => *))"
            f"  (local (defun {prefix}-cfn (u) (ifix u)))"
            f"  (defthm {prefix}-cfn-intp (integerp ({prefix}-cfn u))))"
        )
        forms.append(
            f"(defun-sk {prefix}-sk (x)"
            f"  (exists y (equal y (+ (ifix x) ({prefix}-cfn x)))))"
        )
        forms.append(
            f"(defun {fn_name} (x) (+ {const_val} {dep_expr}))"
        )
        forms.append(
            f"(defthm {fn_name}-intp (integerp ({fn_name} x)))"
        )
        val5 = const_val + dep_val_at_5

    elif variant == "nested_make_event_table":
        # Two-stage nested make-event + table update + elided defconst
        forms.append(
            f"(table {prefix}-tbl :k '({const_val} . :tag))"
        )
        forms.append(
            f"(make-event"
            f"  (let ((pair (cdr (assoc-eq :k (table-alist '{prefix}-tbl (w state))))))"
            f"    `(make-event"
            f"       '(progn"
            f"          (defconst {c_name} ',pair)"
            f"          (defun {fn_name} (x) (+ (car {c_name}) {dep_expr}))))))"
        )
        val5 = const_val + dep_val_at_5

    elif variant == "pkg_symbol_defconst" and pkg_name:
        # Uses a symbol in a portcullis-defined package inside an elided defconst!
        forms.append(
            f"(make-event '(progn"
            f"  (defconst {c_name} '({pkg_name}::tag . {const_val}))"
            f"  (defun {fn_name} (x)"
            f"    (if (eq (car {c_name}) '{pkg_name}::tag)"
            f"        (+ (cdr {c_name}) {dep_expr})"
            f"      -999))))"
        )
        val5 = const_val + dep_val_at_5

    else:
        # Local helper lemma + skip-proofs-free theorem + defconst
        forms.append(f"(local (defthm {prefix}-loc-thm (equal (+ (ifix x) 0) (ifix x))))")
        forms.append(f"(defconst {c_name} '({const_val} . 99))")
        forms.append(f"(defun {fn_name} (x) (+ (car {c_name}) {dep_expr}))")
        forms.append(
            f"(defthm {prefix}-main-thm"
            f"  (equal ({fn_name} 0) (let ((x 0)) (+ {const_val} {dep_expr})))"
            f"  :rule-classes nil)"
        )
        val5 = const_val + dep_val_at_5

    return forms, fn_name, val5


def generate_dag_scenario(sid: int, rng: random.Random) -> Tuple[List[BookNode], str, str]:
    """
    Returns (nodes_in_topo_order, cert_schedule_kind, load_compiled_mode).
    """
    topo_shape = rng.choice(["chain2", "chain3", "diamond4"])
    use_pkg = rng.random() < 0.30
    pkg_name = f"W4PKG{sid}" if use_pkg else None

    variants = [
        "progn_defconst_me",
        "encap_empty_defconst_me",
        "constrained_encap_and_sk",
        "nested_make_event_table",
        "plain_local_thm",
    ]
    if pkg_name:
        variants.append("pkg_symbol_defconst")

    def pick_cert_mode(allow_acl2x: bool = True) -> str:
        choices = ["normal", "pcert", "pcert"]
        if allow_acl2x:
            choices.extend(["acl2x_normal", "acl2x_pcert"])
        return rng.choice(choices)

    nodes: List[BookNode] = []

    c0 = rng.randint(1, 20)
    v0 = rng.choice(variants)
    b0_forms, b0_fn, b0_v5 = make_body_variant(v0, f"s{sid}-b0", c0, "(ifix x)", 5, pkg_name)
    nodes.append(
        BookNode(
            name="b0",
            includes=[],
            body_forms=b0_forms,
            cert_mode=pick_cert_mode(),
            save_expansion=rng.choice([True, False]),
            use_pkg_portcullis=bool(pkg_name),
            pkg_name=pkg_name,
            expected_fn=b0_fn,
            expected_val_at_5=b0_v5,
        )
    )

    if topo_shape == "chain2":
        b1_local_inc = rng.choice([True, False])
        c1 = rng.randint(1, 20)
        v1 = rng.choice(variants)
        dep_expr = "(ifix x)" if b1_local_inc else f"({b0_fn} x)"
        dep_v5 = 5 if b1_local_inc else b0_v5
        b1_forms, b1_fn, b1_v5 = make_body_variant(v1, f"s{sid}-b1", c1, dep_expr, dep_v5, pkg_name)
        if b1_local_inc:
            b1_forms.insert(0, f"(local (defthm s{sid}-use-b0 (integerp ({b0_fn} x))))")
        nodes.append(
            BookNode(
                name="b1",
                includes=[("b0", b1_local_inc)],
                body_forms=b1_forms,
                cert_mode=pick_cert_mode(),
                save_expansion=rng.choice([True, False]),
                use_pkg_portcullis=bool(pkg_name),
                pkg_name=pkg_name,
                expected_fn=b1_fn,
                expected_val_at_5=b1_v5,
            )
        )

    elif topo_shape == "chain3":
        l1 = rng.choice([True, False])
        c1 = rng.randint(1, 20)
        dep1 = "(ifix x)" if l1 else f"({b0_fn} x)"
        dv1 = 5 if l1 else b0_v5
        b1_forms, b1_fn, b1_v5 = make_body_variant(
            rng.choice(variants), f"s{sid}-b1", c1, dep1, dv1, pkg_name
        )
        nodes.append(
            BookNode(
                name="b1",
                includes=[("b0", l1)],
                body_forms=b1_forms,
                cert_mode=pick_cert_mode(),
                save_expansion=rng.choice([True, False]),
                use_pkg_portcullis=bool(pkg_name),
                pkg_name=pkg_name,
                expected_fn=b1_fn,
                expected_val_at_5=b1_v5,
            )
        )
        l2 = rng.choice([True, False])
        c2 = rng.randint(1, 20)
        dep2 = "(ifix x)" if l2 else f"({b1_fn} x)"
        dv2 = 5 if l2 else b1_v5
        b2_forms, b2_fn, b2_v5 = make_body_variant(
            rng.choice(variants), f"s{sid}-b2", c2, dep2, dv2, pkg_name
        )
        nodes.append(
            BookNode(
                name="b2",
                includes=[("b1", l2)],
                body_forms=b2_forms,
                cert_mode=pick_cert_mode(),
                save_expansion=rng.choice([True, False]),
                use_pkg_portcullis=bool(pkg_name),
                pkg_name=pkg_name,
                expected_fn=b2_fn,
                expected_val_at_5=b2_v5,
            )
        )

    else:  # diamond4: b0 -> {b1, b2} -> b3
        c1 = rng.randint(1, 20)
        b1_forms, b1_fn, b1_v5 = make_body_variant(
            rng.choice(variants), f"s{sid}-b1", c1, f"({b0_fn} x)", b0_v5, pkg_name
        )
        nodes.append(
            BookNode(
                name="b1",
                includes=[("b0", False)],
                body_forms=b1_forms,
                cert_mode=pick_cert_mode(),
                save_expansion=rng.choice([True, False]),
                use_pkg_portcullis=bool(pkg_name),
                pkg_name=pkg_name,
                expected_fn=b1_fn,
                expected_val_at_5=b1_v5,
            )
        )
        l2 = rng.choice([True, False])
        c2 = rng.randint(1, 20)
        dep2 = "(ifix x)" if l2 else f"({b0_fn} x)"
        dv2 = 5 if l2 else b0_v5
        b2_forms, b2_fn, b2_v5 = make_body_variant(
            rng.choice(variants), f"s{sid}-b2", c2, dep2, dv2, pkg_name
        )
        nodes.append(
            BookNode(
                name="b2",
                includes=[("b0", l2)],
                body_forms=b2_forms,
                cert_mode=pick_cert_mode(),
                save_expansion=rng.choice([True, False]),
                use_pkg_portcullis=bool(pkg_name),
                pkg_name=pkg_name,
                expected_fn=b2_fn,
                expected_val_at_5=b2_v5,
            )
        )
        l3_b2 = rng.choice([True, False])
        c3 = rng.randint(1, 20)
        dep3 = f"({b1_fn} x)" if l3_b2 else f"(+ ({b1_fn} x) ({b2_fn} x))"
        dv3 = b1_v5 if l3_b2 else (b1_v5 + b2_v5)
        b3_forms, b3_fn, b3_v5 = make_body_variant(
            rng.choice(variants), f"s{sid}-b3", c3, dep3, dv3, pkg_name
        )
        nodes.append(
            BookNode(
                name="b3",
                includes=[("b1", False), ("b2", l3_b2)],
                body_forms=b3_forms,
                cert_mode=pick_cert_mode(),
                save_expansion=rng.choice([True, False]),
                use_pkg_portcullis=bool(pkg_name),
                pkg_name=pkg_name,
                expected_fn=b3_fn,
                expected_val_at_5=b3_v5,
            )
        )

    convert_order = rng.choice(["topo", "reverse_topo"])
    load_compiled = rng.choice(["t", ":comp", "nil"])
    return nodes, convert_order, load_compiled


def materialize_and_build_commands(
    dag_dir: str,
    sid: int,
    nodes: Sequence[BookNode],
    convert_order: str,
    load_compiled: str,
) -> str:
    """
    Writes the `.lisp` book files into `dag_dir` and returns the ACL2 command sequence
    that certifies the entire DAG (with `:pcert` / `.acl2x` / portcullis) and then
    verifies inclusion + evaluation + soundness from a clean `:ubu 0` world.
    """
    os.makedirs(dag_dir, exist_ok=True)
    for node in nodes:
        bpath = os.path.join(dag_dir, f"{node.name}.lisp")
        blines = ['(in-package "ACL2")']
        for inc_name, is_local in node.includes:
            if is_local:
                blines.append(f'(local (include-book "{inc_name}"))')
            else:
                blines.append(f'(include-book "{inc_name}")')
        blines.extend(node.body_forms)
        with open(bpath, "w") as f:
            f.write("\n".join(blines) + "\n")

    cmds: List[str] = []

    def emit_reset_world() -> str:
        return "(mv-let (erp val state) (ubt! 1) (declare (ignore erp val)) (value :reset-ok))"

    def emit_portcullis(node: BookNode) -> int:
        if node.use_pkg_portcullis and node.pkg_name:
            cmds.append(f'(defpkg "{node.pkg_name}" \'(nil t quote))')
            return 1
        return 0

    def wrap_cert_step(step_tag: str, cert_expr: str) -> str:
        return (
            f"(mv-let (erp val state) {cert_expr}"
            f"  (declare (ignore val))"
            f"  (if erp"
            f"      (prog2$ (cw \"~%!!!W4-KF-PCERT-UNEXPECTED-ERR [{step_tag}]~%\")"
            f"              (value :err))"
            f"    (value :ok)))"
        )

    # Phase 1: Initial pass (`normal`, `:pcert :create`, `.acl2x` write + `:pcert :create` / `normal`)
    for node in nodes:
        full_prefix = f"{dag_dir}/{node.name}"
        save_flag = "t" if node.save_expansion else "nil"
        cmds.append(f"(f-put-global 'save-expansion-file {save_flag} state)")

        if node.cert_mode in ("acl2x_normal", "acl2x_pcert"):
            cmds.append(emit_reset_world())
            k = emit_portcullis(node)
            cmds.append("(set-write-acl2x t state)")
            cmds.append(
                wrap_cert_step(
                    f"S{sid}-{node.name}-acl2x-write",
                    f'(certify-book "{full_prefix}" {k} t :acl2x t)',
                )
            )
            cmds.append("(set-write-acl2x nil state)")

        cmds.append(emit_reset_world())
        k = emit_portcullis(node)
        acl2x_kw = " :acl2x t" if node.cert_mode in ("acl2x_normal", "acl2x_pcert") else ""
        if node.cert_mode in ("normal", "acl2x_normal"):
            cmds.append(
                wrap_cert_step(
                    f"S{sid}-{node.name}-cert",
                    f'(certify-book "{full_prefix}" {k} t{acl2x_kw})',
                )
            )
        else:
            cmds.append(
                wrap_cert_step(
                    f"S{sid}-{node.name}-pcert-create",
                    f'(certify-book "{full_prefix}" {k} t :pcert :create{acl2x_kw})',
                )
            )

    # Phase 2: `:pcert :convert` on all provisional nodes (either topo or reverse-topo!)
    pcert_nodes = [n for n in nodes if n.cert_mode in ("pcert", "acl2x_pcert")]
    conv_seq = list(reversed(pcert_nodes)) if convert_order == "reverse_topo" else pcert_nodes
    for node in conv_seq:
        full_prefix = f"{dag_dir}/{node.name}"
        save_flag = "t" if node.save_expansion else "nil"
        cmds.append(f"(f-put-global 'save-expansion-file {save_flag} state)")
        cmds.append(emit_reset_world())
        k = emit_portcullis(node)
        acl2x_kw = " :acl2x t" if node.cert_mode == "acl2x_pcert" else ""
        cmds.append(
            wrap_cert_step(
                f"S{sid}-{node.name}-pcert-convert",
                f'(certify-book "{full_prefix}" {k} t :pcert :convert{acl2x_kw})',
            )
        )

    # Phase 3: `:pcert :complete` in topological order (so sub-books have `.cert` first)
    for node in pcert_nodes:
        full_prefix = f"{dag_dir}/{node.name}"
        cmds.append(emit_reset_world())
        k = emit_portcullis(node)
        acl2x_kw = " :acl2x t" if node.cert_mode == "acl2x_pcert" else ""
        cmds.append(
            wrap_cert_step(
                f"S{sid}-{node.name}-pcert-complete",
                f'(certify-book "{full_prefix}" {k} t :pcert :complete{acl2x_kw})',
            )
        )

    # Phase 4: Clean-world inclusion under requested `:load-compiled-file` mode + value & soundness check
    top = nodes[-1]
    top_prefix = f"{dag_dir}/{top.name}"
    cmds.append("(f-put-global 'save-expansion-file nil state)")
    cmds.append(emit_reset_world())
    cmds.append(
        wrap_cert_step(
            f"S{sid}-{top.name}-include-{load_compiled}",
            f'(include-book "{top_prefix}" :load-compiled-file {load_compiled})',
        )
    )
    cmds.append(
        f"(make-event"
        f"  (let ((actual ({top.expected_fn} 5)))"
        f"    (if (equal actual {top.expected_val_at_5})"
        f"        (value '(value-triple :eval-ok))"
        f"      (prog2$ (cw \"~%!!!W4-KF-PCERT-EVAL-MISMATCH [S{sid}]: got ~x0 expected {top.expected_val_at_5}~%\" actual)"
        f"              (value '(value-triple :eval-mismatch))))))"
    )
    cmds.append(
        f"(make-event"
        f"  (mv-let (erp val state)"
        f"    (with-output :off :all (thm nil))"
        f"    (declare (ignore val))"
        f"    (if erp"
        f"        (value '(value-triple :sound))"
        f"      (prog2$ (cw \"~%!!!W4-KF-PCERT-SOUNDNESS-BUG [S{sid}]~%\")"
        f"              (value '(value-triple :unsound))))))"
    )
    cmds.append(emit_reset_world())
    return "\n".join(cmds)


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
        m = pat.search(out)
        if m:
            s = max(0, m.start() - 120)
            e = min(len(out), m.end() + 320)
            issues.append(f"MATCH[{pat.pattern}]: {out[s:e].strip()}")
    if marker not in out:
        issues.append(f"MISSING_MARKER[{marker}]")
    return issues


def main() -> int:
    ap = argparse.ArgumentParser(description="Wave-4 §5.2 Provisional Certification & Book-DAG Fuzzer")
    ap.add_argument("--acl2", default=DEFAULT_SBCL_ACL2, help="Path to saved_acl2 binary")
    ap.add_argument("--seed", type=int, default=20261114, help="RNG seed")
    ap.add_argument("--batches", type=int, default=8, help="Number of multi-DAG batches")
    ap.add_argument("--dags-per-batch", type=int, default=8, help="Independent book DAGs per batch")
    ap.add_argument("--timeout", type=int, default=60, help="Per-batch timeout in seconds")
    ap.add_argument("--save-anomaly-dir", default="", help="Optional directory to preserve anomalous DAGs")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    root_tmp = tempfile.mkdtemp(prefix="w4-kf-pcert-")

    total_dags = 0
    total_books = 0
    anomalies = 0

    try:
        print(f"[fuzz_pcert_bookgraph] acl2={args.acl2} seed={args.seed} tmp={root_tmp}")
        for b in range(args.batches):
            batch_dir = os.path.join(root_tmp, f"batch_{b}")
            os.makedirs(batch_dir, exist_ok=True)
            batch_cmds = [
                '(in-package "ACL2")',
                '(set-inhibit-warnings "theory" "free" "non-rec" "guards")',
            ]
            books_in_batch = 0
            for d in range(args.dags_per_batch):
                sid = b * args.dags_per_batch + d
                nodes, conv_order, load_comp = generate_dag_scenario(sid, rng)
                dag_dir = os.path.join(batch_dir, f"dag_{sid}")
                dag_script = materialize_and_build_commands(dag_dir, sid, nodes, conv_order, load_comp)
                batch_cmds.append(dag_script)
                total_dags += 1
                books_in_batch += len(nodes)
                total_books += len(nodes)

            marker = f"W4-KF-PCERT-BATCH-{b}-COMPLETE"
            batch_cmds.append(f'(cw "~%{marker}~%")\n:q\n')
            full_script = "\n\n".join(batch_cmds)

            rc, out = run_acl2_script(args.acl2, full_script, timeout_sec=args.timeout)
            issues = check_anomalies(rc, out, marker)
            print(
                f"  [pcert batch {b + 1}/{args.batches}] dags={args.dags_per_batch} "
                f"books={books_in_batch} rc={rc} issues={len(issues)}"
            )
            if issues:
                anomalies += len(issues)
                for iss in issues:
                    print(f"    ! ANOMALY: {iss}")
                if args.save_anomaly_dir:
                    dst = os.path.join(args.save_anomaly_dir, f"pcert_batch_{b}")
                    shutil.copytree(batch_dir, dst, dirs_exist_ok=True)
                    with open(os.path.join(dst, "driver.lsp"), "w") as f:
                        f.write(full_script)
                    with open(os.path.join(dst, "driver.out"), "w") as f:
                        f.write(out)
            else:
                shutil.rmtree(batch_dir, ignore_errors=True)

        print(
            f"[fuzz_pcert_bookgraph] SUMMARY: dags={total_dags} "
            f"books_certified={total_books} anomalies={anomalies}"
        )
        return 1 if anomalies else 0
    finally:
        shutil.rmtree(root_tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
