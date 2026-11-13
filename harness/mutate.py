#!/usr/bin/env python3
import argparse
import json
from collections import Counter
from pathlib import Path

from semantics import AuditError, eval_term, render_results, render_term
from shrink import tuple_tree

def with_form(test, form, index):
    try:
        expected = render_results(eval_term(form, test["args"]))
    except AuditError:
        expected = "(:ERROR)"
    return {"id": f"mutation-{index}", "family": "mutation", "ast": form,
            "form": render_term(form), "args": test["args"],
            "declarations": test["declarations"], "expected": expected}

def mutations(test, start):
    form = tuple_tree(test["ast"])
    return [with_form(test, ("mask-signed", 64, form), start),
            with_form(test, ("integer-length", form), start + 1),
            with_form(test, ("mv-list", form), start + 2),
            with_form(test, ("ash", form, ("var", "count")), start + 3),
            with_form(test, ("if", ("lt", ("integer-length", ("var", "x")), 64),
                             form, ("mv-list", ("truncate", ("var", "x")))), start + 4)]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("corpus")
    parser.add_argument("coverage")
    parser.add_argument("--workdir", default="audit-mutated")
    args = parser.parse_args()
    tests = json.loads(Path(args.corpus).read_text())
    coverage = json.loads(Path(args.coverage).read_text())
    frequencies = Counter(line for entries in coverage.values() for line in set(entries))
    ranked = sorted(tests, key=lambda test: (
        min((frequencies[line] for line in set(coverage.get(test["id"], []))), default=0),
        test["id"]))
    output = []
    for test in ranked:
        output.extend(mutations(test, len(output)))
    workdir = Path(args.workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    (workdir / "corpus.json").write_text(json.dumps(output, indent=2))
    print(json.dumps({"input": len(tests), "output": len(output),
                      "rarest_coverage": min(frequencies.values(), default=0)}))

if __name__ == "__main__":
    main()
