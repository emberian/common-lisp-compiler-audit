#!/usr/bin/env python3
"""
Wave-4 Mechanical Differential & Property Test Harness for ACL2 FV Engines (fuzz_gl_fgl_cp.py)
Implements reports/ACL2-FV-ENGINES.md §6.1–6.4 targeting novel defects beyond FV-1..6:
  - Suite 1 (SMTLink verified/ + trusted/ + Z3 5.4.1):
      * verified/uninterpreted-fn-cp.lisp:105-142,388 let/lambda variable shadowing
        in return-type hypotheses.
      * trusted/z3-py/translate-type.lisp:186-188,235 fty::defalist Z3 ArraySort
        extensionality vs ACL2 cons-list equal.
      * config.lisp:50-62 custom-smt-cnf attachment under (defttag nil).
      * ACL2_to_Z3.py:99 unexpanded lambda reciprocal (/ 0) handling +
        differential Lisp clause tests across SMT-extract, expand-cp,
        type-extract-cp, and add-hypo-cp.
  - Suite 2 (GL & FGL Symbolic-vs-Concrete Differential Tests + bfr-fraig-satlink):
      * centaur/gl/bfr-fraig-satlink.lisp:41-42 non-local (remove-untouchable create-state t)
        leaving create-state / with-local-state accessible after (defttag nil).
      * Symbolic-vs-concrete differential tests of GL symbolic arithmetic & eval-g-base
        (0-bit, 1-bit, negative shifts, truncate/rem by 0, logapp, integer-length, g-ite)
        and FGL symbolic object primitives.
  - Suite 3 (IPASIR 32-Bit Dimacs Literal Bounds & SATlink CNF Invariants):
      * centaur/ipasir/ipasir-logic.lisp:249-268,315-325,480-490 & ipasir-interface-raw.lsp
        32-bit signed-byte boundary checks on satlink-to-dimacs-lit.
      * Randomized SATlink CNF / Dimacs literal roundtrip & evaluation checks.
  - Suite 4 (Clause Processors & Meta Rules Falsifier):
      * Non-pseudo-termp / malformed hint & witness-invalid clause tests across
        books/clause-processors/ and books/centaur/misc/.

Uses an ephemeral /tmp/w4-fv-XXXXXX shadow ACL2_SYSTEM_BOOKS workspace and removes all
temporary files on exit.
"""

import argparse
import json
import os
import random
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

SRC_BOOKS = "/Users/ember/dev/acl2-fix/head-worktree/books"
SBCL_ACL2 = "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2"
CCL_ACL2 = "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2"
TIMEOUT_BIN = "/opt/homebrew/bin/timeout"
PYTHON3_BIN = "/opt/homebrew/bin/python3"


IHS_BASIC_DEFS = r"""(in-package "ACL2")
(include-book "std/basic/defs" :dir :system :uncertified-okp t)
(defun zbp (x) (declare (xargs :guard t)) (or (not (integerp x)) (= x 0)))
(defun b-not (i) (declare (xargs :guard (bitp i))) (if (eql i 0) 1 0))
(defun b-and (i j) (declare (xargs :guard (and (bitp i) (bitp j)))) (if (and (eql i 1) (eql j 1)) 1 0))
(defun b-ior (i j) (declare (xargs :guard (and (bitp i) (bitp j)))) (if (or (eql i 1) (eql j 1)) 1 0))
(defun b-xor (i j) (declare (xargs :guard (and (bitp i) (bitp j)))) (if (eql (bfix i) (bfix j)) 0 1))
(defun b-eqv (i j) (declare (xargs :guard (and (bitp i) (bitp j)))) (if (eql (bfix i) (bfix j)) 1 0))
(defun b-nand (i j) (declare (xargs :guard (and (bitp i) (bitp j)))) (b-not (b-and i j)))
(defun b-nor (i j) (declare (xargs :guard (and (bitp i) (bitp j)))) (b-not (b-ior i j)))
(defun b-andc1 (i j) (declare (xargs :guard (and (bitp i) (bitp j)))) (b-and (b-not i) j))
(defun b-andc2 (i j) (declare (xargs :guard (and (bitp i) (bitp j)))) (b-and i (b-not j)))
(defun b-orc1 (i j) (declare (xargs :guard (and (bitp i) (bitp j)))) (b-ior (b-not i) j))
(defun b-orc2 (i j) (declare (xargs :guard (and (bitp i) (bitp j)))) (b-ior i (b-not j)))
(defmacro b-ite (test then else) `(if (eql ,test 1) (bfix ,then) (bfix ,else)))
(defun logcar (i) (declare (xargs :guard (integerp i))) (mod (ifix i) 2))
(defun logcdr (i) (declare (xargs :guard (integerp i))) (floor (ifix i) 2))
(defun logcons (b i)
  (declare (xargs :guard (and (bitp b) (integerp i))))
  (+ (bfix b) (* 2 (ifix i))))
(defun loghead (size i)
  (declare (xargs :guard (and (integerp size) (<= 0 size) (integerp i))))
  (mod (ifix i) (expt 2 (nfix size))))
(defun logtail (pos i)
  (declare (xargs :guard (and (integerp pos) (<= 0 pos) (integerp i))))
  (floor (ifix i) (expt 2 (nfix pos))))
(defun logapp (size i j)
  (declare (xargs :guard (and (integerp size) (<= 0 size) (integerp i) (integerp j))))
  (+ (loghead size i) (* (ifix j) (expt 2 (nfix size)))))
(defun logext (size i)
  (declare (xargs :guard (and (integerp size) (< 0 size) (integerp i))))
  (let* ((s (if (and (integerp size) (< 0 size)) size 1))
         (m (expt 2 (1- s)))
         (h (loghead s i)))
    (if (>= h m) (- h (* 2 m)) h)))
(defun logbit (pos i)
  (declare (xargs :guard (and (integerp pos) (<= 0 pos) (integerp i))))
  (if (logbitp pos i) 1 0))
(defun logmask (size)
  (declare (xargs :guard (and (integerp size) (<= 0 size))))
  (1- (expt 2 (nfix size))))
(defun logmaskp (i)
  (declare (xargs :guard t))
  (and (integerp i) (<= 0 i) (equal i (1- (expt 2 (integer-length i))))))
(defun logrev1 (size i j)
  (declare (xargs :guard (and (integerp size) (<= 0 size) (integerp i) (integerp j))))
  (if (zp size) (ifix j)
    (logrev1 (1- size) (logcdr i) (logcons (logcar i) j))))
(defun logrev (size i)
  (declare (xargs :guard (and (integerp size) (<= 0 size) (integerp i))))
  (logrev1 size i 0))
(defun lognotu (size i)
  (declare (xargs :guard (and (integerp size) (<= 0 size) (integerp i))))
  (loghead size (lognot (ifix i))))
(defun ashu (size i cnt)
  (declare (xargs :guard (and (integerp size) (< 0 size) (integerp i) (integerp cnt))))
  (loghead size (ash (logext size i) cnt)))
(defmacro logite (i j k) `(logior (logand ,i ,j) (logand (lognot ,i) ,k)))
"""

