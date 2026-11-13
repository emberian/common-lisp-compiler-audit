#!/usr/bin/env python3
import argparse
import json
from pathlib import Path

from lisprun import run
from semantics import AuditError, eval_term, render_results, render_term

def tuple_tree(value):
    return tuple(tuple_tree(item) for item in value) if isinstance(value, list) else value

def replace_test(test, form):
    updated = dict(test)
    updated["ast"] = form
    updated["form"] = render_term(form)
    try:
        updated["expected"] = render_results(eval_term(form, test["args"]))
    except AuditError:
        updated["expected"] = "(:ERROR)"
    return updated

def candidates(test):
    form = test["ast"]
    if not isinstance(form, tuple) or not form:
        return []
    op = form[0]
    out = []
    if op == "if" and len(form) == 4:
        out.extend((form[2], form[3]))
    if op == "let" and len(form) == 4:
        out.extend((form[2], form[3]))
    for index, child in enumerate(form[1:], 1):
        if isinstance(child, tuple):
            out.append(child)
            if child and child[0] == "var" and child[1] in test["args"]:
                out.append(test["args"][child[1]])
        elif isinstance(child, int) and index > 0:
            for value in (0, 1, -1, child - 1, child + 1):
                modified = list(form)
                modified[index] = value
                out.append(tuple(modified))
    return [replace_test(test, candidate) for candidate in out]

def mismatch(test, implementations, workdir):
    return any(run([test], implementation, workdir)[test["id"]].upper() !=
               test["expected"].upper()
               for implementation in implementations)

def minimize(test, implementations, workdir):
    current = test
    changed = True
    while changed:
        changed = False
        for candidate in candidates(current):
            if candidate["form"] == current["form"]:
                continue
            if mismatch(candidate, implementations, workdir):
                current = candidate
                changed = True
                break
    return current

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mismatches")
    parser.add_argument("--implementations", required=True)
    parser.add_argument("--workdir", default="audit-shrink")
    args = parser.parse_args()
    workdir = Path(args.workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    implementations = args.implementations.split(",")
    with (workdir / "minimized.jsonl").open("w") as output:
        for line in Path(args.mismatches).read_text().splitlines():
            record = json.loads(line)
            if record["implementation"] not in implementations:
                continue
            test = record["test"]
            test["ast"] = tuple_tree(test["ast"])
            minimized = minimize(test, implementations, workdir)
            record["test"] = minimized
            record["actual"] = run([minimized], implementations[0], workdir)[minimized["id"]]
            output.write(json.dumps(record) + "\n")
            output.flush()
            print(json.dumps({"id": minimized["id"], "form": minimized["form"]}))

if __name__ == "__main__":
    main()
