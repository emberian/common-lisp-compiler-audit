#!/usr/bin/env python3
"""Compositional whole-program differential campaign.

Enumerates typed multi-function programs over the structure x type x guard x
flavor axis product, admits each into both ACL2 images (SBCL-built and
CCL-built), and evaluates a battery of call terms in three phases:

  logical  -- ev-fncall-rec-logical (the logic-world value; functions total)
  compiled -- host COMPILE of the admitted definition
  raw      -- funcall of the compiled definition

Every guard-satisfying term is compared against the independent Python
oracle; every term is compared across images.  Guard-violating terms are
compared across images only (the oracle does not model total ACL2
semantics for primitive misuse).
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import random
import unicodedata
import re
import subprocess
import sys

from programgen import (
    enumerate_programs, is_recursive, render_acl2, render_const,
    term_battery, coverage_table,
)
import acl2run


HARNESS_DIR = Path(__file__).resolve().parent
BATCH_PROGRAMS = 20


def _prefix_for(index, prog_id):
    stem = re.sub(r"[^A-Za-z0-9-]", "-", prog_id)
    return f"PG{index:03d}-{stem[:24]}-"


def _case_source(index, fn_name, term):
    args = " ".join(render_const(a) for a in term["args"])
    name = acl2run._function_name(index)
    return name, f"(defun {name} ()\n  ({fn_name} {args}))\n"


def write_batch(batch_index, programs, seed, workdir):
    """Write one batch script; returns (script_path, tests, layout)."""
    # Correct layout: program events in the loop, then for EACH case its
    # defun in the loop, :q, probe call, (lp).  The probe itself is raw
    # Lisp defined once after the first :q.
    chunks = [
        '(in-package "ACL2")\n',
        "(set-guard-checking :none)\n",
        "(set-ignore-ok t)\n",
        "(set-irrelevant-formals-ok t)\n",
    ]
    tests = []
    case_sources = []
    case_index = 0
    for pindex, program in enumerate(programs):
        prefix = _prefix_for(pindex, program.prog_id)
        chunks.append(render_acl2(program, prefix=prefix))
        battery = term_battery(
            program, random.Random(hash((seed, pindex)) & 0xFFFFFFFF),
            ok_per_fn=4, violating_per_fn=1)
        for term in battery:
            fn_name = f"{prefix}PROG-F{term['fn']}"
            name, source = _case_source(case_index, fn_name, term)
            tests.append({
                "id": term["id"],
                "form": f"({fn_name} {' '.join(render_const(a) for a in term['args'])})",
                "class": term["class"],
                "oracle": term["oracle"],
                "program": program.prog_id,
                "fn": term["fn"],
                "case_fn": name,
            })
            probe = ("acl2run-run-case-logical" if term["class"] == "violating"
                     else "acl2run-run-case")
            case_sources.append(
                f";; case {term['id']} [{term['class']}]\n"
                f"{source}"
                f":q\n"
                f"({probe} {acl2run._lisp_string(term['id'])} '{name})\n"
                f"(lp)\n"
            )
            case_index += 1
    body = "".join(chunks) + ":q\n" + acl2run.RAW_PROBE + "(lp)\n" \
        + "".join(case_sources) + "(quit)\n"
    script_path = workdir / f"batch-{batch_index:03d}.lisp"
    script_path.write_text(body, encoding="utf-8")
    return script_path, tests


def run_batch(script_path, tests, implementations, timeout):
    results = {}
    for impl in implementations:
        results[impl] = acl2run.run_script(
            tests, script_path, impl, timeout=timeout)
    return results


def analyze(tests, image_results):
    """Compare oracle, phases and images; return (rows, summary)."""
    rows = []
    summary = Counter()
    for test in tests:
        tid = test["id"]
        row = {
            "id": tid, "program": test["program"], "fn": test["fn"],
            "class": test["class"], "form": test["form"],
            "oracle": test["oracle"],
        }
        issues = []
        values = {}
        for impl, result in image_results.items():
            obs = result.get("results", {}).get(tid, {})
            logical = obs.get("logical", {})
            raw = obs.get("raw", {})
            compile_rec = obs.get("compile", {})
            event = obs.get("event", {})
            row[f"{impl}.event"] = event.get("status")
            row[f"{impl}.logical"] = logical.get("status")
            row[f"{impl}.logical_value"] = logical.get("value")
            row[f"{impl}.compile"] = compile_rec.get("status")
            row[f"{impl}.raw"] = raw.get("status")
            row[f"{impl}.raw_value"] = raw.get("value")
            if event.get("status") != "admitted":
                issues.append(f"{impl}:event_failure")
                continue
            if compile_rec.get("status") == "host_compilation_failure":
                issues.append(f"{impl}:host_compilation_failure")
            if logical.get("status") != "value":
                if test["class"] == "ok":
                    issues.append(f"{impl}:logical_error")
            else:
                values.setdefault("logical", {})[impl] = logical.get("value")
            if raw.get("status") == "value":
                values.setdefault("raw", {})[impl] = raw.get("value")
            elif raw.get("status") in ("raw_error", "raw_guard_crash"):
                if test["class"] == "ok":
                    issues.append(f"{impl}:{raw.get('status')}")
        # oracle checks (ok terms only, value phases only)
        if test["class"] == "ok":
            for phase in ("logical", "raw"):
                got = values.get(phase, {})
                for impl, value in got.items():
                    if _normalize(value) != _normalize(test["oracle"]):
                        issues.append(f"{phase}_oracle_mismatch:{impl}")
        # cross-image checks
        for phase in ("logical", "raw"):
            got = values.get(phase, {})
            distinct = {_normalize(v) for v in got.values()}
            if len(distinct) > 1:
                issues.append(f"{phase}_cross_image_disagreement")
        row["issues"] = sorted(issues)
        if issues:
            summary["flagged"] += 1
            summary["flagged:" + row["issues"][0].split(":")[0]] += 1
        else:
            summary["clean"] += 1
        rows.append(row)
    return rows, dict(summary)


_CHAR_TOKEN = re.compile(r"#\\([A-Za-z_][A-Za-z_0-9]*|.)")


def _canonical_char(match):
    token = match.group(1)
    name = token.replace("_", " ")
    try:
        ch = unicodedata.lookup(name)
    except KeyError:
        ch = token if len(token) == 1 else None
    if ch is None:
        return "\x00CHAR\x00" + token
    return "\x00CHAR\x00" + unicodedata.name(ch).title()


def _normalize(value):
    if value is None:
        return None
    text = str(value).strip()
    # canonicalize character tokens first (case-preserving, guarded by a
    # sentinel so the uppercase pass cannot touch them), then uppercase
    text = _CHAR_TOKEN.sub(_canonical_char, text)
    text = text.upper()
    text = text.replace("\x00CHAR\x00", "#\\")
    # unify rational spellings: 3/1 -> 3
    text = re.sub(r"(-?\d+)/1\b", r"\1", text)
    return text


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--limit", type=int, default=20,
                        help="number of programs (axis cells) to sweep")
    parser.add_argument("--offset", type=int, default=0)
    parser.add_argument("--stride", type=int, default=1,
                        help="take every Nth program from the axis product")
    parser.add_argument("--seed", type=int, default=0)
    parser.add_argument("--batch-size", type=int, default=BATCH_PROGRAMS)
    parser.add_argument("--timeout", type=int, default=1800)
    parser.add_argument("--workdir",
                        default=str(HARNESS_DIR / "program-campaign"))
    parser.add_argument("--implementations", default="sbcl,ccl")
    args = parser.parse_args()

    workdir = Path(args.workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    axis = enumerate_programs(seed=args.seed)
    programs = axis[args.offset::args.stride][:args.limit]
    if not programs:
        parser.error("no programs selected")
    (workdir / "coverage.json").write_text(
        json.dumps(coverage_table(programs), indent=2) + "\n")

    implementations = tuple(args.implementations.split(","))
    all_rows = []
    total_summary = Counter()
    batches = [programs[i:i + args.batch_size]
               for i in range(0, len(programs), args.batch_size)]
    for bindex, batch in enumerate(batches):
        script_path, tests = write_batch(bindex, batch, args.seed, workdir)
        image_results = run_batch(script_path, tests, implementations,
                                  args.timeout)
        for impl, res in image_results.items():
            (workdir / f"batch-{bindex:03d}-{impl}.log").write_text(
                res.get("stdout", "") + "\n--- STDERR ---\n" + res.get("stderr", ""),
                encoding="utf-8")
        rows, summary = analyze(tests, image_results)
        all_rows.extend(rows)
        total_summary.update(summary)
        protocol = {impl: len(res.get("protocol_errors", []))
                    for impl, res in image_results.items()}
        print(f"batch {bindex}: {len(batch)} programs, {len(tests)} cases, "
              f"summary={summary}, protocol_errors={protocol}", flush=True)
        for res in image_results.values():
            if res["status"] != "ok":
                print(f"  !! image status {res['status']}: "
                      f"{res.get('error', '')}", flush=True)

    with (workdir / "results.jsonl").open("w") as stream:
        for row in all_rows:
            stream.write(json.dumps(row) + "\n")
    flagged = [row for row in all_rows if row["issues"]]
    with (workdir / "flagged.jsonl").open("w") as stream:
        for row in flagged:
            stream.write(json.dumps(row) + "\n")
    summary = {
        "programs": len(programs),
        "cases": len(all_rows),
        "recursive_programs": sum(map(is_recursive, programs)),
        **{k: v for k, v in total_summary.items()},
        "coverage": coverage_table(programs),
        "workdir": str(workdir),
    }
    (workdir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 1 if flagged else 0


if __name__ == "__main__":
    raise SystemExit(main())