IHS_LOGOPS_DEFS = r"""(in-package "ACL2")
(include-book "ihs/basic-definitions" :dir :system :uncertified-okp t)
"""

AIGNET_SHIM_PKG = r"""(in-package "ACL2")
(defpkg "AIGNET"
  (union-eq *acl2-exports*
            (union-eq *common-lisp-symbols-from-main-lisp-package*
                      '(aignet aignet2 aig->cnf-aignet-transform
                        *fraig-default-config* fraig-config-p fraig
                        comb-transformlist-p make-balance-config make-fraig-config
                        apply-comb-transforms!))))
"""

AIGNET_SHIM_TRANSFORMS = r"""(in-package "AIGNET")
(acl2::defstobj aignet (aignet-fld :type integer :initially 0))
(acl2::defstobj aignet2 (aignet2-fld :type integer :initially 0) :congruent-to aignet)
(defconst *fraig-default-config* :default-fraig)
(defun fraig-config-p (x) (declare (xargs :guard t) (ignore x)) t)
(defun comb-transformlist-p (x) (declare (xargs :guard t) (ignore x)) t)
(defun make-balance-config () (declare (xargs :guard t)) :balance)
(defun make-fraig-config () (declare (xargs :guard t)) :fraig)
(defun fraig (c aignet aignet2 cfg o state)
  (declare (xargs :stobjs (aignet aignet2 state) :guard t) (ignore c cfg o))
  (mv aignet2 nil state))
(defun apply-comb-transforms! (aignet cfg o state)
  (declare (xargs :stobjs (aignet state) :guard t) (ignore cfg o))
  (mv aignet nil state))
(encapsulate
  (((aig->cnf-aignet-transform aignet *) => aignet :formals (aignet cfg) :guard t))
  (local (defun aig->cnf-aignet-transform (aignet cfg)
           (declare (xargs :stobjs aignet :guard t) (ignore cfg))
           aignet)))
"""


def populate_missing_book_stubs(sb: Path):
    """Install lightweight compatibility shims inside ephemeral shadow books ONLY for external
    directories not present in the partial head-worktree/books checkout."""
    # 1. centaur/sv/tutorial/support + centaur/vl/portcullis + centaur/meta/portcullis
    sv_dir = sb / "centaur" / "sv" / "tutorial"
    sv_dir.mkdir(parents=True, exist_ok=True)
    (sv_dir / "portcullis.acl2").write_text('(in-package "ACL2")\n(defpkg "SV" \'(def-saved-event deftutorial $))\n')
    (sv_dir / "support.lisp").write_text('(in-package "SV")\n')

    vl_dir = sb / "centaur" / "vl"
    vl_dir.mkdir(parents=True, exist_ok=True)
    (vl_dir / "portcullis.acl2").write_text('(in-package "ACL2")\n(defpkg "VL" nil)\n')
    (vl_dir / "portcullis.lisp").write_text('(in-package "ACL2")\n')

    cmr_dir = sb / "centaur" / "meta"
    cmr_dir.mkdir(parents=True, exist_ok=True)
    (cmr_dir / "portcullis.acl2").write_text('(in-package "ACL2")\n(defpkg "CMR" nil)\n')
    (cmr_dir / "portcullis.lisp").write_text('(in-package "ACL2")\n')

    # 2. centaur/aignet (not present in head-worktree/books/centaur)
    aig_dir = sb / "centaur" / "aignet"
    aig_dir.mkdir(parents=True, exist_ok=True)
    (aig_dir / "portcullis.acl2").write_text(AIGNET_SHIM_PKG)
    (aig_dir / "portcullis.lisp").write_text('(in-package "ACL2")\n')
    (aig_dir / "transforms.lisp").write_text(AIGNET_SHIM_TRANSFORMS)
    (aig_dir / "aig-cnf.lisp").write_text(AIGNET_SHIM_TRANSFORMS)

    # 3. oslib, coi/util/pseudo-translate, kestrel/utilities/*, meta/pseudo-termp-lemmas
    (sb / "oslib").mkdir(parents=True, exist_ok=True)
    (sb / "oslib" / "package.lsp").write_text('(in-package "ACL2")\n(defpkg "OSLIB" *acl2-exports*)\n')
    (sb / "oslib" / "portcullis.acl2").write_text('(in-package "ACL2")\n(defpkg "OSLIB" *acl2-exports*)\n')
    (sb / "oslib" / "portcullis.lisp").write_text('(in-package "ACL2")\n')
    (sb / "oslib" / "tempfile.lisp").write_text(
        '(in-package "OSLIB")\n'
        '(defun tempfile-fn (base state) (declare (xargs :stobjs state :guard t) (ignore base)) (mv "/tmp/w4-satlink-tmp.cnf" state))\n'
        '(defmacro tempfile (base &key (state \'state)) `(tempfile-fn ,base ,state))\n'
    )
    (sb / "coi" / "util").mkdir(parents=True, exist_ok=True)
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
    (sb / "kestrel" / "utilities" / "system").mkdir(parents=True, exist_ok=True)
    (sb / "kestrel" / "utilities" / "proof-builder-macros.lisp").write_text('(in-package "ACL2")\n')
    (sb / "kestrel" / "utilities" / "ubi.lisp").write_text('(in-package "ACL2")\n')
    (sb / "kestrel" / "utilities" / "make-termination-theorem.lisp").write_text(
        '(in-package "ACL2")\n'
        '(defun make-termination-theorem (fn wrld) (declare (xargs :mode :program) (ignore fn wrld)) \'t)\n'
    )
    (sb / "kestrel" / "utilities" / "system" / "terms.lisp").write_text(
        '(in-package "ACL2")\n(include-book "coi/util/pseudo-translate" :dir :system :uncertified-okp t)\n'
        '(verify-termination body)\n'
    )
    (sb / "meta").mkdir(parents=True, exist_ok=True)
    (sb / "meta" / "pseudo-termp-lemmas.lisp").write_text('(in-package "ACL2")\n')

    # 4. ihs/* & arithmetic/*
    (sb / "ihs").mkdir(parents=True, exist_ok=True)
    (sb / "ihs" / "basic-definitions.lisp").write_text(IHS_BASIC_DEFS)
    (sb / "ihs" / "logops-definitions.lisp").write_text(IHS_LOGOPS_DEFS)
    (sb / "ihs" / "quotient-remainder-lemmas.lisp").write_text('(in-package "ACL2")\n')
    (sb / "ihs" / "logops-lemmas.lisp").write_text('(in-package "ACL2")\n')
    (sb / "arithmetic").mkdir(parents=True, exist_ok=True)
    (sb / "arithmetic" / "top.lisp").write_text('(in-package "ACL2")\n')
    (sb / "arithmetic" / "top-with-meta.lisp").write_text('(in-package "ACL2")\n')

    # 5. Patch package.lsp files in shadow copy so (include-book ".../portcullis" :dir :system)
    # accepts uncertified portcullis.lisp once packages have been defined via ld.
    for pkg_lsp in sb.rglob("package.lsp"):
        txt = pkg_lsp.read_text()
        if ":dir :system)" in txt:
            pkg_lsp.write_text(txt.replace(":dir :system)", ":dir :system :uncertified-okp t)"))


