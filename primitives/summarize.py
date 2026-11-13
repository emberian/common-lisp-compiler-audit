#!/usr/bin/env python3
"""summarize.py RESULTS_DIR [ACL2_SOURCE_DIR]

Aggregates results/<image>/summary.tsv for every image directory found, compares
the per-function logical digests across images, and (if a source directory is
given) tags every swept function with whether its ACL2 source definition has
separate raw Lisp code (a #-acl2-loop-only / #+acl2-loop-only conditional inside
the defun, or a definition that exists only under #+acl2-loop-only).

Writes RESULTS_DIR/SUMMARY.txt and RESULTS_DIR/dual-definitions.tsv.
"""
import glob, os, re, sys

ROUTES = ["none", "prim", "t", "raw"]
KINDS = ["agree", "agree_err", "mismatch", "act_err", "log_err"]
COLS = (["fn", "arity", "nvals", "class", "rawkind", "status", "tuples",
         "l_val", "l_err", "l_depth", "l_timeout",
         "g_true", "g_false", "g_err", "guard_div", "sub_guard", "act_timeouts"]
        + [f"{r}_{k}" for r in ROUTES for k in KINDS]
        + ["digest_l", "digest_a", "ms"])
NUM = COLS[6:-3] + ["ms"]


def read_summary(path):
    rows = {}
    with open(path, encoding="latin-1") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            row = dict(zip(COLS, parts))
            for c in COLS:
                row.setdefault(c, "0" if c in NUM else "-")
            for c in NUM:
                try:
                    row[c] = int(row[c])
                except ValueError:
                    row[c] = 0
            rows[row["fn"]] = row
    return rows


DEF_RE = re.compile(r"^\((defun|defund|defun-inline|defund-inline|defun-one-output|defun-nx|"
                    r"defun-with-guard-check|defun-overrides|defun-notinline)\s+([^\s()]+)")


def scan_sources(srcdir):
    """name -> set of tags.  Heuristic, textual: top-level forms start at column 0."""
    tags = {}
    for path in sorted(glob.glob(os.path.join(srcdir, "*.lisp"))):
        if os.path.basename(path) in ("doc.lisp",):
            continue
        with open(path, encoding="latin-1") as f:
            lines = f.read().split("\n")
        starts = [i for i, l in enumerate(lines) if l.startswith("(")]
        for k, i in enumerate(starts):
            m = DEF_RE.match(lines[i])
            if not m:
                continue
            end = starts[k + 1] if k + 1 < len(starts) else len(lines)
            body = "\n".join(lines[i:end])
            # the feature conditional guarding the whole form, if any
            j = i - 1
            while j >= 0 and lines[j].strip() == "":
                j -= 1
            prev = lines[j].strip() if j >= 0 else ""
            name = m.group(2).upper()
            t = tags.setdefault(name, set())
            if prev.startswith("#+acl2-loop-only"):
                t.add("logic-only-form")
            elif prev.startswith("#-acl2-loop-only"):
                t.add("raw-only-form")
            if "acl2-loop-only" in body:
                t.add("raw-conditional-inside")
    return tags


