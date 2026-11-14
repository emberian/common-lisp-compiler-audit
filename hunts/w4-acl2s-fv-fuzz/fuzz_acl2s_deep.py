#!/usr/bin/env python3
"""
Wave-4 Deep Mechanical Fuzzer for ACL2s (fuzz_acl2s_deep.py)
Implements Pipelines 1-3 (+4) from reports/ACL2S-AUDIT.md targeting NOVEL bugs
beyond ACL2S-1..4:
  - Pipeline 1: defdata combinators (map.lisp:160/199 ?valpred, defdata-core.lisp:167/208
    avoid-lst xvar inversion, cross-package record fields, register-data-constructor,
    defdata-subtype-strict / defdata-disjoint-strict falsification, polymorphic sig).
  - Pipeline 2: match macro (books/acl2s/match.lisp) differential & scope-capture fuzzer
    ((a . !a) outer-variable capture, :t guard scope leak, nested :or, ! / * atoms,
    quote~) + definec/defunc cross-package formals (ACL2::X vs ACL2S::X), free vars in
    :ic/:oc, relational :oc, mv, and stobjs.
  - Pipeline 3: CCG termination ttree check (ccg.lisp:7566 chk-assumption-free-ttree nil)
    with force / case-split / fc-derivation rules + redefun+rewrite stobj interaction.

Strictly uses an ephemeral /tmp/w4-fv-XXXXXX shadow ACL2_SYSTEM_BOOKS workspace
and cleans up all temporary files on exit.
"""

import argparse
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SRC_BOOKS = "/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2 = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2 = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"
TIMEOUT_BIN = "/opt/homebrew/bin/timeout"

PREAMBLE = """
(defpkg "FTY" *acl2-exports*)
(ld "std/package.lsp" :dir :system)
(ld "hacking/hacker-pkg.lsp" :dir :system)
(ld "hacking/rewrite-code-pkg.lsp" :dir :system)
(ld "data-structures/portcullis.acl2" :dir :system)
(ld "coi/symbol-fns/portcullis.acl2" :dir :system)
(ld "acl2s/package.lsp" :dir :system)
(include-book "std/util/defredundant" :dir :system :uncertified-okp t)
(include-book "make-event/acl2x-help" :dir :system :uncertified-okp t)
(include-book "acl2s/ccg/ccg" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/defdata/top" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/cgen/top" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/match" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/defunc" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/definec" :dir :system :ttags :all :uncertified-okp t)
(include-book "acl2s/properties" :dir :system :ttags :all :uncertified-okp t)
(in-package "ACL2S")
"""


