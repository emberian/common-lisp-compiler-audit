#!/usr/bin/env python3
"""Model-based fuzzer for SATlink DIMACS output parser (books/centaur/satlink/top.lisp:528-624)
and DIMACS emission / exit-code handling (top.lisp:738-765)."""

from dataclasses import dataclass
import random


@dataclass
class ParserState:
    saw_unsat_p: bool = False
    saw_sat_p: bool = False
    saw_unknown_p: bool = False
    saw_zero_p: bool = False


def satlink_parse_output_model(lines, max_index):
    """Faithful model of satlink-handle-line / satlink-parse-output (satlink/top.lisp:528-623)."""
    p = ParserState()
    env = [0] * (max_index + 1)
    for line in lines:
        if len(line) < 2:
            continue
        ch = line[0]
        if ch not in ("s", "v") or line[1] != " ":
            continue
        if ch == "s":
            # satlink/top.lisp:550-555 uses str::strprefixp!
            if line.startswith("s SATISFIABLE"):
                p.saw_sat_p = True
            elif line.startswith("s UNSATISFIABLE"):
                p.saw_unsat_p = True
            elif line.startswith("s UNKNOWN"):
                p.saw_unknown_p = True
            else:
                pass
            continue
        if p.saw_zero_p:
            return ("failed", env)
        # Parse v line tokens (satlink-parse-variable-line)
        for tok in line[2:].split():
            try:
                val = int(tok)
            except ValueError:
                return ("failed", env)
            if val == 0:
                p.saw_zero_p = True
            else:
                idx = abs(val)
                if idx <= max_index:
                    env[idx] = 1 if val > 0 else 0
    if p.saw_unsat_p and p.saw_sat_p:
        return ("failed", env)
    if p.saw_unsat_p and p.saw_unknown_p:
        return ("failed", env)
    if p.saw_sat_p and p.saw_unknown_p:
        return ("failed", env)
    if p.saw_sat_p and not p.saw_zero_p:
        return ("failed", env)
    if p.saw_unsat_p and p.saw_zero_p:
        return ("failed", env)
    if p.saw_unknown_p and p.saw_zero_p:
        return ("failed", env)
    if p.saw_unsat_p:
        return ("unsat", env)
    if p.saw_sat_p:
        return ("sat", env)
    return ("failed", env)


def satlink_run_impl_exit_check(exit_status, lines, max_index=1):
    """Model of satlink/top.lisp:751-764: only status == 127 is checked!"""
    if exit_status == 127:
        return ("failed", None)
    return satlink_parse_output_model(lines, max_index)


def main():
    rng = random.Random(20261113)
    findings = []

    adversarial_cases = [
        ("prefix-not-exact-1", 0, ["s UNSATISFIABLE_ERROR_OR_NOT"]),
        ("prefix-not-exact-2", 0, ["s UNSATISFIABLE? FALSE!"]),
        ("nonzero-exit-segfault-139", 139, ["s UNSATISFIABLE"]),
        ("nonzero-exit-1-cli-error", 1, ["s UNSATISFIABLE usage error"]),
        ("duplicate-v-zero-ignored", 0, ["s UNSATISFIABLE", "v "]),
        ("comment-missing-c-spoof", 0, ["s UNSATISFIABLE", "s SATISFIABLE"]),
        ("unknown-then-unsat-not-caught-if-typo", 0, ["s UNSATISFIABLE", "s TIMEOUT"]),
    ]

    for name, code, lines in adversarial_cases:
        res, _ = satlink_run_impl_exit_check(code, lines)
        if res == "unsat":
            findings.append((name, code, lines, res))

    # Fuzz random noisy solver outputs with prefix/exit-code perturbations
    prefixes = ["s UNSATISFIABLE", "s UNSATISFIABLE!", "s UNSATISFIABLE (UNKNOWN)", "c comment", "ERROR:", "v 1 0"]
    fuzzed_unsats = 0
    for _ in range(1000):
        code = rng.choice([0, 1, 2, 134, 139])
        n_lines = rng.randint(1, 4)
        lines = [rng.choice(prefixes) for _ in range(n_lines)]
        res, _ = satlink_run_impl_exit_check(code, lines)
        if res == "unsat" and (code != 0 or any(not l == "s UNSATISFIABLE" for l in lines if l.startswith("s "))):
            fuzzed_unsats += 1

    print(f"Adversarial SATlink parser/exit-code bypasses producing :unsat: {len(findings)}")
    for name, code, lines, res in findings:
        print(f"  [{name}] exit={code} lines={lines!r} -> {res}")
    print(f"Randomized fuzz trials returning :unsat on non-0 exit or corrupted 's UNSATISFIABLE...' line: {fuzzed_unsats}/1000")


if __name__ == "__main__":
    main()