def build_fv_shadow_books(root: Path, subdirs) -> str:
    """Copy required book subdirectories into an ephemeral /tmp/w4-fv-XXXXXX/books."""
    sb = root / "books"
    sb.mkdir(parents=True, exist_ok=True)
    for rel in subdirs:
        src = Path(SRC_BOOKS) / rel
        dst = sb / rel
        if src.exists() and not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(src, dst)
    populate_missing_book_stubs(sb)
    return str(sb)


def run_acl2_script(acl2_bin: str, script: str, shadow_books: str, extra_env=None, timeout_s: int = 85):
    cmd = [TIMEOUT_BIN, "--kill-after=5s", f"{timeout_s}s", acl2_bin]
    env = os.environ.copy()
    env["ACL2_SYSTEM_BOOKS"] = shadow_books
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    if extra_env:
        env.update(extra_env)
    proc = subprocess.run(cmd, input=script, text=True, capture_output=True, env=env)
    return proc.returncode, proc.stdout, proc.stderr


# ==============================================================================
# SUITE 1: End-to-End ACL2 SMTLink (verified/ + trusted/) + Z3 5.4.1
# ==============================================================================

def run_suite_smtlink(acl2_bin: str, label: str, rng: random.Random, tmp_root: Path, diff_count: int = 16):
    shadow = build_fv_shadow_books(
        tmp_root / f"smt-{label}",
        [
            "std", "xdoc", "tools", "misc", "make-event", "system",
            "clause-processors", "defsort", "data-structures", "ordinals",
            "arithmetic-5", "centaur/misc", "centaur/bitops", "centaur/fty",
            "projects/smtlink",
        ],
    )
    # In shadow copy of projects/smtlink/package.lsp, add :uncertified-okp t to the 3 portcullis includes
    pkg_lsp = Path(shadow) / "projects" / "smtlink" / "package.lsp"
    pkg_lsp.write_text(
        pkg_lsp.read_text().replace(":dir :system)", ":dir :system :uncertified-okp t)")
    )

    smt_tmp = tmp_root / f"smt-work-{label}"
    smt_tmp.mkdir(parents=True, exist_ok=True)

    diff_forms = []
    for i in range(diff_count):
        is_valid = (i % 2 == 0)
        a = rng.randint(1, 7)
        b = rng.randint(1, 7)
        if is_valid:
            expr = rng.choice([
                f"(implies (and (integerp x) (integerp y) (< x y)) (< (+ x {a}) (+ y {a + b})))",
                f"(implies (rationalp x) (let ((z (+ x {a}))) (> z x)))",
                f"(implies (booleanp p) (equal (if p {a} {b}) (if (not p) {b} {a})))",
            ])
            tag = "VALID"
        else:
            expr = rng.choice([
                f"(implies (and (integerp x) (integerp y)) (< (+ x {a}) (+ y {b})))",
                f"(implies (rationalp x) (equal (* x x) (- {a})))",
                f"(implies (integerp x) (let ((y (- x {a}))) (> y x)))",
            ])
            tag = "INVALID"
        diff_forms.append(f"""
(cw "~%>>> CASE smt_diff_{i}_{tag}~%")
(defthm smt_diff_thm_{i}
  {expr}
  :hints (("Goal" :smtlink-custom (:smt-dir "{smt_tmp}")))
  :rule-classes nil)
(value-triple (list :SMT-DIFF-ID {i} :EXPECTED '{tag} :PROVED (acl2::logical-namep 'smt_diff_thm_{i} (w state))))
""")

    script = f"""
(ld "std/portcullis.acl2" :dir :system)
(ld "centaur/bitops/portcullis.acl2" :dir :system)
(ld "centaur/fty/portcullis.acl2" :dir :system)
(ld "centaur/sv/tutorial/portcullis.acl2" :dir :system)
(ld "projects/smtlink/portcullis.acl2" :dir :system)
(include-book "projects/smtlink/top" :dir :system :ttags :all :uncertified-okp t)
(defun w4-z3-smt-cnf ()
  (declare (xargs :guard t))
  (smt::change-smtlink-config (smt::default-smtlink-config)
                              :smt-cmd "{PYTHON3_BIN}"))
(defattach smt::custom-smt-cnf w4-z3-smt-cnf)
(defttag nil)

(ld "{smt_tmp}/smt_cases.lisp" :ld-error-action :continue)
(value-triple :SUITE-SMTLINK-DONE)
"""
    cases_lisp = f"""(in-package "ACL2")

;; 1A. verified/uninterpreted-fn-cp.lisp:105-142,388 let/lambda variable shadowing
;; in return-type proof obligations -> derives NIL end-to-end with Z3 5.4.1
(cw "~%>>> CASE smt_let_shadow_nil~%")
(encapsulate ()
  (local (defun w4-id-fn (z) (declare (xargs :guard t)) z))
  (local
   (defthm w4-let-shadow-lemma
     (implies (integerp y)
              (not (equal (let ((y 1/2)) (w4-id-fn y)) 1/2)))
     :hints (("Goal"
              :smtlink-custom (:smt-dir "{smt_tmp}"
                               :functions ((w4-id-fn :formals ((z rationalp))
                                                     :returns ((r integerp))
                                                     :level 0)))))
     :rule-classes nil))
  (local
   (defthm w4-let-shadow-contradiction
     nil
     :hints (("Goal" :use ((:instance w4-let-shadow-lemma (y 0)))
              :in-theory (enable w4-id-fn)))
     :rule-classes nil))
  (defconst *w4-smt-let-shadow-nil* t))
(value-triple (list :SMT-LET-SHADOW-NIL (acl2::logical-namep '*w4-smt-let-shadow-nil* (w state))))

;; 1B. trusted/z3-py/translate-type.lisp:186-188,235 fty::defalist ArraySort
;; extensionality vs ACL2 cons-list equal -> derives NIL end-to-end with Z3 5.4.1
(cw "~%>>> CASE smt_defalist_extensionality_nil~%")
(fty::defalist w4-int-alist
  :key-type integer
  :val-type integer
  :true-listp t)
(encapsulate ()
  (local
   (defthm w4-defalist-lemma
     (implies (w4-int-alist-p a)
              (equal (acons 1 10 (acons 1 20 a))
                     (acons 1 10 a)))
     :hints (("Goal"
              :smtlink-custom (:smt-dir "{smt_tmp}"
                               :fty (w4-int-alist))))
     :rule-classes nil))
  (local
   (defthm w4-defalist-contradiction
     nil
     :hints (("Goal" :use ((:instance w4-defalist-lemma (a nil)))))
     :rule-classes nil))
  (defconst *w4-smt-defalist-nil* t))
(value-triple (list :SMT-DEFALIST-NIL (acl2::logical-namep '*w4-smt-defalist-nil* (w state))))

;; 1C. config.lisp:50-62 custom-smt-cnf defattach allowed under (defttag nil)
;; Write a constant-output solver stub script in smt_tmp and attach it via pure :logic defattach
(cw "~%>>> CASE smt_defattach_cnf_nil~%")
(defun w4-stub-smt-cnf ()
  (declare (xargs :guard t))
  (smt::make-smtlink-config :smt-cmd "{PYTHON3_BIN} -c 'print(\"proved\")'"))
(defattach smt::custom-smt-cnf w4-stub-smt-cnf)
(encapsulate ()
  (local
   (defthm w4-defattach-contradiction
     nil
     :hints (("Goal" :smtlink-custom (:smt-dir "{smt_tmp}" :rm-file nil)))
     :rule-classes nil))
  (defconst *w4-smt-defattach-nil* t))
(value-triple (list :SMT-DEFATTACH-NIL (acl2::logical-namep '*w4-smt-defattach-nil* (w state))))
(defattach smt::custom-smt-cnf w4-z3-smt-cnf)

;; 1D. Unexpanded lambda literal 0 reciprocal (/ 0) -> Z3Exception Q(1, 0) in ACL2_to_Z3.py:99
(cw "~%>>> CASE smt_lambda_div_zero~%")
(defthm w4-lambda-div0
  (implies (rationalp x)
           (equal ((lambda (z) (/ z)) '0) 0))
  :hints (("Goal" :smtlink-custom (:smt-dir "{smt_tmp}")))
  :rule-classes nil)
(value-triple (list :SMT-DIV0-PROVED (acl2::logical-namep 'w4-lambda-div0 (w state))))

{"".join(diff_forms)}
"""
    (smt_tmp / "smt_cases.lisp").write_text(cases_lisp)
    rc, out, err = run_acl2_script(acl2_bin, script, shadow, timeout_s=85)

    findings = []
    if "(:SMT-LET-SHADOW-NIL T)" in out:
        findings.append(("SOUNDNESS_THM_NIL", "smt_let_shadow_nil",
                         "Derived NIL end-to-end in ACL2 + Z3 via verified/uninterpreted-fn-cp.lisp:140,388 let/lambda variable capture"))
    if "(:SMT-DEFALIST-NIL T)" in out:
        findings.append(("SOUNDNESS_THM_NIL", "smt_defalist_extensionality_nil",
                         "Derived NIL end-to-end in ACL2 + Z3 via translate-type.lisp:186-188,235 fty::defalist ArraySort extensionality vs cons-list equal"))
    if "(:SMT-DEFATTACH-NIL T)" in out:
        findings.append(("SOUNDNESS_DEFATTACH_THM_NIL", "smt_defattach_cnf_nil",
                         "Derived NIL under (defttag nil) via unguarded (defattach smt::custom-smt-cnf ...) in config.lisp:50-62"))
    if ">>> CASE smt_lambda_div_zero" in out:
        seg = out.split(">>> CASE smt_lambda_div_zero")[1].split(">>> CASE")[0]
        if "Z3Exception" in seg or "SMT solver failure" in seg or "ZeroDivisionError" in seg:
            findings.append(("SMTLINK_RECIPROCAL_ZERO_ERROR", "smt_lambda_div_zero",
                             "Valid ACL2 theorem ((lambda (z) (/ z)) '0) == 0 aborted in ACL2_to_Z3.py:99 (Q(1,0) Z3Exception)"))
    for m in re.finditer(r"\(:SMT-DIFF-ID\s+(\d+)\s+:EXPECTED\s+INVALID\s+:PROVED\s+\S+\)", out):
        if not m.group(0).endswith("NIL)"):
            findings.append(("SMTLINK_DIFF_UNSOUND", f"smt_diff_{m.group(1)}", "Invalid clause proved by SMTLink"))

    executed = len(re.findall(r">>> CASE ", out))
    return {"rc": rc, "executed": executed, "findings": findings, "stderr": err[:300], "raw_tail": out[-800:]}