def build_shadow_books(root: Path) -> str:
    """Create an ephemeral read-write shadow ACL2_SYSTEM_BOOKS in /tmp/w4-fv-XXXXXX."""
    sb = root / "books"
    sb.mkdir(parents=True, exist_ok=True)
    for d in (
        "acl2s", "xdoc", "misc", "data-structures", "hacking", "std",
        "ordinals", "tools", "arithmetic-5", "make-event",
        "clause-processors", "system", "defsort",
    ):
        shutil.copytree(Path(SRC_BOOKS) / d, sb / d)
    (sb / "centaur" / "fty").mkdir(parents=True, exist_ok=True)
    shutil.copytree(Path(SRC_BOOKS) / "centaur" / "misc", sb / "centaur" / "misc")
    (sb / "coi" / "symbol-fns").mkdir(parents=True, exist_ok=True)
    (sb / "coi" / "util").mkdir(parents=True, exist_ok=True)
    (sb / "ihs").mkdir(parents=True, exist_ok=True)
    (sb / "kestrel" / "utilities" / "system").mkdir(parents=True, exist_ok=True)

    (sb / "centaur" / "fty" / "basetypes.lisp").write_text(
        '(in-package "ACL2")\n'
        '(include-book "std/basic/defs" :dir :system :uncertified-okp t)\n'
        '(include-book "std/basic/pos-fix" :dir :system :uncertified-okp t)\n'
        '(defun int-equiv (x y) (declare (xargs :guard t)) (equal (ifix x) (ifix y)))\n'
        '(defequiv int-equiv)\n(defcong int-equiv equal (ifix x) 1)\n'
        '(defun nat-equiv (x y) (declare (xargs :guard t)) (equal (nfix x) (nfix y)))\n'
        '(defequiv nat-equiv)\n(defcong nat-equiv equal (nfix x) 1)\n'
        '(defun bit-equiv (x y) (declare (xargs :guard t)) (equal (bfix x) (bfix y)))\n'
        '(defequiv bit-equiv)\n(defcong bit-equiv equal (bfix x) 1)\n'
    )
    fixtype_src = (
        '(in-package "FTY")\n'
        '(defmacro deffixtype (&rest args) (declare (ignore args)) \'(value-triple :deffixtype-stub))\n'
        '(defmacro deffixcong (&rest args) (declare (ignore args)) \'(value-triple :deffixcong-stub))\n'
        '(defmacro deffixequiv (&rest args) (declare (ignore args)) \'(value-triple :deffixequiv-stub))\n'
    )
    (sb / "centaur" / "fty" / "fixtype.lisp").write_text(fixtype_src)
    (sb / "centaur" / "fty" / "fixequiv.lisp").write_text(fixtype_src)
    (sb / "coi" / "symbol-fns" / "portcullis.acl2").write_text(
        '(in-package "ACL2")\n'
        '(defpkg "SYMBOL-FNS" (union-eq *acl2-exports* *common-lisp-symbols-from-main-lisp-package*))\n'
    )
    (sb / "coi" / "symbol-fns" / "portcullis.lisp").write_text('(in-package "ACL2")\n')
    (sb / "coi" / "symbol-fns" / "symbol-fns.lisp").write_text(
        '(in-package "SYMBOL-FNS")\n'
        '(defun join-symbols-lst (pkg lst) (declare (xargs :mode :logic :guard (symbol-listp lst)) (ignore pkg)) '
        '(if (endp lst) "" (concatenate \'string (symbol-name (car lst)) (join-symbols-lst pkg (cdr lst)))))\n'
        '(defun join-symbols-fn (pkg lst) (declare (xargs :mode :logic :guard (and (symbolp pkg) (symbol-listp lst)))) '
        '(intern$ (join-symbols-lst pkg lst) (if (symbolp pkg) (symbol-package-name pkg) "ACL2")))\n'
        '(defmacro suffix (&rest args) `(join-symbols-fn ,(car args) (list ,@args)))\n'
        '(defmacro prefix (&rest args) `(let ((xs (list ,@args))) (join-symbols-fn (car (last xs)) xs)))\n'
        '(defun item-to-numbered-symbol-list-rec (x k) (declare (xargs :mode :logic :guard (and (symbolp x) (natp k)))) '
        '(if (zp k) nil (cons (intern$ (concatenate \'string (symbol-name x) (coerce (explode-atom k 10) \'string)) '
        '(if (symbolp x) (symbol-package-name x) "ACL2")) (item-to-numbered-symbol-list-rec x (1- k)))))\n'
    )
    (sb / "coi" / "util" / "pseudo-translate.lisp").write_text(
        '(in-package "ACL2")\n(program)\n'
        '(defun pseudo-translate-add-fns (fns-args wrld) (if (endp fns-args) wrld '
        '(let* ((fn (caar fns-args)) (args (cdar fns-args)) (wrld (putprop fn \'formals args wrld)) '
        '(wrld (putprop fn \'stobjs-in (make-list (len args)) wrld)) (wrld (putprop fn \'stobjs-out \'(nil) wrld))) '
        '(pseudo-translate-add-fns (cdr fns-args) wrld))))\n'
        '(defun pseudo-translate (form new-fns-and-args wrld) '
        '(let ((wrld1 (pseudo-translate-add-fns new-fns-and-args wrld))) '
        '(mv-let (erp val bindings) (translate1-cmp form t nil t \'pseudo-translate wrld1 (default-state-vars nil)) '
        '(declare (ignore bindings)) (mv erp val))))\n'
    )
    (sb / "tau" / "bounders").mkdir(parents=True, exist_ok=True)
    (sb / "tau" / "bounders" / "elementary-bounders.lisp").write_text('(in-package "ACL2")\n')
    # Allow uncertified include-book of ccg inside shadow copy of match.lisp
    match_p = sb / "acl2s" / "match.lisp"
    match_p.write_text(match_p.read_text().replace(":uncertified-okp nil", ":uncertified-okp t"))
    (sb / "ihs" / "basic-definitions.lisp").write_text(
        '(in-package "ACL2")\n'
        '(defun zbp (x) (declare (xargs :guard t)) (or (not (integerp x)) (= x 0)))\n'
        '(defun loghead (size i) (declare (xargs :guard (and (integerp size) (<= 0 size) (integerp i)))) (mod (ifix i) (expt 2 (nfix size))))\n'
        '(defun logtail (pos i) (declare (xargs :guard (and (integerp pos) (<= 0 pos) (integerp i)))) (floor (ifix i) (expt 2 (nfix pos))))\n'
        '(defun logcons (b i) (declare (xargs :guard (and (bitp b) (integerp i)))) (let ((i (ifix i))) (+ (if (= b 1) 1 0) (* 2 i))))\n'
        '(defthm unsigned-byte-p-loghead (implies (and (integerp size) (<= 0 size) (integerp i)) (unsigned-byte-p size (loghead size i))))\n'
        '(defthm logcons-type (implies (and (bitp b) (integerp i)) (integerp (logcons b i))) :rule-classes :type-prescription)\n'
        '(defthm unsigned-byte-p-logcons (implies (and (bitp b) (integerp size) (< 0 size) (unsigned-byte-p (1- size) i)) (unsigned-byte-p size (logcons b i))))\n'
    )
    (sb / "kestrel" / "utilities" / "proof-builder-macros.lisp").write_text('(in-package "ACL2")\n')
    (sb / "kestrel" / "utilities" / "ubi.lisp").write_text('(in-package "ACL2")\n')
    (sb / "kestrel" / "utilities" / "make-termination-theorem.lisp").write_text(
        '(in-package "ACL2")\n'
        '(defun make-termination-theorem (fn wrld) (declare (xargs :mode :program) (ignore fn wrld)) \'t)\n'
    )
    (sb / "kestrel" / "utilities" / "system" / "terms.lisp").write_text(
        '(in-package "ACL2")\n(include-book "coi/util/pseudo-translate" :dir :system)\n'
        '(verify-termination body)\n'
        '(defun filter-program-fns (fns wrld) (declare (xargs :mode :program)) '
        '(cond ((endp fns) nil) ((eq (symbol-class (car fns) wrld) :program) '
        '(cons (car fns) (filter-program-fns (cdr fns) wrld))) (t (filter-program-fns (cdr fns) wrld))))\n'
        '(defun all-program-ffn-symbs (term ans wrld) (declare (xargs :mode :program)) '
        '(append (filter-program-fns (all-ffn-symbs term nil) wrld) ans))\n'
    )
    return str(sb)


