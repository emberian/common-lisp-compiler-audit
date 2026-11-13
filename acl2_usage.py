#!/usr/bin/env python3
import argparse
import json
from collections import Counter
from pathlib import Path

from audit_patterns import head, parse, walk

DEFAULT_OPERATIONS = {
    "ash", "truncate", "floor", "round", "ceiling", "mask-signed-field",
    "len", "length", "car", "cdr", "cons", "append", "elt", "aref",
    "mv-list", "nth-value", "values", "let", "let*", "if", "return-last",
    "mbe", "ec-call", "non-exec", "aref1", "aset1", "compress1", "aref2",
    "aset2", "compress2", "maybe-flush-and-compress1", "zp", "zip", "nfix",
    "ifix", "fix", "mod", "rem", "nonnegative-integer-quotient",
}

def usage(paths):
    counts = Counter()
    files = Counter()
    for path in paths:
        for root in parse(path.read_text(errors="replace")):
            for node, _ in walk(root):
                operation = head(node)
                if operation in DEFAULT_OPERATIONS:
                    counts[operation] += 1
                    files[str(path)] += 1
    return counts, files

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+")
    parser.add_argument("--output")
    args = parser.parse_args()
    paths = []
    for arg in args.paths:
        path = Path(arg)
        paths.extend([path] if path.is_file() else path.glob("*.lisp"))
    counts, files = usage(paths)
    records = [{"operation": operation, "count": count}
               for operation, count in counts.most_common()]
    text = json.dumps(records, indent=2)
    if args.output:
        Path(args.output).write_text(text)
    else:
        print(text)

if __name__ == "__main__":
    main()