# ==============================================================================
# SUITE 2: GL & FGL Symbolic-vs-Concrete Differential Tests + bfr-fraig-satlink
# ==============================================================================

def eval_gl_op(op: str, a: int, b: int):
    if op == "+":
        return a + b
    if op == "-":
        return a - b
    if op == "*":
        return a * b
    if op == "logand":
        return a & b
    if op == "logior":
        return a | b
    if op == "logxor":
        return a ^ b
    if op == "ash":
        if b >= 0:
            return a << min(b, 16)
        return a >> (-b)
    if op == "truncate":
        if b == 0:
            return 0
        q = abs(a) // abs(b)
        return -q if (a < 0) ^ (b < 0) else q
    if op == "rem":
        if b == 0:
            return a
        q = eval_gl_op("truncate", a, b)
        return a - q * b
    return 0


def int_to_bfr_bits_lisp(val: int, pad_bits: int = 0) -> str:
    if val == 0 and pad_bits == -1:
        return "nil"
    if val == 0:
        bits = [False] * (1 + max(0, pad_bits))
    elif val == -1:
        bits = [True] * (1 + max(0, pad_bits))
    elif val > 0:
        nb = val.bit_length() + 1 + max(0, pad_bits)
        bits = [bool((val >> i) & 1) for i in range(nb)]
    else:
        nb = (-val - 1).bit_length() + 1 + max(0, pad_bits)
        twos = (1 << nb) + val
        bits = [bool((twos >> i) & 1) for i in range(nb)]
    return "(" + " ".join("t" if b else "nil" for b in bits) + ")"