def gen_pipeline1_defdata(rng, rand_count=25):
    """Pipeline 1: Deep defdata combinators, map ?valpred, avoid-lst xvar,
    cross-package record fields, register-data-constructor, subtype/disjoint, sig."""
    cases = []

    # 1A. map.lisp:160 & 199 ?valpred copy-paste bug:
    # ?valpred checks (and (proper-symbolp keybody) (assoc-eq keybody M) ...) instead of valbody!
    # Case 1: keybody is a symbol in M (nat), valbody is compound (oneof 1 2) or (cons nat nat):
    #   (predicate-name '(oneof 1 2) A M) returns NIL or crashes / generates malformed (NIL ...) predicate!
    # Case 2: keybody is compound (oneof 'a 'b), valbody is a symbol in M (nat):
    #   ?valpred becomes NIL even though valbody IS a proper type symbol!
    cases.extend([
        ("p1_map_symkey_compval",
         "(defdata p1_m_sc (map nat (oneof 1 2)))",
         "(value-triple (list :P1-MAP-SC-EXISTS (acl2::logical-namep 'p1_m_scp (w state))))"),
        ("p1_map_symkey_consval",
         "(defdata p1_m_scons (map symbol (cons nat pos)))",
         "(value-triple (list :P1-MAP-SCONS-EXISTS (acl2::logical-namep 'p1_m_sconsp (w state))))"),
        ("p1_map_compkey_symval",
         "(defdata p1_m_cs (map (oneof :a :b) nat))",
         "(value-triple (list :P1-MAP-CS-EXISTS (acl2::logical-namep 'p1_m_csp (w state))))"),
        ("p1_mut_map_newkey_oldval",
         "(defdata (p1_mm1 (map p1_mr1 nat)) (p1_mr1 (oneof nil (cons nat p1_mr1))))",
         "(value-triple (list :P1-MUT-MAP1-EXISTS (acl2::logical-namep 'p1_mm1p (w state))))"),
        ("p1_mut_map_oldkey_newval",
         "(defdata (p1_mm2 (map nat p1_mr2)) (p1_mr2 (oneof nil (cons nat p1_mr2))))",
         "(value-triple (list :P1-MUT-MAP2-EXISTS (acl2::logical-namep 'p1_mm2p (w state))))"),
        ("p1_map_direct_events_check",
         """(let* ((wrld (w state))
                   (M (acl2::table-alist 'defdata::type-metadata-table wrld))
                   (A (acl2::table-alist 'defdata::type-alias-table wrld))
                   (new-types '((r_new . ((:predicate . r_newp)))))
                   (ev1 (defdata::map-theory-events 'test_m1 'r_new 'nat new-types (append new-types M) 'defdata::mp))
                   (ev2 (defdata::map-theory-events 'test_m2 'nat 'r_new new-types (append new-types M) 'defdata::mp)))
              (cw "(:MAP-EV-NEWKEY ~x0 :MAP-EV-NEWVAL ~x1)~%" (len ev1) (len ev2)))""",
         "(value-triple :P1-MAP-DIRECT-DONE)"),
    ])

    # 1B. defdata-core.lisp:167 & 208 inverted avoid-lst check:
    # (xvar (if (member-eq d avoid-lst) d (acl2::generate-variable d avoid-lst nil nil wrld)))
    cases.extend([
        ("p1_avoid_self_d",
         "(defdata (d (oneof nil (cons nat d))))",
         "(value-triple (list :P1-AVOID-D-EXISTS (acl2::logical-namep 'dp (w state))))"),
        ("p1_avoid_v1_collision",
         "(defdata (v1 (oneof nil (cons v1 v1))))",
         "(value-triple (list :P1-AVOID-V1-EXISTS (acl2::logical-namep 'v1p (w state))))"),
        ("p1_avoid_cons_collision",
         "(defdata (d (oneof 0 (list d d))))",
         "(value-triple (list :P1-AVOID-D2-EXISTS (acl2::logical-namep 'dp (w state))))"),
    ])

    # 1C. Cross-package field names in record (ACL2::A vs ACL2S::A) & keyword/weird fields
    cases.extend([
        ("p1_rec_cross_pkg_fields",
         "(defdata p1_rpkg (record (acl2::a . nat) (acl2s::a . string)))",
         """(value-triple (list :P1-RPKG-EXISTS (acl2::logical-namep 'p1_rpkgp (w state))))"""),
        ("p1_rec_cross_pkg_exploit",
         """(defthm p1_rpkg_check
              (implies (p1_rpkgp r) (and (natp (p1_rpkg-a r)) (stringp (p1_rpkg-a r))))
              :rule-classes nil)""",
         "(value-triple :P1-RPKG-EXPLOIT-AFTER)"),
    ])

    # 1D. register-data-constructor with non-bijective / overlapping / improper constructors
    cases.extend([
        ("p1_reg_ctor_nonbijective",
         """(progn
              (defun bad-pair-p (x) (declare (xargs :guard t)) (consp x))
              (defun bad-pair (a b) (declare (xargs :guard t) (ignore b)) (cons a a))
              (defun bad-fst (x) (declare (xargs :guard (bad-pair-p x))) (car x))
              (defun bad-snd (x) (declare (xargs :guard (bad-pair-p x))) 0)
              (register-data-constructor (bad-pair-p bad-pair)
                ((allp bad-fst) (allp bad-snd))
                :proper nil))""",
         "(value-triple (list :P1-REG-CTOR-DONE (acl2::logical-namep 'bad-pair (w state))))"),
        ("p1_reg_ctor_use_in_defdata",
         "(defdata p1_bp_t (bad-pair nat string))",
         "(thm nil)"),
    ])

    # 1E. defdata-subtype-strict / defdata-disjoint-strict false claims (must fail!)
    cases.extend([
        ("p1_false_subtype",
         "(defdata-subtype-strict int nat)",
         "(value-triple :MUST-FAIL-SUBTYPE)"),
        ("p1_false_disjoint",
         "(defdata-disjoint-strict nat int)",
         "(value-triple :MUST-FAIL-DISJOINT)"),
        ("p1_range_disjoint_edge",
         """(progn
              (defdata p1_r1 (range rational (0 <= _ <= 1)))
              (defdata p1_r2 (range rational (1 <= _ <= 2)))
              (defdata-disjoint-strict p1_r1 p1_r2))""",
         "(value-triple :MUST-FAIL-OVERLAPPING-RANGE)"),
    ])

    # 1F. Polymorphic sig edge cases
    cases.extend([
        ("p1_sig_dup_tvar",
         """(progn
              (defun p1_id2 (x y) (declare (xargs :guard t)) (if (equal x y) x y))
              (sig p1_id2 (:a :a) => :a))""",
         "(value-triple :P1-SIG-DUP-DONE)"),
        ("p1_sig_wrong_ret",
         """(progn
              (defun p1_bad_sig_fn (x) (declare (xargs :guard t)) (cons x x))
              (sig p1_bad_sig_fn ((listof :a)) => (listof :a)))""",
         "(value-triple :MUST-FAIL-SIG)"),
    ])

    # 1G. Random combinator fuzzing (compound map/alistof/record/oneof)
    atom_t = ["nat", "pos", "int", "boolean", "symbol", "string"]
    comp_t = ["(oneof 1 2)", "(oneof :x :y)", "(listof nat)", "(cons nat boolean)", "(range integer (0 <= _ <= 3))"]
    for i in range(rand_count):
        tn = f"p1_fz_{i}"
        choice = rng.choice(["map_comp_val", "map_comp_key", "alist_comp", "rec_nested", "mut_avoid"])
        if choice == "map_comp_val":
            kt = rng.choice(atom_t)
            vt = rng.choice(comp_t)
            form = f"(defdata {tn} (map {kt} {vt}))"
        elif choice == "map_comp_key":
            kt = rng.choice(comp_t)
            vt = rng.choice(atom_t)
            form = f"(defdata {tn} (map {kt} {vt}))"
        elif choice == "alist_comp":
            kt = rng.choice(atom_t + comp_t)
            vt = rng.choice(atom_t + comp_t)
            form = f"(defdata {tn} (alistof {kt} {vt}))"
        elif choice == "rec_nested":
            f1 = rng.choice(["a", "b", "d", "x", "v1"])
            f2 = rng.choice(["c", "e", "y", "v2"])
            form = f"(defdata {tn} (record ({f1} . {rng.choice(atom_t)}) ({f2} . {rng.choice(comp_t)})))"
        else:
            nm = rng.choice(["d", "v1", "v2", f"{tn}_r"])
            form = f"(defdata ({tn} (oneof nil (cons {rng.choice(atom_t)} {nm}))) ({nm} (oneof nil (cons pos {tn}))))"
        cases.append((f"p1_rand_{i}_{choice}", form, f"(value-triple (list :P1-RAND '{tn} (acl2::logical-namep '{tn}p (w state))))"))

    return cases


