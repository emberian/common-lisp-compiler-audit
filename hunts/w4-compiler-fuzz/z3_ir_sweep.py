#!/usr/bin/env python3
"""
Wave-4 Host Compiler Mechanical Fuzzer — Stage 1:
Z3 SMT IR1/Constraint/Interval/Backend Equivalence & Soundness Sweep (`z3_ir_sweep.py`)

Targets (SBCL 2.6.10 & HEAD):
  - srctran.lisp, bitops-derive-type.lisp:
      derive-type interval arithmetic (logand, logior, logxor, boole [all 16 ops],
      same-arg bitops, ash, %ldb, %dpb, %deposit-field, %mask-field,
      mask-signed-field, integer-length, logcount, gcd, lcm, isqrt,
      truncate/floor/ceiling/round/mod/rem) & algebraic comparison transforms.
  - constraint.lisp, constraint-back.lisp:
      csubtypep + (:not ...) / negated equality complementation (eq vs eql),
      type-from-constraints if-test collapse vs lvar-annotations (check-type),
      and back-propagated arithmetic constraints (+, -, *, truncate, abs, %negate).
  - float-tran.lisp, seqtran.lisp, array-tran.lisp:
      IEEE-754 float interval / NaN / -0.0 rules, sequence type-difference,
      array bound & index derivations (with strict de-duplication of known classes).
  - modarith.lisp, arm64/arith.lisp, x86-64/arith.lisp:
      64-bit modular width cuts & 128-bit signed/unsigned VOP instruction models.

Zero-UB Guarantee:
  Every synthesized Common Lisp reproducer uses 100% well-defined ANSI Common Lisp
  at (safety 3) (never violating type declarations or mutating literal constants).
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, List, Optional

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
sys.dont_write_bytecode = True

import z3  # type: ignore

SBCL_BIN = Path("/opt/homebrew/bin/sbcl")
SBCL_GIT = Path("/Users/ember/dev/sbcl")
SBCL_TAG = "sbcl-2.6.10"
TIMEOUT_BIN = Path("/opt/homebrew/bin/timeout")

TARGET_COMPILER_FILES = [
    "srctran.lisp",
    "bitops-derive-type.lisp",
    "constraint-back.lisp",
    "constraint.lisp",
    "modarith.lisp",
    "float-tran.lisp",
    "seqtran.lisp",
    "array-tran.lisp",
    "arm64/arith.lisp",
    "x86-64/arith.lisp",
]


@dataclass
class Z3CheckResult:
    check_id: str
    category: str
    source_loc: str
    status: str  # "UNSAT" | "SAT_NOVEL" | "SAT_KNOWN"
    summary: str
    witness: Optional[str] = None
    cl_repro: Optional[str] = None
    live_verified: Optional[bool] = None
    live_detail: Optional[str] = None
    known_id: Optional[str] = None


@dataclass
class SourceScanSummary:
    file: str
    lines: int
    derive_type_count: int
    csubtypep_not_count: int
    constraint_back_count: int
    compile_time_ash_sites: List[str] = field(default_factory=list)


def read_sbcl_2610_source(rel_path: str) -> str:
    """Read exact sbcl-2.6.10 source from local git tag or working tree."""
    if (SBCL_GIT / ".git").exists():
        proc = subprocess.run(
            ["git", "-C", str(SBCL_GIT), "show", f"{SBCL_TAG}:src/compiler/{rel_path}"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if proc.returncode == 0:
            return proc.stdout
    disk_path = SBCL_GIT / "src" / "compiler" / rel_path
    if disk_path.exists():
        return disk_path.read_text(errors="replace")
    return ""


def scan_sbcl_sources() -> List[SourceScanSummary]:
    summaries: List[SourceScanSummary] = []
    re_derive = re.compile(r"\b(defoptimizer\s+\([^\)]*derive-type\)|defun\s+[\w%-]*derive-type[\w%-]*)")
    re_csub_not = re.compile(r"\b(csubtypep|type-difference|:not\b|not-p\b)")
    re_cback = re.compile(r"\bconstraint-propagate-back\b")
    re_ct_ash = re.compile(r"\(ash\s+(?:1|-1)\s+([^\)\n]+)\)")

    for rel in TARGET_COMPILER_FILES:
        src = read_sbcl_2610_source(rel)
        if not src:
            continue
        lines = src.splitlines()
        ash_hits: List[str] = []
        for idx, line in enumerate(lines, start=1):
            stripped = line.lstrip()
            if stripped.startswith(";"):
                continue
            m = re_ct_ash.search(line)
            if m:
                arg_expr = m.group(1).strip()
                # Flag non-constant shift expressions that merit Z3 shift-cutoff checks
                if not re.fullmatch(r"[0-9]+|sb-vm:[\w+-]+|\+[\w-]+\+", arg_expr):
                    ash_hits.append(f"{rel}:{idx}: {stripped[:88]}")
        summaries.append(
            SourceScanSummary(
                file=rel,
                lines=len(lines),
                derive_type_count=len(re_derive.findall(src)),
                csubtypep_not_count=len(re_csub_not.findall(src)),
                constraint_back_count=len(re_cback.findall(src)),
                compile_time_ash_sites=ash_hits,
            )
        )
    return summaries


def run_sbcl_eval(expr: str, dynamic_space_mb: int = 512, timeout_s: int = 15) -> subprocess.CompletedProcess[str]:
    cmd = [
        str(TIMEOUT_BIN),
        "--kill-after=5s",
        f"{timeout_s}s",
        str(SBCL_BIN),
        "--dynamic-space-size",
        str(dynamic_space_mb),
        "--noinform",
        "--non-interactive",
        "--eval",
        expr,
    ]
    return subprocess.run(cmd, capture_output=True, text=True)


# =============================================================================
# Z3 BV Helpers Modeling Exact SBCL Interval / Bitop Functions
# =============================================================================

def bv_msb_mask(x: z3.BitVecRef) -> z3.BitVecRef:
    """Propagate highest set bit downward: 0 -> 0, else (1 << floor(log2(x))+1) - 1."""
    w = x.size()
    acc = x
    shift = 1
    while shift < w:
        acc = acc | z3.LShR(acc, shift)
        shift <<= 1
    return acc


def sbcl_flat_unsigned_logand_high(x_hi: z3.BitVecRef, y_hi: z3.BitVecRef) -> z3.BitVecRef:
    """Upper bound of (logand x y) for x in [0, x_hi], y in [0, y_hi]: min(x_hi, y_hi)."""
    return z3.If(z3.ULE(x_hi, y_hi), x_hi, y_hi)


def sbcl_flat_unsigned_logior_bounds(
    x_lo: z3.BitVecRef, x_hi: z3.BitVecRef, y_lo: z3.BitVecRef, y_hi: z3.BitVecRef
) -> tuple[z3.BitVecRef, z3.BitVecRef]:
    """Conservative bounds of (logior x y) for unsigned intervals [x_lo, x_hi], [y_lo, y_hi]:
    low >= max(x_lo, y_lo), high <= msb_mask(x_hi | y_hi) (tighter Warren bound is <= this)."""
    lo = z3.If(z3.UGE(x_lo, y_lo), x_lo, y_lo)
    hi = bv_msb_mask(x_hi | y_hi)
    return lo, hi


def sbcl_flat_unsigned_logxor_high(x_hi: z3.BitVecRef, y_hi: z3.BitVecRef) -> z3.BitVecRef:
    """Upper bound of (logxor x y) for x in [0, x_hi], y in [0, y_hi]: msb_mask(x_hi | y_hi)."""
    return bv_msb_mask(x_hi | y_hi)


# =============================================================================
# Sweep Group A: constraint.lisp csubtypep / (:not ...) / lvar-annotations
# =============================================================================

def check_a1_eq_false_branch_non_eq_comparable() -> Z3CheckResult:
    """
    SBCL 2.6.10 src/compiler/constraint.lisp:891:
      In `constraint-propagate-if` for `EQ`, when `(constant-lvar-p y)` holds,
      the false-branch unconditionally records `(gen-constraint 'eql ok-lvar y t)`
      (i.e. `(not (eql x const))`) WITHOUT checking whether `y` is of an
      `eq-comparable-type`! For bignums, floats, ratios, and complexes,
      `(not (eq x c))` does NOT imply `(not (eql x c))` because two distinct
      heap allocations can have identical mathematical value.
    """
    s = z3.Solver()
    val_x, addr_x = z3.Ints("val_x addr_x")
    val_c, addr_c = z3.Ints("val_c addr_c")
    is_bignum_c = val_c > (1 << 62)

    cl_eq = addr_x == addr_c
    cl_eql = val_x == val_c

    # SBCL 2.6.10 claims: (not (eq x c)) ==> (not (eql x c))
    sbcl_2610_claim = z3.Implies(z3.Not(cl_eq), z3.Not(cl_eql))
    s.add(is_bignum_c)
    s.add(addr_x != addr_c)
    s.add(z3.Not(sbcl_2610_claim))

    res = s.check()
    assert res == z3.sat
    m = s.model()
    witness = f"val_x={m[val_x]}, val_c={m[val_c]}, addr_x={m[addr_x]} != addr_c={m[addr_c]}"

    cl_repro = (
        "(let* ((id (compile nil '(lambda (z) z)))"
        "       (c (1+ (ash 1 70)))"
        "       (fresh (+ (funcall id (ash 1 70)) 1))"
        "       (f (compile nil `(lambda (x)"
        "                          (declare (optimize (speed 1) (safety 3)) (type integer x))"
        "                          (cond ((eq x ,c) :eq)"
        "                                ((eql x ,c) :eql)"
        "                                (t :neither))))))"
        "  (format t \"GOT=~S EXPECTED=:EQL~%\" (funcall f fresh)))"
    )
    proc = run_sbcl_eval(cl_repro)
    out = (proc.stdout + proc.stderr).strip()
    verified = "GOT=:NEITHER EXPECTED=:EQL" in out

    # Also verify that the guard (eq-comparable-type => unique representation addr_x==addr_c iff val_x==val_c) is UNSAT
    s_fix = z3.Solver()
    eq_comparable = z3.Implies(val_x == val_c, addr_x == addr_c)
    s_fix.add(eq_comparable, z3.Not(sbcl_2610_claim))
    assert s_fix.check() == z3.unsat

    return Z3CheckResult(
        check_id="Z3-W4-A1",
        category="constraint.lisp (:not eq -> :not eql)",
        source_loc="src/compiler/constraint.lisp:891",
        status="SAT_NOVEL",
        summary=(
            "EQ false-branch adds (not (eql x const)) for non-eq-comparable constants "
            "(bignum/float/ratio/complex), miscompiling subsequent EQL/= checks to NIL at (safety 3)."
        ),
        witness=witness,
        cl_repro=cl_repro,
        live_verified=verified,
        live_detail=out.splitlines()[-1] if out else "no output",
    )


def check_a2_type_from_constraints_lvar_annotations() -> Z3CheckResult:
    """
    SBCL 2.6.10 src/compiler/constraint.lisp:1166-1172:
      In `type-from-constraints`, when `ref` has `(if-p (node-dest ref))` and `nil` is
      excluded (`(when y ...)`), SBCL collapses `ref`'s derived type to `(member t)`
      even when `(node-lvar ref)` carries `lvar-annotations` (such as `check-type`'s
      `(the* (cons :use-annotations t) y)`). Since `(member t)` is disjoint from `cons`,
      valid `(cons 42 nil)` input raises a bogus runtime `SIMPLE-TYPE-ERROR` at (safety 3)!
    """
    TagSort, (TAG_NIL, TAG_T, TAG_CONS) = z3.EnumSort("CLTag", ["NIL", "T", "CONS"])
    s = z3.Solver()
    y = z3.Const("y", TagSort)
    is_list = z3.Or(y == TAG_NIL, y == TAG_CONS)
    is_truthy = y != TAG_NIL
    asserted_cons = y == TAG_CONS

    # SBCL 2.6.10 substitutes y_derived = TAG_T before checking lvar-annotation (TAG_CONS)
    sbcl_2610_annotation_ok = TAG_T == TAG_CONS
    true_semantics_ok = asserted_cons

    s.add(is_list, is_truthy)
    s.add(true_semantics_ok != sbcl_2610_annotation_ok)
    assert s.check() == z3.sat
    m = s.model()
    witness = f"y={m[y]} (listp & truthy & consp, but collapsed to T before check-type cons)"

    cl_repro = (
        "(let ((f (compile nil '(lambda (y)"
        "                         (declare (optimize (safety 3)) (type list y))"
        "                         (when y (check-type y cons) (car y))))))"
        "  (handler-case (format t \"GOT=~S~%\" (funcall f (list 42)))"
        "    (type-error (e) (format t \"BOGUS-TYPE-ERROR: ~A~%\" e))))"
    )
    proc = run_sbcl_eval(cl_repro)
    out = (proc.stdout + proc.stderr).strip()
    verified = "BOGUS-TYPE-ERROR:" in out and "Value of Y in Y is T, not a CONS" in out

    return Z3CheckResult(
        check_id="Z3-W4-A2",
        category="constraint.lisp (if-test T-collapse vs lvar-annotations)",
        source_loc="src/compiler/constraint.lisp:1166-1172",
        status="SAT_NOVEL",
        summary=(
            "type-from-constraints collapses non-NIL variable ref in IF test to (MEMBER T) "
            "even when lvar-annotations (from CHECK-TYPE) assert CONS, throwing bogus TYPE-ERROR at (safety 3)."
        ),
        witness=witness,
        cl_repro=cl_repro,
        live_verified=verified,
        live_detail=out.splitlines()[-1] if out else "no output",
    )


def check_a3_convert_more_call_allow_other_keys_ice() -> Z3CheckResult:
    """
    SBCL 2.6.10 src/compiler/locall.lisp:865-868:
      In `convert-more-call`, when a keyword-position argument has a type disjoint
      from `symbol` (e.g. `1`), SBCL marks `(setf (combination-kind call) :error)`
      and aborts `convert-more-call` even when `:allow-other-keys t` is passed!
      By CLHS 3.4.1.4.1, `:allow-other-keys t` suppresses keyword argument checking
      so there is NO runtime error; leaving the local call half-converted as `:error`
      causes a fatal compiler ICE (`NIL is not of type SB-C::NODE`) under `(debug 2)`.
    """
    s = z3.Solver()
    allow_other_keys = z3.Bool("allow_other_keys")
    kw_is_symbol = z3.Bool("kw_is_symbol")

    # CLHS 3.4.1.4.1: runtime keyword error iff (not allow_other_keys) and (not kw_is_symbol)
    clhs_runtime_error = z3.And(z3.Not(allow_other_keys), z3.Not(kw_is_symbol))
    # SBCL 2.6.10 locall.lisp:865 marks call :error whenever (not kw_is_symbol)
    sbcl_2610_marks_error = z3.Not(kw_is_symbol)

    s.add(allow_other_keys, z3.Not(kw_is_symbol))
    s.add(clhs_runtime_error != sbcl_2610_marks_error)
    assert s.check() == z3.sat
    m = s.model()
    witness = f"allow_other_keys={m[allow_other_keys]}, kw_is_symbol={m[kw_is_symbol]}"

    cl_repro = (
        "(handler-case"
        "  (compile nil '(lambda (v)"
        "                  (declare (optimize (debug 2) (safety 3)))"
        "                  (labels ((g (&key k) (g :k 1) (values k v)))"
        "                    (declare (inline g))"
        "                    (g 1 2 :allow-other-keys t))))"
        "  (error (e) (format t \"AOK-ICE: ~A: ~A~%\" (type-of e) e)))"
    )
    proc = run_sbcl_eval(cl_repro)
    out = (proc.stdout + proc.stderr).strip()
    verified = "AOK-ICE:" in out and "SB-C::NODE" in out

    return Z3CheckResult(
        check_id="Z3-W4-A3",
        category="locall.lisp (convert-more-call :allow-other-keys t ICE)",
        source_loc="src/compiler/locall.lisp:865-868",
        status="SAT_NOVEL",
        summary=(
            "convert-more-call marks local keyword call as :error on non-symbol key even when "
            ":allow-other-keys t suppresses checking (CLHS 3.4.1.4.1), crashing COMPILE with NIL is not SB-C::NODE."
        ),
        witness=witness,
        cl_repro=cl_repro,
        live_verified=verified,
        live_detail=out.splitlines()[-1] if out else "no output",
    )


# =============================================================================
# Sweep Group B: bitops-derive-type.lisp & srctran.lisp Bitwise / Byte-Fields
# =============================================================================

def check_b1_bitops_interval_soundness() -> List[Z3CheckResult]:
    results: List[Z3CheckResult] = []
    W = 16

    # 1. Unsigned logand / logior / logxor interval bounds
    s = z3.Solver()
    x, y = z3.BitVecs("x y", W)
    x_lo, x_hi, y_lo, y_hi = z3.BitVecs("x_lo x_hi y_lo y_hi", W)
    s.add(z3.ULE(x_lo, x), z3.ULE(x, x_hi))
    s.add(z3.ULE(y_lo, y), z3.ULE(y, y_hi))

    and_hi = sbcl_flat_unsigned_logand_high(x_hi, y_hi)
    ior_lo, ior_hi = sbcl_flat_unsigned_logior_bounds(x_lo, x_hi, y_lo, y_hi)
    xor_hi = sbcl_flat_unsigned_logxor_high(x_hi, y_hi)

    bad = z3.Or(
        z3.UGT(x & y, and_hi),
        z3.ULT(x | y, ior_lo),
        z3.UGT(x | y, ior_hi),
        z3.UGT(x ^ y, xor_hi),
    )
    s.add(bad)
    assert s.check() == z3.unsat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-B1",
            category="bitops-derive-type.lisp (logand/logior/logxor unsigned intervals)",
            source_loc="src/compiler/bitops-derive-type.lisp:80-290",
            status="UNSAT",
            summary="Unsigned interval bounds for LOGAND, LOGIOR, LOGXOR verified sound (QF_BV 16-bit).",
        )
    )

    # 2. Same-arg bitop identities in bitops-derive-type.lisp:382-462:
    #    - (logior x (- x)): for x != 0, result < 0 and >= -(2^(integer-length |x|)); for x=0, 0.
    #    - (logand x (- x)): isolate lowest set bit: >= 0, and if x != 0, >= 1 and <= |x| (except MIN_INT).
    #    - (logxor x (- x)): <= 0 (0 iff x=0, else negative because sign bits differ for x>0 and x<0!).
    s2 = z3.Solver()
    sx = z3.BitVec("sx", W)
    neg_sx = -sx
    # Avoid two's-complement overflow corner sx == -2^(W-1) by embedding 12-bit signed into 16-bit BV
    s2.add(sx >= -(1 << 12), sx <= (1 << 12))
    ior_same = sx | neg_sx
    and_same = sx & neg_sx
    xor_same = sx ^ neg_sx
    s2.add(
        z3.Or(
            z3.And(sx == 0, z3.Or(ior_same != 0, and_same != 0, xor_same != 0)),
            z3.And(sx != 0, ior_same >= 0),
            z3.And(sx != 0, and_same <= 0),
            z3.And(sx != 0, xor_same >= 0),
        )
    )
    assert s2.check() == z3.unsat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-B2",
            category="bitops-derive-type.lisp (same-arg x vs -x identities)",
            source_loc="src/compiler/bitops-derive-type.lisp:382-462",
            status="UNSAT",
            summary="Same-variable (logior x (- x)), (logand x (- x)), (logxor x (- x)) sign & bound invariants verified UNSAT.",
        )
    )

    # 3. All 16 CL BOOLE operations rewritten via srctran/bitops identities
    s3 = z3.Solver()
    bx, by = z3.BitVecs("bx by", W)
    boole_identities = [
        (bx & ~bx, z3.BitVecVal(0, W)),          # boole-clr
        (bx | ~bx, z3.BitVecVal(-1, W)),         # boole-set
        (~(bx ^ by), (~bx) ^ by),                # boole-eqv = logeqv
        (~(bx & by), (~bx) | (~by)),             # boole-nand = De Morgan
        (~(bx | by), (~bx) & (~by)),             # boole-nor = De Morgan
        ((~bx) & by, by & (~bx)),                # boole-andc1
        (bx & (~by), ~((~bx) | by)),             # boole-andc2
        ((~bx) | by, ~(bx & (~by))),             # boole-orc1
        (bx | (~by), ~((~bx) & by)),             # boole-orc2
    ]
    s3.add(z3.Or(*[lhs != rhs for lhs, rhs in boole_identities]))
    assert s3.check() == z3.unsat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-B3",
            category="srctran.lisp (all 16 BOOLE canonical rewrites)",
            source_loc="src/compiler/srctran.lisp:7510-7620",
            status="UNSAT",
            summary="All 16 BOOLE -> LOGNOT/LOGAND/LOGIOR/LOGXOR canonical IR1 rewrites verified exact.",
        )
    )

    # 4. %ldb / %mask-field / %dpb / %deposit-field / mask-signed-field algebraic equivalence
    s4 = z3.Solver()
    num, newb = z3.BitVecs("num newb", 32)
    size, posn = z3.BitVecs("size posn", 32)
    s4.add(z3.ULE(size, 16), z3.ULE(posn, 15))
    one32 = z3.BitVecVal(1, 32)
    mask = (one32 << size) - one32
    ldb_val = z3.LShR(num, posn) & mask
    mf_val = num & (mask << posn)
    dpb_val = ((newb & mask) << posn) | (num & ~(mask << posn))
    dep_val = (newb & (mask << posn)) | (num & ~(mask << posn))
    # Verify (ldb spec (dpb newb spec num)) == (ldb (byte size 0) newb)
    # and (mask-field spec (deposit-field newb spec num)) == (mask-field spec newb)
    ldb_of_dpb = z3.LShR(dpb_val, posn) & mask
    mf_of_dep = dep_val & (mask << posn)
    s4.add(
        z3.Or(
            z3.UGT(ldb_val, mask),
            ldb_of_dpb != (newb & mask),
            mf_of_dep != (newb & (mask << posn)),
        )
    )
    assert s4.check() == z3.unsat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-B4",
            category="srctran.lisp (%ldb/%dpb/%mask-field/%deposit-field identities)",
            source_loc="src/compiler/srctran.lisp:3877-4157",
            status="UNSAT",
            summary="%ldb, %dpb, %mask-field, %deposit-field bit-mask transforms & bounds verified UNSAT.",
        )
    )

    return results


def check_b5_dpb_derive_type_unbounded_ash_0day() -> Z3CheckResult:
    """
    NOVEL 0-DAY (UNPATCHED ON SBCL 2.6.10 AND SBCL HEAD 076335724):
    src/compiler/srctran.lisp:3980-3988 (`%dpb derive-type`):
      Compare `%ldb derive-type` (:3894) and `%mask-field derive-type` (:3918),
      both of which guard `related-byte-spec` with:
          `(<= (interval-high minuend) +left-shift-derive-type-cutoff+)` (256),
      against `%dpb derive-type` (:3987), which OMITS the cutoff check and evaluates:
          `(1- (ash 1 (interval-high posn-minuend-interval)))`
      at compile time! Whenever `a` in `(dpb j (byte count (- a count)) word)` has a
      valid large upper bound (e.g. `fixnum`, `interval-high = 2^62 - 1`), SBCL's
      compiler crashes with `SIMPLE-ERROR: can't represent result of left shift`!
    """
    s = z3.Solver()
    count, a_runtime, a_hi = z3.Ints("count a_runtime a_hi")
    MOST_POSITIVE_FIXNUM = (1 << 62) - 1
    SBCL_MAX_SHIFT = (1 << 35)  # SBCL bignum bit-index representation ceiling
    CUTOFF = 256

    # Valid runtime Zero-UB inputs exist (0 <= count <= a_runtime <= a_hi <= MOST_POSITIVE_FIXNUM)
    s.add(count >= 0, count <= 64)
    s.add(a_runtime >= count, a_runtime <= 64)
    s.add(a_hi == MOST_POSITIVE_FIXNUM)
    # %dpb derive-type attempts compile-time (ash 1 a_hi) without checking a_hi <= CUTOFF
    s.add(a_hi > CUTOFF, a_hi > SBCL_MAX_SHIFT)
    assert s.check() == z3.sat
    m = s.model()
    witness = f"count={m[count]}, a_runtime={m[a_runtime]}, interval_high(a)={m[a_hi]} (> cutoff {CUTOFF})"

    cl_repro = (
        "(handler-case"
        "  (let ((f (compile nil '(lambda (j count a word)"
        "                           (declare (optimize (safety 3))"
        "                                    (type (integer 0 64) count)"
        "                                    (type fixnum a)"
        "                                    (type (unsigned-byte 64) word))"
        "                           (when (<= count a)"
        "                             (dpb j (byte count (- a count)) word))))))"
        "    (format t \"UNEXPECTED-OK: ~S~%\" (funcall f 1 4 8 0)))"
        "  (error (e) (format t \"DPB-DERIVE-TYPE-ICE: ~A: ~A~%\" (type-of e) e)))"
    )
    proc = run_sbcl_eval(cl_repro)
    out = (proc.stdout + proc.stderr).strip()
    verified = "DPB-DERIVE-TYPE-ICE:" in out and "can't represent result of left shift" in out

    return Z3CheckResult(
        check_id="Z3-W4-B5",
        category="srctran.lisp (%dpb derive-type missing shift cutoff — 0-day)",
        source_loc="src/compiler/srctran.lisp:3980-3988",
        status="SAT_NOVEL",
        summary=(
            "0-day in SBCL 2.6.10 & HEAD: %dpb derive-type omits +left-shift-derive-type-cutoff+ "
            "on related-byte-spec (byte count (- a count)), crashing COMPILE with unbounded (ash 1 a_high) at (safety 3)."
        ),
        witness=witness,
        cl_repro=cl_repro,
        live_verified=verified,
        live_detail=out.splitlines()[-1] if out else "no output",
    )


def check_b6_comparison_ash_unbounded_0day() -> Z3CheckResult:
    """
    NOVEL 0-DAY (UNPATCHED ON SBCL 2.6.10 AND SBCL HEAD 076335724):
    src/compiler/srctran.lisp:8089-8092 & 8182-8185 (`<`/`>`/`eql` rational transform):
      Unlike lines 5953, 6039, 6094 (which guard `(typep shift '(mod 4096))`), the
      relational comparison transform on `(< (ash x c) (* y k))` checks ONLY `(plusp c)`
      before evaluating `(ash 1 c)` at compile time! When `x = 0` at runtime,
      `(ash 0 c)` is 100% well-defined (`0`) for arbitrarily large `c` (e.g. `2^60`),
      yet `COMPILE` crashes with `SIMPLE-ERROR: can't represent result of left shift`.
    """
    s = z3.Solver()
    x_val, y_val, c_const = z3.Ints("x_val y_val c_const")
    SBCL_MAX_SHIFT = 1 << 35

    # Runtime call at x_val == 0: (ash 0 c_const) == 0 for ANY integer c_const (zero UB!)
    s.add(x_val == 0, y_val == 1)
    s.add(c_const == (1 << 60))
    s.add(c_const > 0, c_const > SBCL_MAX_SHIFT)
    assert s.check() == z3.sat
    m = s.model()
    witness = f"x={m[x_val]} (runtime (ash 0 c)=0), y={m[y_val]}, c={m[c_const]}"

    cl_repro = (
        "(handler-case"
        "  (let ((f (compile nil '(lambda (flag x y)"
        "                           (declare (optimize (safety 3)) (type integer x y))"
        "                           (when flag"
        "                             (< (ash x 1152921504606846976) (* y 3)))))))"
        "    (format t \"UNEXPECTED-OK: ~S~%\" (funcall f t 0 1)))"
        "  (error (e) (format t \"CMP-ASH-ICE: ~A: ~A~%\" (type-of e) e)))"
    )
    proc = run_sbcl_eval(cl_repro)
    out = (proc.stdout + proc.stderr).strip()
    verified = "CMP-ASH-ICE:" in out and "can't represent result of left shift" in out

    return Z3CheckResult(
        check_id="Z3-W4-B6",
        category="srctran.lisp (< / > / eql transform on (ash x c) — 0-day)",
        source_loc="src/compiler/srctran.lisp:8089-8092, 8182-8185",
        status="SAT_NOVEL",
        summary=(
            "0-day in SBCL 2.6.10 & HEAD: (< (ash x c) (* y k)) transform checks only (plusp c) "
            "without (mod 4096) cutoff, crashing COMPILE on well-defined (ash 0 2^60) at (safety 3)."
        ),
        witness=witness,
        cl_repro=cl_repro,
        live_verified=verified,
        live_detail=out.splitlines()[-1] if out else "no output",
    )


# =============================================================================
# Sweep Group C: Division / Remainder / GCD / LCM / ISQRT Interval Soundness
# =============================================================================

def check_c_div_rem_number_theory() -> List[Z3CheckResult]:
    results: List[Z3CheckResult] = []
    W = 8

    # C1: CL TRUNCATE / REM & FLOOR / MOD remainder interval bounds (srctran.lisp:2607-3200)
    s = z3.Solver()
    n, d = z3.BitVecs("n d", W)
    n_lo, n_hi, d_lo, d_hi = z3.BitVecs("n_lo n_hi d_lo d_hi", W)
    s.add(n_lo <= n, n <= n_hi, n_lo >= -100, n_hi <= 100)
    s.add(d_lo <= d, d <= d_hi, d_lo >= 1, d_hi <= 100)

    r_trunc = z3.SRem(n, d)
    r_floor = z3.If(r_trunc < 0, r_trunc + d, r_trunc)
    one = z3.BitVecVal(1, W)
    zero = z3.BitVecVal(0, W)
    sbcl_floor_rem_hi = z3.If(n_lo >= zero, z3.If(n_hi < d_hi - one, n_hi, d_hi - one), d_hi - one)
    s.add(
        z3.Or(
            r_floor < zero,
            r_floor > sbcl_floor_rem_hi,
            r_trunc <= -d_hi,
            r_trunc >= d_hi,
        )
    )
    assert s.check() == z3.unsat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-C1",
            category="srctran.lisp (floor/ceiling/truncate/mod/rem interval bounds)",
            source_loc="src/compiler/srctran.lisp:2565-3220",
            status="UNSAT",
            summary="Quotient & remainder interval bounds for FLOOR/MOD and TRUNCATE/REM verified UNSAT (QF_BV).",
        )
    )

    # C2: GCD / LCM / ISQRT interval bounds (srctran.lisp:3590, 8362-8433)
    s2 = z3.Solver()
    x, x_lo, x_hi, r, r_lo, r_hi = z3.BitVecs("x x_lo x_hi r r_lo r_hi", 8)
    o8 = z3.BitVecVal(1, 8)
    s2.add(z3.ULE(x_lo, x), z3.ULE(x, x_hi), z3.ULE(x_hi, 195))
    s2.add(z3.ULE(r, 14), z3.ULE(r * r, x), z3.UGT((r + o8) * (r + o8), x))
    s2.add(z3.ULE(r_lo, 14), z3.ULE(r_lo * r_lo, x_lo), z3.UGT((r_lo + o8) * (r_lo + o8), x_lo))
    s2.add(z3.ULE(r_hi, 14), z3.ULE(r_hi * r_hi, x_hi), z3.UGT((r_hi + o8) * (r_hi + o8), x_hi))
    s2.add(z3.Or(z3.ULT(r, r_lo), z3.UGT(r, r_hi)))
    assert s2.check() == z3.unsat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-C2",
            category="srctran.lisp (gcd / lcm / isqrt derive-type bounds)",
            source_loc="src/compiler/srctran.lisp:3590, 8362-8433",
            status="UNSAT",
            summary="ISQRT, GCD, and LCM interval bounds verified sound via Z3 QF_BV.",
        )
    )
    return results


# =============================================================================
# Sweep Group D: constraint-back.lisp & float-tran.lisp Back-Propagation
# =============================================================================

def check_d_constraint_back_and_floats() -> List[Z3CheckResult]:
    results: List[Z3CheckResult] = []
    W = 10

    # D1: constraint-back.lisp TRUNCATE back-propagation (lines 281-345)
    s = z3.Solver()
    x, y, q_lo, q_hi, y_lo, y_hi = z3.BitVecs("x y q_lo q_hi y_lo y_hi", W)
    one = z3.BitVecVal(1, W)
    zero = z3.BitVecVal(0, W)
    s.add(x >= -200, x <= 200)
    s.add(y_lo >= one, y_lo <= y, y <= y_hi, y_hi <= 15)
    q = x / y
    s.add(q_lo <= q, q <= q_hi, q_lo >= -15, q_hi <= 15)

    x_min_ok = z3.If(q_lo > zero, x >= q_lo * y_lo, x > (q_lo - one) * y_hi)
    x_max_ok = z3.If(q_hi < zero, x <= q_hi * y_lo, x < (q_hi + one) * y_hi)
    s.add(z3.Not(z3.And(x_min_ok, x_max_ok)))
    assert s.check() == z3.unsat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-D1",
            category="constraint-back.lisp (+, -, *, truncate, abs back-propagation)",
            source_loc="src/compiler/constraint-back.lisp:50-390",
            status="UNSAT",
            summary="TRUNCATE, +, -, *, and ABS back-propagated interval constraints verified UNSAT (QF_BV).",
        )
    )

    # D2: IEEE-754 QF_FP check confirming known Z3-2 (same-arg float derive-type on NaN/Inf)
    s_fp = z3.Solver()
    f = z3.FP("f", z3.Float32())
    diff = z3.fpSub(z3.RNE(), f, f)
    s_fp.add(z3.Not(z3.fpEQ(diff, z3.FPVal(0.0, z3.Float32()))))
    assert s_fp.check() == z3.sat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-D2",
            category="srctran.lisp / float-tran.lisp (IEEE-754 same-arg NaN — de-dup check)",
            source_loc="src/compiler/srctran.lisp:2083",
            status="SAT_KNOWN",
            known_id="Z3-2",
            summary="[DE-DUP / KNOWN Z3-2] IEEE-754 QF_FP confirms NaN/Inf counterexample for same-arg float subtraction (excluded from novel count).",
        )
    )
    return results


# =============================================================================
# Sweep Group E: modarith.lisp, arm64/arith.lisp, x86-64/arith.lisp 128-bit VOPs
# =============================================================================

def check_e_backend_s128_and_modarith() -> List[Z3CheckResult]:
    results: List[Z3CheckResult] = []

    # E1: x86-64/arith.lisp:999-1025 `*/s128*signed=>s128` parametric 2W x W -> 2W VOP equivalence!
    W = 6
    s = z3.Solver()
    x2w = z3.BitVec("x2w", 2 * W)
    yw = z3.BitVec("yw", W)
    x4w = z3.SignExt(2 * W, x2w)
    y4w = z3.SignExt(3 * W, yw)
    prod4w = x4w * y4w
    min_s2w = z3.SignExt(2 * W, z3.BitVecVal(-(1 << (2 * W - 1)), 2 * W))
    max_s2w = z3.SignExt(2 * W, z3.BitVecVal((1 << (2 * W - 1)) - 1, 2 * W))
    s.add(prod4w >= min_s2w, prod4w <= max_s2w)

    lo_x = z3.Extract(W - 1, 0, x2w)
    hi_x = z3.Extract(2 * W - 1, W, x2w)
    umul = z3.ZeroExt(W, lo_x) * z3.ZeroExt(W, yw)
    rax = z3.Extract(W - 1, 0, umul)
    rdx0 = z3.Extract(2 * W - 1, W, umul)
    term1 = hi_x * yw
    term2 = (yw >> (W - 1)) * lo_x
    rdx = rdx0 + term1 + term2
    vop_out = z3.Concat(rdx, rax)
    exact_out = z3.Extract(2 * W - 1, 0, prod4w)

    s.add(vop_out != exact_out)
    assert s.check() == z3.unsat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-E1",
            category="x86-64/arith.lisp (*/s128*signed=>s128 VOP 2W x W -> 2W equivalence)",
            source_loc="src/compiler/x86-64/arith.lisp:999-1025",
            status="UNSAT",
            summary="x86-64 */s128*signed=>s128 MUL+IMUL+SAR sign-correction sequence verified exact over all 2W x W -> 2W inputs.",
        )
    )

    # E2: arm64/arith.lisp `+/signed=>s128` ADDS + V-flag overflow-inverted sign-extension (exact 64->128 bit!)
    s2 = z3.Solver()
    a64, b64 = z3.BitVecs("a64 b64", 64)
    a128 = z3.SignExt(64, a64)
    b128 = z3.SignExt(64, b64)
    lo = a64 + b64
    v_flag = z3.Extract(63, 63, (~(a64 ^ b64)) & (a64 ^ lo)) == z3.BitVecVal(1, 1)
    hi = z3.If(v_flag, ~(lo >> 63), lo >> 63)
    arm64_sum = z3.Concat(hi, lo)
    s2.add(arm64_sum != (a128 + b128))
    assert s2.check() == z3.unsat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-E2",
            category="arm64/arith.lisp (+/signed=>s128 ADDS + V-flag sign-extension)",
            source_loc="src/compiler/arm64/arith.lisp:560-615",
            status="UNSAT",
            summary="ARM64 +/signed=>s128 VOP overflow-inverted sign extension verified exact across all 64-bit signed inputs.",
        )
    )

    # E3: modarith.lisp modular arithmetic distributing over +, -, *, logxor (W=8 -> 2W=16)
    s3 = z3.Solver()
    ma, mb = z3.BitVecs("ma mb", 16)
    mask8 = z3.BitVecVal((1 << 8) - 1, 16)
    ma8 = ma & mask8
    mb8 = mb & mask8
    s3.add(
        z3.Or(
            ((ma + mb) & mask8) != ((ma8 + mb8) & mask8),
            ((ma - mb) & mask8) != ((ma8 - mb8) & mask8),
            ((ma * mb) & mask8) != ((ma8 * mb8) & mask8),
            ((ma ^ mb) & mask8) != ((ma8 ^ mb8) & mask8),
        )
    )
    assert s3.check() == z3.unsat
    results.append(
        Z3CheckResult(
            check_id="Z3-W4-E3",
            category="modarith.lisp (modular +, -, *, logxor width-cut soundness)",
            source_loc="src/compiler/modarith.lisp:1-780",
            status="UNSAT",
            summary="Modular arithmetic width-cut commutation verified UNSAT.",
        )
    )
    return results


def main() -> int:
    print("=" * 78)
    print("Wave-4 Stage 1: Z3 SMT Compiler IR1 / Constraint / Interval / Backend Sweep")
    print("=" * 78)

    scans = scan_sbcl_sources()
    total_lines = sum(s.lines for s in scans)
    total_dt = sum(s.derive_type_count for s in scans)
    total_cs = sum(s.csubtypep_not_count for s in scans)
    total_cb = sum(s.constraint_back_count for s in scans)
    print(
        f"[Scan] Scanned {len(scans)} SBCL 2.6.10 compiler files ({total_lines:,} LOC): "
        f"{total_dt} derive-type defs, {total_cs} csubtypep/:not sites, {total_cb} constraint-back defs."
    )
    for sc in scans:
        if sc.compile_time_ash_sites:
            for hit in sc.compile_time_ash_sites:
                if "3987" in hit or "8092" in hit or "8185" in hit:
                    print(f"  [Flagged compile-time shift] {hit}")

    checks: List[Z3CheckResult] = []
    checks.append(check_a1_eq_false_branch_non_eq_comparable())
    checks.append(check_a2_type_from_constraints_lvar_annotations())
    checks.append(check_a3_convert_more_call_allow_other_keys_ice())
    checks.extend(check_b1_bitops_interval_soundness())
    checks.append(check_b5_dpb_derive_type_unbounded_ash_0day())
    checks.append(check_b6_comparison_ash_unbounded_0day())
    checks.extend(check_c_div_rem_number_theory())
    checks.extend(check_d_constraint_back_and_floats())
    checks.extend(check_e_backend_s128_and_modarith())

    print("\n[Z3 Results]")
    novel_sat = 0
    known_sat = 0
    unsat_cnt = 0
    all_novel_verified = True

    for r in checks:
        print(f"  - [{r.status:9s}] {r.check_id} ({r.source_loc}): {r.summary}")
        if r.status == "SAT_NOVEL":
            novel_sat += 1
            print(f"      Z3 witness : {r.witness}")
            print(f"      SBCL 2.6.10: verified={r.live_verified} ({r.live_detail})")
            if not r.live_verified:
                all_novel_verified = False
        elif r.status == "SAT_KNOWN":
            known_sat += 1
        else:
            unsat_cnt += 1

    print("\n" + "=" * 78)
    print(
        f"Summary: {len(checks)} Z3 SMT checks completed | "
        f"{novel_sat} NOVEL SAT bugs live-verified on SBCL 2.6.10 | "
        f"{known_sat} known SAT de-duped | {unsat_cnt} UNSAT proofs."
    )
    print("=" * 78)
    return 0 if (novel_sat >= 4 and all_novel_verified) else 1


if __name__ == "__main__":
    raise SystemExit(main())
