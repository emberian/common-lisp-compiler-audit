#!/usr/bin/env python3
import json
import sys
from dataclasses import dataclass
from pathlib import Path

@dataclass
class Atom:
    text: str
    line: int

@dataclass
class Form:
    items: list
    line: int

BOUNDED = {"signed-byte", "unsigned-byte", "integer", "mod"}
SENSITIVE = {"length", "integer-length", "ash", "integer-length", "elt", "aref"}
DERIVATION = {"deftransform", "defoptimizer", "defknown", "defun"}

def tokens(text):
    i = 0
    line = 1
    n = len(text)
    depth = 0
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c.isspace() or c == ",":
            i += 1
        elif c == ";":
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("#|", i):
            depth += 1
            i += 2
            while depth and i < n:
                if text.startswith("#|", i):
                    depth += 1
                    i += 2
                elif text.startswith("|#", i):
                    depth -= 1
                    i += 2
                else:
                    if text[i] == "\n":
                        line += 1
                    i += 1
        elif text.startswith("|#", i):
            i += 2
        elif c == '"':
            start = line
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                elif text[i] == '"':
                    i += 1
                    break
                else:
                    if text[i] == "\n":
                        line += 1
                    i += 1
            yield Atom('"' + text[i:i] + '"', start)
        elif c in "()":
            yield Atom(c, line)
            i += 1
        elif c in "'`":
            yield Atom(c, line)
            i += 1
        elif c == "#" and i + 1 < n and text[i + 1] == "'":
            yield Atom("#'", line)
            i += 2
        else:
            start = i
            start_line = line
            while i < n and not text[i].isspace() and text[i] not in "();'`\"":
                i += 1
            yield Atom(text[start:i], start_line)

def parse(text):
    stack = []
    roots = []
    for token in tokens(text):
        if token.text == "(":
            form = Form([], token.line)
            if stack:
                stack[-1].items.append(form)
            else:
                roots.append(form)
            stack.append(form)
        elif token.text == ")":
            if stack:
                stack.pop()
        elif token.text in {"'", "`", "#'"}:
            continue
        elif stack:
            stack[-1].items.append(token)
    return roots

def head(form):
    if isinstance(form, Form) and form.items and isinstance(form.items[0], Atom):
        return form.items[0].text.lower()
    return None

def walk(form, path=()):
    yield form, path
    if isinstance(form, Form):
        for index, item in enumerate(form.items):
            yield from walk(item, path + (index,))

def bounded_type(form):
    if not isinstance(form, Form) or not form.items:
        return False
    name = head(form)
    return name in BOUNDED and any(isinstance(x, Atom) and x.text.lstrip("+-").isdigit()
                                   for x in form.items[1:])

def source_text(form, limit=220):
    if isinstance(form, Atom):
        return form.text
    text = "(" + " ".join(source_text(x, limit) for x in form.items) + ")"
    return text if len(text) <= limit else text[:limit - 3] + "..."

def analyze(path):
    try:
        roots = parse(path.read_text(errors="replace"))
    except OSError:
        return
    for root in roots:
        nodes = list(walk(root))
        bounded = [(node, path) for node, path in nodes if bounded_type(node)]
        sensitive = [(node, path) for node, path in nodes
                     if isinstance(node, Form) and head(node) in SENSITIVE]
        for node, node_path in bounded:
            parent = root
            kind = head(root) or "top-level"
            yield {"kind": "bounded-type-near-sensitive-operation" if sensitive else "bounded-type",
                   "path": str(path), "line": node.line, "construct": kind,
                   "form": source_text(root)}
        if head(root) in DERIVATION and sensitive:
            yield {"kind": "sensitive-operation-in-compiler-definition",
                   "path": str(path), "line": root.line, "construct": head(root),
                   "form": source_text(root)}

def main():
    seen = set()
    for arg in sys.argv[1:]:
        base = Path(arg)
        paths = [base] if base.is_file() else sorted(base.rglob("*.lisp"))
        for path in paths:
            for finding in analyze(path):
                key = (finding["kind"], finding["path"], finding["line"], finding["form"])
                if key not in seen:
                    seen.add(key)
                    print(json.dumps(finding, ensure_ascii=False))

if __name__ == "__main__":
    main()