def eval_py_pattern(pat, val, outer_env):
    """Ground-truth reference evaluator for ACL2s `match` patterns (intended spec)."""
    kind = pat[0]
    if kind == "wild":
        return True, {}
    if kind == "lit":
        return val == pat[1], {}
    if kind == "type":
        t = pat[1]
        if t == ":int":
            ok = isinstance(val, int) and not isinstance(val, bool)
        elif t == ":nat":
            ok = isinstance(val, int) and not isinstance(val, bool) and val >= 0
        elif t == ":pos":
            ok = isinstance(val, int) and not isinstance(val, bool) and val > 0
        elif t == ":bool":
            ok = isinstance(val, bool)
        else:
            ok = False
        return ok, {}
    if kind == "var":
        vname = pat[1]
        return True, {vname: val}
    if kind == "bang":
        vname = pat[1]
        # !v matches existing value of v (either bound earlier in same pattern or outer scope!)
        if vname in outer_env:
            return val == outer_env[vname], {}
        return False, {}
    if kind == "cons":
        if not isinstance(val, tuple) or len(val) != 2:
            return False, {}
        ok1, b1 = eval_py_pattern(pat[1], val[0], outer_env)
        if not ok1:
            return False, {}
        merged_env = dict(outer_env)
        merged_env.update(b1)
        ok2, b2 = eval_py_pattern(pat[2], val[1], merged_env)
        if not ok2:
            return False, {}
        b1.update(b2)
        return True, b1
    return False, {}


def val_to_lisp(val):
    if val is True:
        return "t"
    if val is False:
        return "nil"
    if isinstance(val, int):
        return str(val)
    if isinstance(val, tuple) and len(val) == 2:
        return f"(cons {val_to_lisp(val[0])} {val_to_lisp(val[1])})"
    return "nil"


def pat_to_lisp(pat):
    kind = pat[0]
    if kind == "wild":
        return "&"
    if kind == "lit":
        v = pat[1]
        if v is True:
            return "t"
        if v is False:
            return "nil"
        return str(v)
    if kind == "type":
        return pat[1]
    if kind == "var":
        return pat[1]
    if kind == "bang":
        return f"!{pat[1]}"
    if kind == "cons":
        return f"({pat_to_lisp(pat[1])} . {pat_to_lisp(pat[2])})"
    return "&"


