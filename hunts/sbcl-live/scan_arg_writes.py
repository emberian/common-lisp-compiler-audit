#!/usr/bin/env python3
"""Scan all SBCL 2.6.10 x86-64 and arm64 VOPs for writes directly to :args TNs!"""
import sys
import subprocess
from scan_vops import parse_sexprs, extract_vops_from_form, resolve_inheritance, enumerate_paths

git_dir = sys.argv[1]
tag = sys.argv[2] if len(sys.argv) > 2 else "sbcl-2.6.10"

for arch in ("x86-64", "arm64"):
    ls = subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", tag, f"src/compiler/{arch}/"],
        cwd=git_dir, text=True
    ).splitlines()
    vops = []
    for rel in sorted(ls):
        if not rel.endswith(".lisp"):
            continue
        src = subprocess.check_output(["git", "show", f"{tag}:{rel}"], cwd=git_dir, text=True)
        for f in parse_sexprs(src, rel):
            extract_vops_from_form(f, rel, vops)
    resolve_inheritance(vops)

    print(f"=== {arch}: scanning {len(vops)} VOPs for direct writes to :args TNs ===")
    seen = set()
    for v in vops:
        if not v.generator:
            continue
        arg_names = {a.name for a in v.args}
        known = arg_names | {r.name for r in v.results} | {t.name for t in v.temps}
        if not arg_names:
            continue
        paths = enumerate_paths(list(v.generator), arch, known, set(), max_paths=48)
        for p in paths:
            for kind, var, line, gvars, ctx in p:
                if kind == "write" and var in arg_names:
                    # Check if guarded by (location= var something)
                    is_g = any(var in pair for pair in gvars)
                    key = (v.file, v.line, v.name, var, ctx, is_g)
                    if key not in seen:
                        seen.add(key)
                        print(f"  [{'GUARDED' if is_g else 'ARG-WRITE!'}] {v.file}:{v.line} vop={v.name} tr={v.translate} writes arg `{var}` @L{line}: {ctx}")