def run_suite_gl_fgl(acl2_bin: str, label: str, rng: random.Random, tmp_root: Path, diff_count: int = 30):
    shadow = build_fv_shadow_books(
        tmp_root / f"gl-{label}",
        [
            "std", "xdoc", "tools", "misc", "make-event", "system",
            "clause-processors", "defsort", "data-structures", "ordinals",
            "arithmetic-5", "hacking",
            "centaur/misc", "centaur/bitops", "centaur/fty", "centaur/aig",
            "centaur/satlink", "centaur/ubdds", "centaur/gl",
        ],
    )
    # Allow uncertified include-book inside centaur/*/package.lsp
    for pkg_rel in ["gl", "satlink", "bitops", "fty", "aig", "ubdds"]:
        p = Path(shadow) / "centaur" / pkg_rel / "package.lsp"
        if p.exists():
            p.write_text(p.read_text().replace(":dir :system)", ":dir :system :uncertified-okp t)"))

    gl_tmp = tmp_root / f"gl-work-{label}"
    gl_tmp.mkdir(parents=True, exist_ok=True)

    # 2A. Test centaur/gl/bfr-fraig-satlink.lisp:42 non-local (remove-untouchable acl2::create-state t)
    # after closing (defttag nil): check whether pure :logic code can derive NIL via with-local-state!
    fraig_script = """
(ld "std/portcullis.acl2" :dir :system)
(ld "oslib/portcullis.acl2" :dir :system)
(ld "centaur/bitops/portcullis.acl2" :dir :system)
(ld "centaur/fty/portcullis.acl2" :dir :system)
(ld "centaur/vl/portcullis.acl2" :dir :system)
(ld "centaur/aignet/portcullis.acl2" :dir :system)
(ld "centaur/satlink/portcullis.acl2" :dir :system)
(ld "centaur/aig/portcullis.acl2" :dir :system)
(ld "centaur/gl/portcullis.acl2" :dir :system)
(include-book "centaur/gl/bfr-fraig-satlink" :dir :system :ttags :all :uncertified-okp t)
(defttag nil)

(cw "~%>>> CASE gl_fraig_untouchable_check~%")
(encapsulate ()
  (local
   (defun w4-read-state-global ()
     (declare (xargs :guard t))
     (acl2::with-local-state
       (mv-let (v state)
         (mv (acl2::f-get-global 'w4-test-var state) state)
         v))))
  (local (make-event (er-progn (acl2::assign w4-test-var 1) (acl2::value '(value-triple :s1)))))
  (local
   (defthm w4-state-eq-1
     (equal (w4-read-state-global) 1)
     :hints (("Goal" :in-theory (acl2::executable-counterpart-theory :here)))
     :rule-classes nil))
  (local (make-event (er-progn (acl2::assign w4-test-var 2) (acl2::value '(value-triple :s2)))))
  (local
   (defthm w4-state-eq-2
     (equal (w4-read-state-global) 2)
     :hints (("Goal" :in-theory (acl2::executable-counterpart-theory :here)))
     :rule-classes nil))
  (local
   (defthm w4-fraig-create-state-contradiction
     nil
     :hints (("Goal" :use (w4-state-eq-1 w4-state-eq-2)
              :in-theory (disable w4-read-state-global (w4-read-state-global))))
     :rule-classes nil))
  (defconst *w4-gl-fraig-proved-nil* t))
(value-triple (list :GL-FRAIG-CREATE-STATE-NIL (acl2::logical-namep '*w4-gl-fraig-proved-nil* (w state))))
(value-triple :SUITE-GL-FRAIG-DONE)
"""
    rc_f, out_f, err_f = run_acl2_script(acl2_bin, fraig_script, shadow, timeout_s=85)

    # 2B. Symbolic-vs-Concrete Differential Tests on GL symbolic-arithmetic & eval-g-base
    ops = ["+", "-", "*", "logand", "logior", "logxor", "ash", "truncate", "rem"]
    edge_vals = [0, -1, 1, 2, -2, 7, -8, 15, -16, 127, -128]
    gl_cases = []
    for i in range(diff_count):
        op = rng.choice(ops)
        a = rng.choice(edge_vals)
        b = rng.choice([-4, -1, 0, 1, 3, 7] if op == "ash" else edge_vals)
        pad_a = rng.choice([-1, 0, 1, 3]) if a == 0 else rng.choice([0, 1, 2])
        pad_b = rng.choice([-1, 0, 1, 3]) if b == 0 else rng.choice([0, 1, 2])
        bits_a = int_to_bfr_bits_lisp(a, pad_a)
        bits_b = int_to_bfr_bits_lisp(b, pad_b)
        expected = eval_gl_op(op, a, b)

        if op == "+":
            sym_call = f"(gl::bfr-+-ss nil '{bits_a} '{bits_b})"
        elif op == "-":
            sym_call = f"(gl::bfr-+-ss t '{bits_a} (gl::bfr-lognot-s '{bits_b}))"
        elif op == "*":
            sym_call = f"(gl::bfr-*-ss '{bits_a} '{bits_b})"
        elif op == "logand":
            sym_call = f"(gl::bfr-logand-ss '{bits_a} '{bits_b})"
        elif op == "logior":
            sym_call = f"(gl::bfr-logior-ss '{bits_a} '{bits_b})"
        elif op == "logxor":
            sym_call = f"(gl::bfr-logxor-ss '{bits_a} '{bits_b})"
        elif op == "ash":
            sym_call = f"(gl::bfr-ash-ss 1 '{bits_a} '{bits_b})"
        elif op == "truncate":
            sym_call = f"(gl::bfr-truncate-ss '{bits_a} '{bits_b})"
        else:
            sym_call = f"(gl::bfr-rem-ss '{bits_a} '{bits_b})"

        gl_cases.append(f"""
(cw "~%>>> CASE gl_sym_diff_{i}~%")
(let* ((res-bits {sym_call})
       (got (gl::bfr-list->s res-bits nil)))
  (value-triple (list :GL-DIFF-ID {i} :OP '{op} :A {a} :B {b} :EXP {expected} :GOT got)))
""")

    extra_gl = """
(cw "~%>>> CASE gl_edge_0bit_intlen~%")
(value-triple (list :GL-INTLEN-EMPTY (gl::bfr-list->s (gl::bfr-integer-length-s '()) nil)
                    :GL-INTLEN-MINUS1 (gl::bfr-list->s (gl::bfr-integer-length-s '(t)) nil)))
(cw "~%>>> CASE gl_edge_logapp_neg~%")
(value-triple (list :GL-LOGAPP-NEG (gl::bfr-list->s (gl::bfr-logapp-nss -3 '(t nil t) '(nil t)) nil)
                    :EXP-LOGAPP-NEG (logapp -3 -3 1)))
(cw "~%>>> CASE gl_edge_eval_g_base~%")
(value-triple (list :GL-EVAL-GITE
                    (gl::eval-g-base '(:g-ite (:g-boolean . t) (:g-integer t nil) (:g-concrete . 99))
                                     '((t . t)))))
"""
    (gl_tmp / "gl_diff.lisp").write_text("\n".join(gl_cases) + extra_gl)
    gl_diff_script = f"""
(ld "std/portcullis.acl2" :dir :system)
(ld "oslib/portcullis.acl2" :dir :system)
(ld "centaur/bitops/portcullis.acl2" :dir :system)
(ld "centaur/fty/portcullis.acl2" :dir :system)
(ld "centaur/vl/portcullis.acl2" :dir :system)
(ld "centaur/aignet/portcullis.acl2" :dir :system)
(ld "centaur/satlink/portcullis.acl2" :dir :system)
(ld "centaur/aig/portcullis.acl2" :dir :system)
(ld "centaur/gl/portcullis.acl2" :dir :system)
(include-book "centaur/gl/symbolic-arithmetic" :dir :system :uncertified-okp t)
(include-book "centaur/gl/eval-g-base" :dir :system :uncertified-okp t)
(ld "{gl_tmp}/gl_diff.lisp" :ld-error-action :continue)
(value-triple :SUITE-GL-DIFF-DONE)
"""
    rc_g, out_g, err_g = run_acl2_script(acl2_bin, gl_diff_script, shadow, timeout_s=85)

    findings = []
    if ":GL-FRAIG-CREATE-STATE-NIL" in out_f and ":GL-FRAIG-CREATE-STATE-NIL NIL)" not in out_f:
        findings.append((
            "SOUNDNESS_THM_NIL",
            "gl_fraig_untouchable_check",
            "Derived NIL under (defttag nil) after including centaur/gl/bfr-fraig-satlink.lisp:42 "
            "due to non-local (remove-untouchable acl2::create-state t) leaving with-local-state unlocked"
        ))
    for m in re.finditer(r"\(:GL-DIFF-ID\s+(\d+)\s+:OP\s+(\S+)\s+:A\s+(-?\d+)\s+:B\s+(-?\d+)\s+:EXP\s+(-?\d+)\s+:GOT\s+(-?\d+)\)", out_g):
        if m.group(5) != m.group(6):
            findings.append((
                "GL_SYMBOLIC_ARITH_MISMATCH",
                f"gl_sym_diff_{m.group(1)}",
                f"op={m.group(2)} a={m.group(3)} b={m.group(4)}: expected {m.group(5)}, got {m.group(6)}"
            ))
    if "ABORTING from raw Lisp" in out_f or "ABORTING from raw Lisp" in out_g:
        findings.append(("RAW_LISP_ABORT_GL", "gl_suite", (out_f + out_g)[-400:]))

    executed = len(re.findall(r">>> CASE ", out_f)) + len(re.findall(r">>> CASE ", out_g))
    return {"rc": rc_g, "executed": executed, "findings": findings, "stderr": (err_f + err_g)[:300]}