def gen_pipeline2_match_and_definec(rng, diff_count=30):
    """Pipeline 2: match macro completeness/soundness + definec/defunc deep contracts."""
    cases = []

    # 2A. Targeted match bugs from source inspection of books/acl2s/match.lisp:
    # Bug candidate M1: (a . !a) when `a` is NOT bound in outer scope -> fails translation!
    # Bug candidate M2: (a . !a) when `a` IS bound in outer scope -> SILENT SEMANTIC CORRUPTION!
    #   Tests (equal (cdr y) <outer-a>) instead of (equal (car y) (cdr y)), AND binds a=(car y) in body!
    # Bug candidate M3: `:t` guard in match clause -> `(match y ((a . b) :t (< a b) ...))` ->
    #   Does `match` put `:t (< a b)` inside `cond` test OUTSIDE `(let ((a (car y)) (b (cdr y))) ...)`?!
    # Bug candidate M4: Nested `(:or ...)` inside cons pattern `((:or 1 2) . x)` ->
    #   Treated as 3-element list pattern matching literal keyword `:or` instead of disjunction!
    # Bug candidate M5: Bare `!` or `*` symbol in pattern!
    cases.extend([
        ("p2_match_bang_unbound",
         "(definec m_bang_unb (y :cons) :bool (match y ((b_fresh . !b_fresh) t) (& nil)))",
         "(value-triple (list :M-BANG-UNB-ADMITTED (acl2::logical-namep 'm_bang_unb (w state))))"),
        ("p2_match_bang_outer_capture",
         """(definec m_bang_cap (a :int y :cons) :int
              (match y
                ((a . !a) a)
                (& -1)))""",
         """(value-triple
              (list :M-BANG-CAP-SAME (m_bang_cap 99 '(7 . 7))
                    :M-BANG-CAP-OUTER (m_bang_cap 99 '(42 . 99))))"""),
        ("p2_match_t_guard_unbound",
         """(definec m_tguard_unb (y :cons) :bool
              (match y
                ((g_fresh1 . g_fresh2) :t (equal g_fresh1 g_fresh2) t)
                (& nil)))""",
         "(value-triple (list :M-TGUARD-UNB-ADMITTED (acl2::logical-namep 'm_tguard_unb (w state))))"),
        ("p2_match_t_guard_outer_capture",
         """(definec m_tguard_cap (a :int b :int y :cons) :int
              (match y
                ((a . b) :t (< a b) (+ a b))
                (& -1)))""",
         """(value-triple
              (list :M-TGUARD-CAP-1 (m_tguard_cap 100 0 '(1 . 2))
                    :M-TGUARD-CAP-2 (m_tguard_cap 1 2 '(100 . 0))))"""),
        ("p2_match_nested_or",
         """(definec m_nested_or (y :cons) :int
              (match y
                (((:or 1 2) . x) (if (integerp x) x 0))
                (& -1)))""",
         """(value-triple
              (list :M-NESTED-OR-1 (m_nested_or '(1 . 42))
                    :M-NESTED-OR-KW (m_nested_or '((:or 1 2) . 42))))"""),
        ("p2_match_bare_bang",
         "(definec m_bare_bang (y :all) :bool (match y (! t) (& nil)))",
         "(value-triple (list :M-BARE-BANG (acl2::logical-namep 'm_bare_bang (w state))))"),
        ("p2_match_bare_star",
         "(definec m_bare_star (y :all) :bool (match y (* t) (& nil)))",
         "(value-triple (list :M-BARE-STAR (acl2::logical-namep 'm_bare_star (w state))))"),
    ])

    # 2B. Differential random match fuzzing (comparing ACL2s match vs Python reference)
    sample_inputs = [
        0, 1, -3, True, False,
        (1, 1), (1, 2), (2, 1), (0, -3), ((1, 2), 1),
    ]
    for i in range(diff_count):
        # Generate a cons/type/var/bang pattern with outer formal `a = 5`
        p_choice = rng.choice(["dup_bang", "cons_type", "nested_cons", "lit_cons"])
        if p_choice == "dup_bang":
            pat = ("cons", ("var", "a"), ("bang", "a"))
            body_expr = "(if (integerp a) a 1000)"
            py_body = lambda env: env["a"] if (isinstance(env["a"], int) and not isinstance(env["a"], bool)) else 1000
        elif p_choice == "cons_type":
            t_tag = rng.choice([":int", ":nat", ":pos", ":bool"])
            pat = ("cons", ("type", t_tag), ("var", "a"))
            body_expr = "(if (integerp a) a 500)"
            py_body = lambda env: env["a"] if (isinstance(env["a"], int) and not isinstance(env["a"], bool)) else 500
        elif p_choice == "nested_cons":
            pat = ("cons", ("cons", ("var", "a"), ("wild",)), ("bang", "a"))
            body_expr = "(if (integerp a) a 700)"
            py_body = lambda env: env["a"] if (isinstance(env["a"], int) and not isinstance(env["a"], bool)) else 700
        else:
            lit = rng.choice([0, 1, -3, True, False])
            pat = ("cons", ("lit", lit), ("var", "a"))
            body_expr = "(if (integerp a) a 300)"
            py_body = lambda env: env["a"] if (isinstance(env["a"], int) and not isinstance(env["a"], bool)) else 300

        inp = rng.choice(sample_inputs)
        outer_a = rng.choice([1, 2, 5, 99])
        ok, bnd = eval_py_pattern(pat, inp, {"a": outer_a})
        merged = {"a": outer_a}
        merged.update(bnd)
        expected = py_body(merged) if ok else -999

        pat_s = pat_to_lisp(pat)
        inp_s = val_to_lisp(inp)
        form = (
            f"(let ((a {outer_a}) (y {inp_s})) "
            f"(match y ({pat_s} {body_expr}) (& -999)))"
        )
        cases.append((
            f"p2_diff_match_{i}",
            f"(value-triple (list :DIFF-MATCH-ID {i} :EXP {expected} :GOT {form}))",
            f"(value-triple :P2-DIFF-{i}-DONE)"
        ))

    # 2C. definec / defunc cross-package distinct symbols with identical symbol-name (ACL2::X vs ACL2S::X),
    #     defunc.lisp:1630 pseudo-translate msgp -> all-fnnames1 SIGSEGV,
    #     free variables in :ic/:oc, relational :oc, mv, and stobj tests:
    cases.extend([
        ("p2_defunc_segv_msgp",
         "(definec dc_segv_typo (x :int) :int (nonexistent_fn_xyz (x . 1)))",
         "(value-triple :P2-SEGV-SURVIVED)"),
        ("p2_property_segv_msgp",
         "(property (x :int) (nonexistent_prop_fn (x . 1)))",
         "(value-triple :P2-PROP-SEGV-SURVIVED)"),
        ("p2_definec_cross_pkg_formals",
         "(definec dc_pkg_x (acl2::x :int acl2s::x :string) :int (+ acl2::x (length acl2s::x)))",
         """(value-triple
              (list :DC-PKG-ADMITTED (acl2::logical-namep 'dc_pkg_x (w state))
                    :DC-PKG-FORMALS (and (acl2::logical-namep 'dc_pkg_x (w state))
                                         (acl2::formals 'dc_pkg_x (w state)))))"""),
        ("p2_defunc_cross_pkg_formals",
         """(defunc du_pkg_x (acl2::x acl2s::x)
              :input-contract (and (integerp acl2::x) (stringp acl2s::x))
              :output-contract (integerp (du_pkg_x acl2::x acl2s::x))
              (+ acl2::x (length acl2s::x)))""",
         "(value-triple (list :DU-PKG-ADMITTED (acl2::logical-namep 'du_pkg_x (w state))))"),
        ("p2_definec_ic_free_var",
         "(definec dc_free_ic (x :int) :int :ic (equal free_z x) x)",
         "(value-triple (list :DC-FREE-IC-ADMITTED (acl2::logical-namep 'dc_free_ic (w state))))"),
        ("p2_definec_oc_free_var",
         "(definec dc_free_oc (x :int) :int :oc (equal (dc_free_oc x) free_z) x)",
         "(value-triple (list :DC-FREE-OC-ADMITTED (acl2::logical-namep 'dc_free_oc (w state))))"),
        ("p2_defunc_relational_oc",
         """(defunc du_rel_oc (x)
              :input-contract (natp x)
              :output-contract (and (natp (du_rel_oc x))
                                    (implies (posp x) (< (du_rel_oc (1- x)) (du_rel_oc x))))
              (if (zp x) 0 (1+ (du_rel_oc (1- x)))))""",
         "(value-triple (list :DU-REL-OC-ADMITTED (acl2::logical-namep 'du_rel_oc (w state))))"),
        ("p2_defunc_false_relational_oc",
         """(defunc du_bad_rel_oc (x)
              :input-contract (natp x)
              :output-contract (and (natp (du_bad_rel_oc x))
                                    (implies (posp x) (< (du_bad_rel_oc x) (du_bad_rel_oc (1- x)))))
              (if (zp x) 0 (1+ (du_bad_rel_oc (1- x)))))""",
         "(value-triple (list :DU-BAD-REL-ADMITTED (acl2::logical-namep 'du_bad_rel_oc (w state))))"),
        ("p2_definec_mv_attempt",
         "(definec dc_mv_test (x :int) :all (acl2::mv x x))",
         "(value-triple (list :DC-MV-ADMITTED (acl2::logical-namep 'dc_mv_test (w state))))"),
    ])

    return cases


