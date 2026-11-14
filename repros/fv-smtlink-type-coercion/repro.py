#!/usr/bin/env python3
"""Exercises actual head-worktree ACL2_to_Z3.py (ACL22SMT) on false ACL2 theorems."""
import sys
sys.path.insert(0, "/Users/ember/dev/acl2-fix/head-worktree/books/projects/smtlink/z3_interface")

from z3 import *  # noqa: F403
from ACL2_to_Z3 import ACL22SMT

cases = [
    ("equal_nil_0", lambda s: s.equal(False, 0)),
    ("equal_t_1", lambda s: s.equal(True, 1)),
    ("lt_nil_t", lambda s: s.lt(False, True)),
    ("lt_0_t", lambda s: s.lt(0, True)),
    ("plus_t_minus1_eq_0", lambda s: s.equal(s.plus(True, -1), 0)),
    ("negate_t_eq_minus1", lambda s: s.equal(s.negate(True), -1)),
    ("reciprocal_t_eq_1", lambda s: s.equal(s.reciprocal(True), 1)),
    ("times_nil_nil_eq_nil", lambda s: s.equal(s.times(False, False), False)),
]

all_proved = True
for name, fn in cases:
    _SMT_ = ACL22SMT()
    res = _SMT_.prove(fn(_SMT_))
    print(f"{name}: isThm={res.isThm()}")
    if not res.isThm():
        all_proved = False

if all_proved:
    print("proved")
sys.exit(0 if all_proved else 1)