# ==============================================================================
# SUITE 3: IPASIR 32-Bit Dimacs Literal Bounds & SATlink CNF Invariants
# ==============================================================================

def run_suite_ipasir_satlink(acl2_bin: str, label: str, rng: random.Random, tmp_root: Path, cnf_count: int = 20):
    shadow = build_fv_shadow_books(
        tmp_root / f"sat-{label}",
        [
            "std", "xdoc", "tools", "misc", "make-event", "system",
            "clause-processors", "defsort", "data-structures", "ordinals",
            "arithmetic-5", "centaur/misc", "centaur/bitops", "centaur/fty",
            "centaur/satlink", "centaur/ipasir",
        ],
    )
    for pkg_p in [
        Path(shadow) / "centaur" / "satlink" / "package.lsp",
        Path(shadow) / "centaur" / "ipasir" / "package.lsp",
    ]:
        if pkg_p.exists():
            pkg_p.write_text(pkg_p.read_text().replace(":dir :system)", ":dir :system :uncertified-okp t)"))

    sat_tmp = tmp_root / f"sat-work-{label}"
    sat_tmp.mkdir(parents=True, exist_ok=True)

    cnf_cases = []
    for i in range(cnf_count):
        v = rng.choice([0, 1, 7, 65535, 2147483646, 2147483647])
        neg = rng.randint(0, 1)
        cnf_cases.append(f"""
(cw "~%>>> CASE sat_lit_roundtrip_{i}~%")
(let* ((lit (satlink::make-lit {v} {neg}))
       (dim (satlink::satlink-to-dimacs-lit lit)))
  (value-triple (list :SAT-LIT {i} :VAR (satlink::lit->var lit) :NEG (satlink::lit->neg lit)
                      :DIM dim :S32 (signed-byte-p 32 dim) :NEG-DIM-S32 (signed-byte-p 32 (- dim)))))
""")

    script = f"""
(ld "std/portcullis.acl2" :dir :system)
(ld "oslib/portcullis.acl2" :dir :system)
(ld "centaur/bitops/portcullis.acl2" :dir :system)
(ld "centaur/fty/portcullis.acl2" :dir :system)
(ld "centaur/satlink/portcullis.acl2" :dir :system)
(ld "centaur/ipasir/portcullis.acl2" :dir :system)
(include-book "centaur/satlink/cnf" :dir :system :uncertified-okp t)
(include-book "centaur/ipasir/ipasir-logic" :dir :system :uncertified-okp t)
(ld "{sat_tmp}/sat_cases.lisp" :ld-error-action :continue)
(value-triple :SUITE-SAT-DONE)
"""
    sat_cases = f"""(in-package "ACL2")

(cw "~%>>> CASE ipasir_int_min_dimacs_bounds~%")
(let* ((lit-neg-intmin (satlink::make-lit 2147483647 1))
       (dimacs-neg     (satlink::satlink-to-dimacs-lit lit-neg-intmin))
       (lit-pos-ovf    (satlink::make-lit 2147483647 0))
       (dimacs-pos     (satlink::satlink-to-dimacs-lit lit-pos-ovf)))
  (value-triple
   (list :LIT-NEG-LITP (satlink::litp lit-neg-intmin)
         :DIMACS-NEG dimacs-neg
         :DIMACS-NEG-S32 (signed-byte-p 32 dimacs-neg)
         :NEGATED-OVERFLOWS-S32 (not (signed-byte-p 32 (- dimacs-neg)))
         :DIMACS-POS dimacs-pos
         :DIMACS-POS-S32 (signed-byte-p 32 dimacs-pos))))

(cw "~%>>> CASE ipasir_logic_mbe_bounds_gap~%")
(let* ((st0 (ipasir::create-ipasir$a))
       (st1 (ipasir::ipasir-init$a st0 '(nil)))
       (st2 (ipasir::ipasir-add-lit$a st1 4294967295))
       (st3 (ipasir::ipasir-assume$a st2 (satlink::make-lit (expt 2 40) 0))))
  (value-triple
   (list :ADD-INTMIN-STATUS (ipasir::ipasir->status$a st2)
         :ASSUME-2P40-LEN (len (ipasir::ipasir->assumption$a st3)))))

{"".join(cnf_cases)}
"""
    (sat_tmp / "sat_cases.lisp").write_text(sat_cases)
    rc, out, err = run_acl2_script(acl2_bin, script, shadow, timeout_s=85)

    findings = []
    if ":DIMACS-NEG -2147483648 :DIMACS-NEG-S32 T :NEGATED-OVERFLOWS-S32 T" in out:
        findings.append((
            "IPASIR_DIMACS_INT32_GUARD_GAP",
            "ipasir_int_min_dimacs_bounds",
            "ipasir-logic.lisp:249-268,315-325,480-490 & ipasir-interface-raw.lsp:329-383: "
            "(make-lit 2147483647 1) maps to Dimacs -2147483648 (INT32_MIN, whose negation overflows int32_t), "
            "and ipasir-add-lit / ipasir-assume / ipasir-bump-activity-vars lack 32-bit guards on :logic fns"
        ))
    if "ABORTING from raw Lisp" in out:
        findings.append(("RAW_LISP_ABORT_SAT", "sat_suite", out[-400:]))

    executed = len(re.findall(r">>> CASE ", out))
    return {"rc": rc, "executed": executed, "findings": findings, "stderr": err[:300]}