def gen_pipeline3_ccg_and_stobj(rng, rand_count=15):
    """Pipeline 3: CCG ttree assumption/fc-derivation leak (ccg.lisp:7566) & redefun+rewrite stobjs."""
    cases = []

    cases.extend([
        ("p3_enable_ccg",
         "(acl2::set-termination-method :ccg)",
         "(value-triple :CCG-ENABLED)"),

        # Test 3A: Can a :forward-chaining rule with a FORCED impossible hypothesis
        # leak an 'fc-derivation tag past (chk-assumption-free-ttree nil ttree state) in CCG?!
        # Remember: in ACL2 prove.lisp, (chk-assumption-free-ttree nil ttree state) checks ONLY
        # 'assumption and SKIPS 'fc-derivation unless the first arg is 'fc-derivation!
        ("p3_ccg_fc_derivation_setup",
         """(progn
              (defun p3_trig (x) (declare (xargs :guard t)) (integerp x))
              (defthm p3_forced_fc
                (implies (and (p3_trig x)
                              (acl2::force (equal x 'impossible)))
                         (< (acl2s-size (+ 1 x)) (acl2s-size x)))
                :rule-classes (:forward-chaining :linear))
              (in-theory (disable p3_trig)))""",
         "(value-triple :P3-FC-SETUP-DONE)"),
        ("p3_ccg_fc_nonterm_attempt",
         """(defun p3_bad_fc_rec (x)
              (declare (xargs :mode :logic))
              (if (p3_trig x)
                  (1+ (p3_bad_fc_rec (+ 1 x)))
                0))""",
         """(value-triple
              (list :P3-FC-NONTERM-ADMITTED
                    (acl2::logical-namep 'p3_bad_fc_rec (w state))))"""),
        ("p3_ccg_fc_thm_nil_check",
         "(defthm p3_contradiction_1 nil :rule-classes nil :hints ((\"Goal\" :use ((:instance p3_bad_fc_rec (x 0))))))",
         "(value-triple :P3-FC-THM-NIL-AFTER)"),

        # Test 3B: Direct rewrite rule with (force nil) during CCG termination proof
        ("p3_ccg_force_rw_setup",
         """(progn
              (defun p3_trig2 (x) (declare (xargs :guard t)) (consp x))
              (defthm p3_forced_rw
                (implies (and (p3_trig2 x) (acl2::force nil))
                         (equal (acl2-count (cons 1 x)) 0))))""",
         "(value-triple :P3-RW-SETUP-DONE)"),
        ("p3_ccg_force_rw_nonterm_attempt",
         """(defun p3_bad_rw_rec (x)
              (declare (xargs :mode :logic))
              (if (p3_trig2 x)
                  (1+ (p3_bad_rw_rec (cons 1 x)))
                0))""",
         """(value-triple
              (list :P3-RW-NONTERM-ADMITTED
                    (acl2::logical-namep 'p3_bad_rw_rec (w state))))"""),

        # Test 3C: defstobj + updater/accessor under acl2s-common redefun+rewrite
        ("p3_stobj_under_acl2s",
         """(progn
              (acl2::defstobj p3_st (p3_fld :type integer :initially 0))
              (defun p3_bump (p3_st)
                (declare (xargs :stobjs p3_st))
                (let ((v (p3_fld p3_st)))
                  (update-p3_fld (+ v 1) p3_st))))""",
         "(value-triple (list :P3-STOBJ-OK (acl2::logical-namep 'p3_bump (w state))))"),
    ])

    # Random CCG mutual-recursion & loop/branch stress cases
    for i in range(rand_count):
        fn1 = f"p3_fz_{i}_a"
        fn2 = f"p3_fz_{i}_b"
        step1 = rng.choice(["(1- x)", "(+ x 1)", "x", "(ash x -1)"])
        step2 = rng.choice(["(1- y)", "(+ y 1)", "y"])
        nonterm = ("+ " in step1 or step1 == "x") and ("+ " in step2 or step2 == "y")
        form = (
            f"(acl2::mutual-recursion "
            f"(defun {fn1} (x) (declare (xargs :mode :logic)) (if (zp x) 0 ({fn2} {step1}))) "
            f"(defun {fn2} (y) (declare (xargs :mode :logic)) (if (zp y) 0 ({fn1} {step2}))))"
        )
        cases.append((
            f"p3_rand_ccg_{i}",
            form,
            f"(value-triple (list :P3-RAND-CCG '{fn1} :NONTERM {str(nonterm).upper()} :ADMITTED (acl2::logical-namep '{fn1} (w state))))"
        ))

    return cases