def main():
    resdir = sys.argv[1]
    srcdir = sys.argv[2] if len(sys.argv) > 2 else None
    images = {}
    for p in sorted(glob.glob(os.path.join(resdir, "*", "summary.tsv"))):
        images[os.path.basename(os.path.dirname(p))] = read_summary(p)
    out = []
    tags = scan_sources(srcdir) if srcdir else {}

    def dual(fn):
        base = fn.strip("|")
        for cand in (base, base.replace("$INLINE", ""), base.replace("$NOTINLINE", "")):
            t = tags.get(cand)
            if t and (t & {"logic-only-form", "raw-only-form", "raw-conditional-inside"}):
                return sorted(t)
        return []

    for img, rows in images.items():
        real = {k: v for k, v in rows.items() if not v["status"].startswith("CONTROL")}
        ctl = {k: v for k, v in rows.items() if v["status"].startswith("CONTROL")}
        out.append(f"== {img} ==")
        meta = os.path.join(resdir, img, "meta.txt")
        if os.path.exists(meta):
            for line in open(meta, encoding="latin-1"):
                if line.startswith(("host", "acl2", "qualifying", "excluded", "universe-size",
                                    "function-symbols", "depth-bound", "MODEL", "reader", "binary-")):
                    out.append("  " + line.rstrip())
        st = {}
        for v in real.values():
            st[v["status"]] = st.get(v["status"], 0) + 1
        out.append(f"  functions swept: {len(real)}  by status: {st}")
        by_ar = {}
        for v in real.values():
            by_ar[v["arity"]] = by_ar.get(v["arity"], 0) + 1
        out.append(f"  by arity: {dict(sorted(by_ar.items()))}")
        tot = {c: sum(v[c] for v in real.values()) for c in NUM}
        out.append(f"  tuples evaluated: {tot['tuples']}")
        out.append(f"  logical outcome: value {tot['l_val']}, error {tot['l_err']}, "
                   f"depth-bounded {tot['l_depth']}, timed out {tot['l_timeout']}")
        names = {"none": "*1* with guard-checking :none (every non-bounded tuple)",
                 "prim": "raw apply$-prim dispatch, guard-checking :none (apply$ primitives only)",
                 "t": "*1* with guard-checking t (guard holds)",
                 "raw": "raw function (guard holds, guard-verified)"}
        for r in ROUTES:
            n = sum(tot[f"{r}_{k}"] for k in KINDS)
            out.append(f"  {names[r]}: compared {n}")
            out.append(f"      equal values {tot[r + '_agree']}, neither side a value "
                       f"{tot[r + '_agree_err']}, VALUE MISMATCH {tot[r + '_mismatch']}, "
                       f"actual aborted {tot[r + '_act_err']}, "
                       f"logical evaluator had no value {tot[r + '_log_err']}")
        out.append(f"  guard: true {tot['g_true']}, false {tot['g_false']}, undetermined "
                   f"{tot['g_err']}; logical guard vs *1* guard check disagree: {tot['guard_div']}")
        out.append(f"  guard error raised for a callee although the guard holds (ec-call / "
                   f":ideal; not a value): {tot['sub_guard']}")
        out.append(f"  actual-side timeouts: {tot['act_timeouts']}")
        if srcdir:
            nd = sum(1 for k in real if dual(k))
            out.append(f"  swept functions whose source has separate raw Lisp code: {nd}")
        for kind, title in (("mismatch", "functions with a VALUE MISMATCH"),
                            ("act_err", "functions where the actual side aborted but the logic has a value"),
                            ("log_err", "functions the logical evaluator could not evaluate (actual has a value)")):
            out.append(f"  {title}:")
            for k, v in real.items():
                c = [v[f"{r}_{kind}"] for r in ROUTES]
                if any(c):
                    out.append(f"    {k}/{v['arity']} none={c[0]} prim={c[1]} t={c[2]} raw={c[3]}")
        out.append("  functions where logical guard and *1* guard check disagree:")
        for k, v in real.items():
            if v["guard_div"]:
                out.append(f"    {k}/{v['arity']} {v['guard_div']}")
        out.append("  functions not fully swept, or with bounded tuples:")
        for k, v in real.items():
            if v["status"] != "OK":
                out.append(f"    {k}/{v['arity']} {v['status']} after {v['tuples']} tuples")
        bounded = [(v["l_depth"] + v["l_timeout"] + v["act_timeouts"], k, v) for k, v in real.items()
                   if v["l_depth"] + v["l_timeout"] + v["act_timeouts"]]
        out.append(f"    {len(bounded)} functions have depth-bounded or timed-out tuples "
                   f"(see bounded.tsv)")
        with open(os.path.join(resdir, img, "bounded.tsv"), "w") as f:
            f.write("fn\tarity\ttuples\tlogical_depth_bounded\tlogical_timeout\tactual_timeout\n")
            for _, k, v in sorted(bounded, key=lambda x: -x[0]):
                f.write(f"{k}\t{v['arity']}\t{v['tuples']}\t{v['l_depth']}\t{v['l_timeout']}\t"
                        f"{v['act_timeouts']}\n")
        out.append("  controls:")
        for k, v in ctl.items():
            out.append(f"    {k}: tuples={v['tuples']} mismatch none={v['none_mismatch']} "
                       f"prim={v['prim_mismatch']} t={v['t_mismatch']} raw={v['raw_mismatch']} "
                       f"guard_div={v['guard_div']}")
        out.append("")

    names = list(images)
    if len(names) >= 2:
        a, b = images[names[0]], images[names[1]]
        common = [k for k in a if k in b]
        same = diff = skipped = 0
        diffs = []
        for k in common:
            ra, rb = a[k], b[k]
            if ra["status"] != rb["status"] or "OK" not in ra["status"] or \
               ra["l_timeout"] or rb["l_timeout"]:
                skipped += 1
                continue
            if ra["digest_l"] == rb["digest_l"]:
                same += 1
            else:
                diff += 1
                diffs.append(k)
        out.append(f"== logical digests, {names[0]} vs {names[1]} ==")
        out.append(f"  functions in both: {len(common)}; only in {names[0]}: "
                   f"{len([k for k in a if k not in b])}; only in {names[1]}: "
                   f"{len([k for k in b if k not in a])}")
        out.append(f"  identical logical digest: {same}; different: {diff}; "
                   f"not comparable (partial/crashed/timeouts): {skipped}")
        for k in diffs:
            out.append(f"    DIFFERENT {k}/{a[k]['arity']}: {a[k]['digest_l']} vs {b[k]['digest_l']}")
        adiff = [k for k in common if a[k]["digest_a"] != b[k]["digest_a"]
                 and a[k]["status"] == b[k]["status"] and "OK" in a[k]["status"]
                 and not (a[k]["act_timeouts"] or b[k]["act_timeouts"]
                          or a[k]["l_timeout"] or b[k]["l_timeout"])]
        out.append(f"  *1* (:none) digests different across images: {len(adiff)}")
        for k in adiff:
            out.append(f"    DIFFERENT-ACTUAL {k}/{a[k]['arity']}")
    if srcdir:
        with open(os.path.join(resdir, "dual-definitions.tsv"), "w") as f:
            f.write("fn\tsource_tags\n")
            any_rows = next(iter(images.values())) if images else {}
            for k in any_rows:
                f.write(f"{k}\t{','.join(dual(k)) or '-'}\n")
    # one row per function and image: domain, tuples, result
    with open(os.path.join(resdir, "per-function.tsv"), "w") as f:
        f.write("fn\tarity\tdomain(30^arity)\timage\tstatus\ttuples_swept\tlogical_values\t"
                "bounded(depth+timeout)\tguard_true\tcompared_none\tcompared_t\tcompared_raw\t"
                "value_mismatch\tactual_aborted\tlogical_no_value\tresult\n")
        for img, rows in images.items():
            for k, v in rows.items():
                if v["status"].startswith("CONTROL"):
                    continue
                cmp_ = {r: sum(v[f"{r}_{kd}"] for kd in KINDS) for r in ROUTES}
                mm = sum(v[f"{r}_mismatch"] for r in ROUTES)
                ae = max(v[f"{r}_act_err"] for r in ROUTES)
                le = max(v[f"{r}_log_err"] for r in ROUTES)
                res = ("VALUE-MISMATCH" if mm else "actual-aborts" if ae else
                       "logical-side-unavailable" if le and not v["none_agree"] else
                       "agree" if v["status"] == "OK" else "agree-on-swept-part")
                dom = 30 ** int(v["arity"]) if str(v["arity"]).isdigit() else 0
                f.write(f"{k}\t{v['arity']}\t{dom}\t{img}\t{v['status']}\t{v['tuples']}\t"
                        f"{v['l_val']}\t{v['l_depth'] + v['l_timeout']}\t{v['g_true']}\t"
                        f"{cmp_['none']}\t{cmp_['t']}\t{cmp_['raw']}\t{mm}\t{ae}\t{le}\t{res}\n")
    text = "\n".join(out) + "\n"
    with open(os.path.join(resdir, "SUMMARY.txt"), "w") as f:
        f.write(text)
    sys.stdout.write(text)


if __name__ == "__main__":
    main()