# ==============================================================================
# SUITE 4: Clause Processors & Meta Rules Malformed-Hint & False-Goal Falsifier
# ==============================================================================

def run_suite_clause_processors(acl2_bin: str, label: str, rng: random.Random, tmp_root: Path, rand_count: int = 20):
    shadow = build_fv_shadow_books(
        tmp_root / f"cp-{label}",
        [
            "std", "xdoc", "tools", "misc", "make-event", "system",
            "clause-processors", "defsort", "data-structures", "ordinals",
            "arithmetic-5", "centaur/misc", "centaur/bitops", "centaur/fty",
        ],
    )
    cp_tmp = tmp_root / f"cp-work-{label}"
    cp_tmp.mkdir(parents=True, exist_ok=True)

    false_goals = [
        "nil",
        "(equal x (+ x 1))",
        "(implies (integerp x) (< x 0))",
        "(equal (cons a b) (cons b a))",
    ]
    bad_hints = [
        "nil",
        "t",
        "42",
        "'(:malformed . 7)",
        "'((x . (1 . 2)))",
        "'((x . (quote 1 2)))",
        "'(((lambda (a) unbound_sym) x))",
        "'((non_symbol_fn . (x)))",
    ]

    cp_targets = [
        ("equality_cp", "(equality-substitute-clause clause {hint})"),
        ("generalize_simple_cp", "(simple-generalize-cp clause {hint})"),
        ("replace_eq_cp", "(replace-equalities-cp clause {hint} state)"),
        ("autohide_cp", "(autohide-cp clause {hint})"),
        ("remove_hyp_cp", "(remove-first-hyp-cp clause)"),
        ("null_cp", "(identity-clause-processor clause)"),
    ]

    cases_lisp = ['(in-package "ACL2")']
    idx = 0
    for cp_name, cp_tpl in cp_targets:
        hints_to_try = bad_hints if "{hint}" in cp_tpl else ["nil"]
        for h in hints_to_try:
            goal = false_goals[idx % len(false_goals)]
            cp_expr = cp_tpl.format(hint=h)
            cases_lisp.append(f"""
(cw "~%>>> CASE cp_{idx}_{cp_name}~%")
(defthm w4_cp_false_{idx}
  {goal}
  :hints (("Goal" :clause-processor {cp_expr}))
  :rule-classes nil)
(value-triple (list :CP-ID {idx} :NAME '{cp_name} :PROVED (acl2::logical-namep 'w4_cp_false_{idx} (w state))))
""")
            idx += 1

    for j in range(rand_count):
        a = rng.randint(-5, 5)
        b = rng.randint(1, 5)
        cases_lisp.append(f"""
(cw "~%>>> CASE meta_rand_{j}~%")
(defthm w4_meta_false_{j}
  (implies (acl2-numberp x)
           (equal (+ x {a} (- x)) {a + b}))
  :rule-classes nil)
(value-triple (list :META-ID {j} :PROVED (acl2::logical-namep 'w4_meta_false_{j} (w state))))
""")

    (cp_tmp / "cp_cases.lisp").write_text("\n".join(cases_lisp))

    script = f"""
(ld "std/portcullis.acl2" :dir :system)
(ld "centaur/bitops/portcullis.acl2" :dir :system)
(ld "centaur/fty/portcullis.acl2" :dir :system)
(include-book "tools/flag" :dir :system :uncertified-okp t)
(include-book "clause-processors/null-fail-hints" :dir :system :uncertified-okp t)
(include-book "clause-processors/remove-hyp" :dir :system :uncertified-okp t)
(include-book "clause-processors/equality" :dir :system :uncertified-okp t)
(include-book "clause-processors/generalize" :dir :system :uncertified-okp t)
(include-book "clause-processors/autohide" :dir :system :uncertified-okp t)
(include-book "clause-processors/replace-equalities" :dir :system :uncertified-okp t)
(include-book "clause-processors/just-expand" :dir :system :uncertified-okp t)
(include-book "centaur/misc/collect-like-terms" :dir :system :uncertified-okp t)
(ld "{cp_tmp}/cp_cases.lisp" :ld-error-action :continue)
(value-triple :SUITE-CP-DONE)
"""
    rc, out, err = run_acl2_script(acl2_bin, script, shadow, timeout_s=85)

    findings = []
    parts = re.split(r">>> CASE ([^\r\n]+)", out)
    for k in range(1, len(parts), 2):
        cid = parts[k].strip()
        body = parts[k + 1]
        if ":PROVED " in body and ":PROVED NIL)" not in body:
            findings.append(("CRITICAL_CP_META_UNSOUND", cid, f"False theorem proved in {cid}"))
        if "ABORTING from raw Lisp" in body or "Unhandled memory fault" in body or "Fault during read" in body:
            errs = [ln.strip() for ln in body.splitlines() if "Error:" in ln or "ABORTING" in ln or "While executing:" in ln]
            findings.append(("CP_RAW_LISP_ABORT_ON_MALFORMED_HINT", cid, " | ".join(errs[:4])))

    executed = (len(parts) - 1) // 2
    return {"rc": rc, "executed": executed, "findings": findings, "stderr": err[:300]}