def run_acl2_batch(acl2_bin: str, cases, shadow_books: str, timeout_s: int = 85):
    script_lines = ['(in-package "ACL2S")']
    for cid, form, oracle in cases:
        script_lines.append(f'(cw "~%>>> CASE {cid}~%")')
        script_lines.append(form)
        script_lines.append(oracle)
    script_text = "\n".join(script_lines) + "\n"

    fd, tf_path = tempfile.mkstemp(prefix="w4-acl2s-batch-", suffix=".lisp")
    os.close(fd)
    try:
        Path(tf_path).write_text(script_text)
        cmd = [TIMEOUT_BIN, "--kill-after=5s", f"{timeout_s}s", acl2_bin]
        env = os.environ.copy()
        env["ACL2_SYSTEM_BOOKS"] = shadow_books
        wrapper = (
            PREAMBLE
            + f'\n(ld "{tf_path}" :ld-error-action :continue)\n'
            + '(in-package "ACL2S")\n'
            + '(thm nil)\n'
            + '(value-triple :W4-ACL2S-FINAL-CANARY)\n'
        )
        proc = subprocess.run(cmd, input=wrapper, text=True, capture_output=True, env=env)
        return proc.returncode, proc.stdout, proc.stderr
    finally:
        if os.path.exists(tf_path):
            os.unlink(tf_path)


def analyze_acl2s_output(stdout: str):
    findings = []
    parts = re.split(r">>> CASE ([^\r\n]+)", stdout)
    case_outputs = {}
    for i in range(1, len(parts), 2):
        cid = parts[i].strip()
        body = parts[i + 1]
        case_outputs[cid] = body

        # 1. Raw Lisp crashes / aborts
        if "ABORTING from raw Lisp" in body or "Unhandled memory fault" in body or "Fault during read of memory address" in body:
            errs = [ln.strip() for ln in body.splitlines() if "Error:" in ln or "ABORTING" in ln or "While executing:" in ln]
            findings.append(("RAW_LISP_ABORT", cid, " | ".join(errs[:4])))

        # 2. Differential match mismatches
        m_diff = re.search(r":DIFF-MATCH-ID\s+(\d+)\s+:EXP\s+(-?\d+)\s+:GOT\s+(-?\d+)", body)
        if m_diff and m_diff.group(2) != m_diff.group(3):
            findings.append((
                "MATCH_SEMANTIC_MISMATCH",
                cid,
                f"Expected {m_diff.group(2)}, ACL2s match returned {m_diff.group(3)}"
            ))

        # 3. Targeted match bugs
        if cid == "p2_match_bang_unbound" and ":M-BANG-UNB-ADMITTED NIL" in body:
            findings.append((
                "MATCH_BANG_UNBOUND_REJECTED",
                cid,
                "(match y ((b_fresh . !b_fresh) t) (& nil)) failed translation because !b_fresh is tested outside let binding"
            ))
        if cid == "p2_match_bang_outer_capture":
            m_cap = re.search(r":M-BANG-CAP-SAME\s+(-?\d+)\s+:M-BANG-CAP-OUTER\s+(-?\d+)", body)
            if m_cap and (m_cap.group(1) != "7" or m_cap.group(2) != "-1"):
                findings.append((
                    "MATCH_OUTER_VAR_CAPTURE_MISCOMPILATION",
                    cid,
                    f"(m_bang_cap 99 '(7 . 7)) => {m_cap.group(1)} (expected 7); "
                    f"(m_bang_cap 99 '(42 . 99)) => {m_cap.group(2)} (expected -1)!"
                ))
        if cid == "p2_match_t_guard_unbound" and ":M-TGUARD-UNB-ADMITTED NIL" in body:
            findings.append((
                "MATCH_TGUARD_UNBOUND_REJECTED",
                cid,
                ":t guard referencing newly bound pattern vars failed translation (emitted outside let)"
            ))
        if cid == "p2_match_t_guard_outer_capture":
            m_tg = re.search(r":M-TGUARD-CAP-1\s+(-?\d+)\s+:M-TGUARD-CAP-2\s+(-?\d+)", body)
            if m_tg and (m_tg.group(1) != "3" or m_tg.group(2) != "-1"):
                findings.append((
                    "MATCH_TGUARD_OUTER_VAR_CAPTURE",
                    cid,
                    f"(m_tguard_cap 100 0 '(1 . 2)) => {m_tg.group(1)} (expected 3); "
                    f"(m_tguard_cap 1 2 '(100 . 0)) => {m_tg.group(2)} (expected -1)!"
                ))
        if cid == "p2_match_nested_or":
            m_or = re.search(r":M-NESTED-OR-1\s+(-?\d+)\s+:M-NESTED-OR-KW\s+(-?\d+)", body)
            if m_or and (m_or.group(1) != "42" or m_or.group(2) == "42"):
                findings.append((
                    "MATCH_NESTED_OR_MISCOMPILATION",
                    cid,
                    f"(((:or 1 2) . x)) on '(1 . 42) => {m_or.group(1)} (expected 42); "
                    f"on literal '((:or 1 2) . 42) => {m_or.group(2)}!"
                ))
        if cid in ("p2_match_bare_bang", "p2_match_bare_star") and "NIL)" in body:
            findings.append(("MATCH_ATOM_PATTERN_BUG", cid, body.strip()[:240]))

        # 4. Cross-package record / definec / defunc
        if cid == "p1_rec_cross_pkg_exploit" and "Q.E.D." in body:
            findings.append(("DEFDATA_RECORD_CROSS_PKG_SOUNDNESS", cid, "Proved both natp and stringp of p1_rpkg-a!"))
        if cid == "p1_rec_cross_pkg_fields" and ":P1-RPKG-EXISTS NIL" in body:
            # Check error reason
            findings.append(("DEFDATA_RECORD_CROSS_PKG_COLLISION", cid, body.strip()[:300]))
        if cid in ("p2_definec_cross_pkg_formals", "p2_defunc_cross_pkg_formals"):
            findings.append(("INFO_CROSS_PKG_FORMALS", cid, " ".join(body.split())[:260]))
        if cid in ("p2_definec_ic_free_var", "p2_definec_oc_free_var") and " T)" in body:
            findings.append(("DEFINEC_FREE_VAR_ADMITTED", cid, " ".join(body.split())[:260]))
        if cid == "p2_defunc_false_relational_oc" and ":DU-BAD-REL-ADMITTED T" in body:
            findings.append(("UNSOUND_RELATIONAL_OC", cid, "False relational :oc admitted!"))

        # 5. map.lisp ?valpred & defdata-core avoid-lst inspection
        if cid == "p1_map_direct_events_check":
            findings.append(("INFO_MAP_DIRECT_EVENTS", cid, " ".join(body.split())[:350]))
        if cid in ("p1_map_symkey_compval", "p1_map_symkey_consval", "p1_map_compkey_symval", "p1_mut_map_newkey_oldval", "p1_mut_map_oldkey_newval") and "NIL)" in body:
            findings.append(("DEFDATA_MAP_VALPRED_FAILURE", cid, " ".join(body.split())[:300]))
        if cid in ("p1_avoid_self_d", "p1_avoid_v1_collision", "p1_avoid_cons_collision") and "NIL)" in body:
            findings.append(("DEFDATA_AVOID_LST_FAILURE", cid, " ".join(body.split())[:300]))

        # 6. CCG ttree fc-derivation / force checks
        if cid == "p3_ccg_fc_nonterm_attempt" and ":P3-FC-NONTERM-ADMITTED NIL" not in body and ":P3-FC-NONTERM-ADMITTED" in body:
            findings.append(("CRITICAL_CCG_TTREE_BYPASS", cid, "Non-terminating function admitted under CCG via force/fc-derivation!!"))
        if cid == "p3_ccg_force_rw_nonterm_attempt" and ":P3-RW-NONTERM-ADMITTED NIL" not in body and ":P3-RW-NONTERM-ADMITTED" in body:
            findings.append(("CRITICAL_CCG_TTREE_BYPASS", cid, "Non-terminating function admitted under CCG via forced rewrite!!"))
        if cid == "p3_ccg_fc_thm_nil_check" and "Q.E.D." in body:
            findings.append(("CRITICAL_SOUNDNESS_THM_NIL", cid, "Proved NIL via CCG fc-derivation leak!!"))
        m_ccg = re.search(r":NONTERM\s+T\s+:ADMITTED\s+T", body)
        if m_ccg:
            findings.append(("CRITICAL_CCG_RAND_NONTERM", cid, body.strip()[:200]))

        # 7. False subtype / disjoint / sig must fail
        if ":MUST-FAIL-" in body and "Q.E.D." in body and "FAILED" not in body:
            findings.append(("UNSOUND_DEFDATA_RELATION", cid, body.strip()[:240]))

    # Final canary check
    tail = stdout.split(":W4-ACL2S-FINAL-CANARY")[0][-1500:] if ":W4-ACL2S-FINAL-CANARY" in stdout else stdout[-1500:]
    if "Q.E.D." in tail and "(THM NIL)" in tail.upper():
        findings.append(("CRITICAL_FINAL_THM_NIL", "final_canary", "(thm nil) proved Q.E.D.!"))

    return findings, len(case_outputs)


def main():
    ap = argparse.ArgumentParser(description="Wave-4 Deep ACL2s Mechanical Fuzzer")
    ap.add_argument("--seed", type=int, default=20261114)
    ap.add_argument("--runtime", choices=["sbcl", "ccl", "both"], default="both")
    ap.add_argument("--rand-count", type=int, default=25)
    ap.add_argument("--json-out", type=str, default="")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    p1 = gen_pipeline1_defdata(rng, args.rand_count)
    p2 = gen_pipeline2_match_and_definec(rng, args.rand_count)
    p3 = gen_pipeline3_ccg_and_stobj(rng, max(10, args.rand_count // 2))
    all_cases = p1 + p2 + p3

    runtimes = []
    if args.runtime in ("sbcl", "both"):
        runtimes.append(("SBCL-2.6.10", SBCL_ACL2))
    if args.runtime in ("ccl", "both"):
        runtimes.append(("CCL-1.14", CCL_ACL2))

    summary = {"seed": args.seed, "total_cases_per_runtime": len(all_cases), "runs": {}}

    tmp_root = Path(tempfile.mkdtemp(prefix="w4-fv-", dir="/tmp"))
    try:
        shadow_books = build_shadow_books(tmp_root)
        for label, acl2_bin in runtimes:
            print(f"=== [fuzz_acl2s_deep] Running {len(all_cases)} cases on {label} ===")
            rc, out, err = run_acl2_batch(acl2_bin, all_cases, shadow_books, timeout_s=85)
            findings, executed = analyze_acl2s_output(out)
            summary["runs"][label] = {
                "rc": rc,
                "cases_executed": executed,
                "stdout_bytes": len(out),
                "findings": findings,
            }
            print(f"[{label}] rc={rc}, executed={executed}/{len(all_cases)}, findings={len(findings)}")
            for kind, cid, detail in findings:
                print(f"  * [{kind}] {cid}: {detail}")
            if err.strip():
                print(f"  [stderr] {err[:300]}")
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