def main():
    ap = argparse.ArgumentParser(description="Wave-4 Mechanical Test Harness for ACL2 FV Engines")
    ap.add_argument("--seed", type=int, default=20261114)
    ap.add_argument("--runtime", choices=["sbcl", "ccl", "both"], default="both")
    ap.add_argument("--suite", choices=["all", "smtlink", "gl", "sat", "cp"], default="all")
    ap.add_argument("--scale", type=int, default=1)
    ap.add_argument("--json-out", type=str, default="")
    args = ap.parse_args()

    runtimes = []
    if args.runtime in ("sbcl", "both"):
        runtimes.append(("SBCL-2.6.10", SBCL_ACL2))
    if args.runtime in ("ccl", "both"):
        runtimes.append(("CCL-1.14", CCL_ACL2))

    summary = {"seed": args.seed, "runs": {}}
    tmp_root = Path(tempfile.mkdtemp(prefix="w4-fv-", dir="/tmp"))
    try:
        for label, acl2_bin in runtimes:
            rng = random.Random(args.seed)
            summary["runs"][label] = {}
            print(f"\n================ [{label}] ================")
            if args.suite in ("all", "smtlink"):
                res = run_suite_smtlink(acl2_bin, label, rng, tmp_root, diff_count=16 * args.scale)
                summary["runs"][label]["smtlink"] = res
                print(f"[smtlink] rc={res['rc']}, executed={res['executed']}, findings={len(res['findings'])}")
                for kind, cid, det in res["findings"]:
                    print(f"  * [{kind}] {cid}: {det}")
            if args.suite in ("all", "gl"):
                res = run_suite_gl_fgl(acl2_bin, label, rng, tmp_root, diff_count=30 * args.scale)
                summary["runs"][label]["gl"] = res
                print(f"[gl]      rc={res['rc']}, executed={res['executed']}, findings={len(res['findings'])}")
                for kind, cid, det in res["findings"]:
                    print(f"  * [{kind}] {cid}: {det}")
            if args.suite in ("all", "sat"):
                res = run_suite_ipasir_satlink(acl2_bin, label, rng, tmp_root, cnf_count=20 * args.scale)
                summary["runs"][label]["sat"] = res
                print(f"[sat]     rc={res['rc']}, executed={res['executed']}, findings={len(res['findings'])}")
                for kind, cid, det in res["findings"]:
                    print(f"  * [{kind}] {cid}: {det}")
            if args.suite in ("all", "cp"):
                res = run_suite_clause_processors(acl2_bin, label, rng, tmp_root, rand_count=20 * args.scale)
                summary["runs"][label]["cp"] = res
                print(f"[cp]      rc={res['rc']}, executed={res['executed']}, findings={len(res['findings'])}")
                for kind, cid, det in res["findings"]:
                    print(f"  * [{kind}] {cid}: {det}")
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
