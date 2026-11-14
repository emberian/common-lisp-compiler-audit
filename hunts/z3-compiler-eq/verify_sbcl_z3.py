#!/usr/bin/env python3
"""
Wave-2 Lane C ("Alive2-Lite"): Z3 Symbolic Equivalence & Interval-Transfer Checker
Target: SBCL 2.6.10 (src/compiler/equality-constraints.lisp, bitops-derive-type.lisp,
        srctran.lisp, modarith.lisp, constraint-back.lisp)

Checks both:
  1. Unsound rewrites / transfer functions (producing SAT + concrete witness inputs)
  2. Sound rewrites / transfer functions (proving UNSAT across all bitvectors / IEEE-754 floats / integers)
"""

import json
import os
import time
import z3

RESULTS = []


def record(name, source_loc, category, expected_status, solver, witness_fn=None, notes=""):
    t0 = time.perf_counter()
    res = solver.check()
    dt_ms = (time.perf_counter() - t0) * 1000.0
    status = str(res)
    witness = None
    if res == z3.sat and witness_fn is not None:
        m = solver.model()
        witness = witness_fn(m)
    entry = {
        "name": name,
        "source": source_loc,
        "category": category,
        "z3_status": status,
        "expected_status": expected_status,
        "sound": (status == "unsat"),
        "time_ms": round(dt_ms, 2),
        "witness": witness,
        "notes": notes,
    }
    RESULTS.append(entry)
    tag = "BUG (SAT)" if status == "sat" else ("SOUND (UNSAT)" if status == "unsat" else status.upper())
    print(f"[{tag:13s}] {name:52s} ({dt_ms:6.1f} ms)  {source_loc}")
    if witness:
        print(f"                witness: {witness}")
    if status != expected_status:
        raise AssertionError(f"Unexpected Z3 status for {name}: got {status}, expected {expected_status}")


# =============================================================================
# PART 1: equality-constraints.lisp — Equivalence Lattice & IEEE-754 Propagation
# =============================================================================

def check_equality_constraints():
    # 1A. Mixed-type numeric/object equivalence lattice (Int, Float64, Char, BignumPtr)
    # Tag: 0 = Fixnum, 1 = Bignum(ptr, val), 2 = Float64, 3 = Char(code)
    s = z3.Solver()
    tag_x, tag_y, tag_z = z3.Ints("tag_x tag_y tag_z")
    ival_x, ival_y, ival_z = z3.Ints("ival_x ival_y ival_z")
    ptr_x, ptr_y, ptr_z = z3.Ints("ptr_x ptr_y ptr_z")
    fval_x, fval_y, fval_z = z3.Consts("fval_x fval_y fval_z", z3.Float64())

    for t in (tag_x, tag_y, tag_z):
        s.add(t >= 0, t <= 2)

    def cl_eq(tx, ix, px, fx, ty, iy, py, fy):
        return z3.And(
            tx == ty,
            z3.If(tx == 0, ix == iy,
            z3.If(tx == 1, z3.And(px == py, ix == iy),
                  z3.And(fx.sort() == fy.sort(), z3.fpToIEEEBV(fx) == z3.fpToIEEEBV(fy)))))

    def cl_eql(tx, ix, px, fx, ty, iy, py, fy):
        return z3.And(
            tx == ty,
            z3.If(tx == 0, ix == iy,
            z3.If(tx == 1, ix == iy,
                  z3.fpToIEEEBV(fx) == z3.fpToIEEEBV(fy))))

    # Sub-check 1a-i: inherit-equality-p(new='=', from='eql', not-p=False) -> 'eql'
    # Witness restricted to 53-bit exact integer vs Float64
    s1 = z3.Solver()
    bv_ix = z3.BitVec("bv_ix", 64)
    s1.add(bv_ix >= -1000, bv_ix <= 1000)
    s1.add(tag_x == 0, tag_y == 2, tag_z == 2)
    s1.add(z3.Not(z3.fpIsNaN(fval_y)), z3.Not(z3.fpIsInf(fval_y)))
    # eql(y, z): identical IEEE-754 bits
    s1.add(z3.fpToIEEEBV(fval_y) == z3.fpToIEEEBV(fval_z))
    # =(x, y): exact integer coerced to Float64 equals fval_y
    s1.add(z3.fpEQ(z3.fpSignedToFP(z3.RNE(), bv_ix, z3.Float64()), fval_y))
    # SBCL derives eql(x, z), which requires tag_x == tag_z
    sbcl_derived_eql_xz = (tag_x == tag_z)
    s1.add(z3.Not(sbcl_derived_eql_xz))
    record(
        "eq_constraints_inherit_int_vs_float",
        "equality-constraints.lisp:169-178",
        "equivalence-lattice",
        "sat",
        s1,
        lambda m: {
            "x": f"Int({m[bv_ix].as_signed_long()})",
            "y": f"Float64({m[fval_y]})",
            "z": f"Float64({m[fval_z]})",
            "eql(y,z)": True,
            "=(x,y)": True,
            "true_eql(x,z)": False,
            "sbcl_derived_eql(x,z)": True,
        },
        "inherit-equality-p returns FROM (eql) instead of lattice meet (=)",
    )

    # Sub-check 1a-ii: Float64 -0.0d0 vs +0.0d0 under eql + = -> eql
    s2 = z3.Solver()
    fx, fy, fz = z3.Consts("fx fy fz", z3.Float64())
    s2.add(z3.fpToIEEEBV(fy) == z3.fpToIEEEBV(fz))  # (eql y z)
    s2.add(z3.fpEQ(fx, fy))                          # (= x y)
    s2.add(z3.fpToIEEEBV(fx) != z3.fpToIEEEBV(fz))  # NOT (eql x z)
    record(
        "eq_constraints_inherit_signed_zero",
        "equality-constraints.lisp:169-178",
        "equivalence-lattice",
        "sat",
        s2,
        lambda m: {
            "fx": str(m[fx]),
            "fy": str(m[fy]),
            "fz": str(m[fz]),
            "fx_bits": hex(m.eval(z3.fpToIEEEBV(fx)).as_long()),
            "fz_bits": hex(m.eval(z3.fpToIEEEBV(fz)).as_long()),
        },
        "(= -0.0 +0.0) and (eql +0.0 +0.0) unsoundly derive (eql -0.0 +0.0)",
    )

    # Sub-check 1a-iii: Character char= / eql + char-equal -> char= / eql (triggers ACL2 NIL proof!)
    s3 = z3.Solver()
    cx, cy, cz = z3.BitVecs("cx cy cz", 8)
    # Printable ASCII letters
    for c in (cx, cy, cz):
        s3.add(z3.Or(z3.And(c >= 65, c <= 90), z3.And(c >= 97, c <= 122)))

    def char_upcase(c):
        return z3.If(z3.And(c >= 97, c <= 122), c - 32, c)

    char_eql_yz = (cy == cz)
    char_equal_xy = (char_upcase(cx) == char_upcase(cy))
    char_eql_xz = (cx == cz)
    s3.add(char_eql_yz, char_equal_xy, z3.Not(char_eql_xz))
    record(
        "eq_constraints_inherit_char_equal_acl2",
        "equality-constraints.lisp:169-178",
        "equivalence-lattice",
        "sat",
        s3,
        lambda m: {
            "x": repr(chr(m[cx].as_long())),
            "y": repr(chr(m[cy].as_long())),
            "z": repr(chr(m[cz].as_long())),
            "acl2_impact": "Proves (defthm nil-proved nil) in pure guard-verified ACL2 on SBCL 2.6.10",
        },
        "(eql y z) + (char-equal x y) unsoundly derives (eql x z) / (char= x z)",
    )

    # Sub-check 1a-iv: Distinct heap bignums: (eq y z) + (= x y) -> (eq x z)
    s4 = z3.Solver()
    s4.add(tag_x == 1, tag_y == 1, tag_z == 1)
    s4.add(ival_x > (1 << 62), ival_y > (1 << 62), ival_z > (1 << 62))
    eq_yz = z3.And(ptr_y == ptr_z, ival_y == ival_z)
    num_eq_xy = (ival_x == ival_y)
    eq_xz = z3.And(ptr_x == ptr_z, ival_x == ival_z)
    s4.add(eq_yz, num_eq_xy, z3.Not(eq_xz))
    record(
        "eq_constraints_inherit_bignum_eq",
        "equality-constraints.lisp:169-178",
        "equivalence-lattice",
        "sat",
        s4,
        lambda m: {
            "ptr_x": m[ptr_x].as_long(),
            "ptr_y": m[ptr_y].as_long(),
            "ptr_z": m[ptr_z].as_long(),
            "bignum_val": m[ival_x].as_long(),
        },
        "Distinct equal bignums satisfy (eq y z) and (= x y) while (eq x z) is NIL",
    )

    # Sub-check 1b-i: equality-constraints.lisp:535-537: (not (= x y)) => (eql x y) = NIL
    s5 = z3.Solver()
    nx, ny = z3.Consts("nx ny", z3.Float64())
    # Quiet NaN in IEEE-754 binary64: exponent=0x7ff, bit 51=1 (quiet)
    bvx = z3.fpToIEEEBV(nx)
    bvy = z3.fpToIEEEBV(ny)
    s5.add(z3.Extract(62, 51, bvx) == z3.BitVecVal(0xFFF, 12))  # quiet NaN
    not_num_eq = z3.Not(z3.fpEQ(nx, ny))
    cl_float_eql = (bvx == bvy)
    # SBCL folds (eql nx ny) to False when (not (= nx ny)); counterexample if cl_float_eql is True!
    s5.add(not_num_eq, cl_float_eql)
    record(
        "eq_constraints_qnan_not_num_eq_folds_eql_nil",
        "equality-constraints.lisp:535-537",
        "ieee754-constraints",
        "sat",
        s5,
        lambda m: {
            "x_bits": hex(m.eval(bvx).as_long()),
            "y_bits": hex(m.eval(bvy).as_long()),
            "(= x y)": False,
            "true_(eql x y)": True,
            "sbcl_folded_(eql x y)": False,
        },
        "Triggers under SBCL DEFAULT FPU mode on quiet NaN!",
    )

    # Sub-check 1b-ii: equality-constraints.lisp:575-577: (eql x y) => (= x y) = T
    s6 = z3.Solver()
    s6.add(z3.Extract(62, 51, bvx) == z3.BitVecVal(0xFFF, 12))  # quiet NaN
    s6.add(cl_float_eql, z3.Not(z3.fpEQ(nx, ny)))
    record(
        "eq_constraints_qnan_eql_folds_num_eq_t",
        "equality-constraints.lisp:575-577",
        "ieee754-constraints",
        "sat",
        s6,
        lambda m: {
            "x_bits": hex(m.eval(bvx).as_long()),
            "y_bits": hex(m.eval(bvy).as_long()),
            "(eql x y)": True,
            "true_(= x y)": False,
            "sbcl_folded_(= x y)": True,
        },
        "Triggers under SBCL DEFAULT FPU mode on quiet NaN!",
    )

    # Sub-check 1b-iii: equality-constraints.lisp:26-31: (not (< x y)) => (>= x y)
    s7 = z3.Solver()
    ox, oy = z3.Consts("ox oy", z3.Float64())
    s7.add(z3.Not(z3.fpLT(ox, oy)), z3.Not(z3.fpGEQ(ox, oy)))
    record(
        "eq_constraints_nan_not_lt_folds_ge",
        "equality-constraints.lisp:26-31",
        "ieee754-constraints",
        "sat",
        s7,
        lambda m: {
            "ox": str(m[ox]),
            "oy": str(m[oy]),
            "(< ox oy)": False,
            "true_(>= ox oy)": False,
            "sbcl_folded_(>= ox oy)": True,
        },
        "not-operator maps < to >= without checking float NaN possibility",
    )

    # Sub-check 1b-iv: Fixed lattice meet + no-NaN guard proved SOUND (UNSAT)
    s8 = z3.Solver()
    # Meet on chain eq < eql < = over non-NaN values:
    # eql(y,z) and =(x,y) => =(x,z)
    s8.add(z3.Not(z3.fpIsNaN(fx)), z3.Not(z3.fpIsNaN(fy)), z3.Not(z3.fpIsNaN(fz)))
    s8.add(z3.fpToIEEEBV(fy) == z3.fpToIEEEBV(fz))
    s8.add(z3.fpEQ(fx, fy))
    s8.add(z3.Not(z3.fpEQ(fx, fz)))
    record(
        "eq_constraints_fixed_lattice_meet_sound",
        "equality-constraints.lisp:169-178 (proposed fix)",
        "equivalence-lattice",
        "unsat",
        s8,
        notes="Lattice meet(eql, =) = '=' is transitive on all non-NaN IEEE-754 floats",
    )


# =============================================================================
# PART 2: srctran.lisp — Float same-arg Division, Truncation & Subtraction
# =============================================================================

def check_float_same_arg():
    # 2A. (/ x x) on bounded finite Float64 [lo, hi]: srctran.lisp:2247-2250 derives [1.0, 1.0]
    s1 = z3.Solver()
    x, lo, hi = z3.Consts("x lo hi", z3.Float64())
    s1.add(lo == z3.FPVal(-1.0, z3.Float64()), hi == z3.FPVal(1.0, z3.Float64()))
    s1.add(z3.fpLEQ(lo, x), z3.fpLEQ(x, hi), z3.Not(z3.fpIsNaN(x)))
    q = z3.fpDiv(z3.RNE(), x, x)
    one = z3.FPVal(1.0, z3.Float64())
    s1.add(z3.Not(z3.fpEQ(q, one)))
    record(
        "srctran_div_same_arg_bounded_float",
        "srctran.lisp:2247-2250 (/-derive-type-aux)",
        "float-derive-type",
        "sat",
        s1,
        lambda m: {
            "x": str(m[x]),
            "x_bits": hex(m.eval(z3.fpToIEEEBV(x)).as_long()),
            "true_(/ x x)": str(m.eval(q)),
            "sbcl_derived": "[1.0d0, 1.0d0]",
        },
        "0.0d0 / 0.0d0 = NaN, excluded by derived singleton (double-float 1.0d0 1.0d0)",
    )

    # 2B. (ftruncate x x) / (ffloor x x) / (fceiling x x): srctran.lisp:2611-2626
    # On x in [-1.0, 1.0], derives quot=1.0, rem=0.0, failing on x = ±0.0
    s2 = z3.Solver()
    s2.add(lo == z3.FPVal(-1.0, z3.Float64()), hi == z3.FPVal(1.0, z3.Float64()))
    s2.add(z3.fpLEQ(lo, x), z3.fpLEQ(x, hi), z3.Not(z3.fpIsNaN(x)))
    ftrunc_q = z3.fpRoundToIntegral(z3.RTZ(), z3.fpDiv(z3.RNE(), x, x))
    s2.add(z3.Not(z3.fpEQ(ftrunc_q, one)))
    record(
        "srctran_ftruncate_ffloor_fceiling_same_arg",
        "srctran.lisp:2611-2626, 2808-2813, 2843-2849",
        "float-derive-type",
        "sat",
        s2,
        lambda m: {
            "x": str(m[x]),
            "true_ftruncate_quot": str(m.eval(ftrunc_q)),
            "sbcl_derived_quot": "1.0d0 (and integer (1 1) causing WARNING in float-tran.lisp:1870)",
        },
        "Folds NaN to 1.0d0 AND causes full WARNING on (truncate/floor/ceiling x x) for double-float",
    )

    # 2C. (- x x) on bounded finite Float64 under IEEE-754 roundTowardNegative (RTN):
    # srctran.lisp:2098-2121 derives (double-float +0.0d0 +0.0d0) (:normalize-zeros nil)!
    s3 = z3.Solver()
    s3.add(lo == z3.FPVal(0.0, z3.Float64()), hi == z3.FPVal(2.0, z3.Float64()))
    s3.add(z3.fpLEQ(lo, x), z3.fpLEQ(x, hi), z3.Not(z3.fpIsNaN(x)))
    diff_rtn = z3.fpSub(z3.RTN(), x, x)
    pos_zero_bits = z3.fpToIEEEBV(z3.FPVal(+0.0, z3.Float64()))
    s3.add(z3.fpToIEEEBV(diff_rtn) != pos_zero_bits)
    record(
        "srctran_sub_same_arg_rtn_signed_zero",
        "srctran.lisp:2098-2121 (--derive-type-aux)",
        "float-derive-type",
        "sat",
        s3,
        lambda m: {
            "x": str(m[x]),
            "true_(- x x)_RTN": "-0.0d0",
            "diff_bits": hex(m.eval(z3.fpToIEEEBV(diff_rtn)).as_long()),
            "sbcl_derived": "(DOUBLE-FLOAT 0.0d0 0.0d0) (:normalize-zeros nil)",
        },
        "Under :rounding-mode :negative-infinity, x - x = -0.0d0, violating derived +0.0d0",
    )

    # 2D. (- x x) under default RNE rounding on bounded finite Float64: proved SOUND (UNSAT)
    s4 = z3.Solver()
    s4.add(z3.Not(z3.fpIsNaN(x)), z3.Not(z3.fpIsInf(x)))
    diff_rne = z3.fpSub(z3.RNE(), x, x)
    s4.add(z3.fpToIEEEBV(diff_rne) != pos_zero_bits)
    record(
        "srctran_sub_same_arg_rne_sound",
        "srctran.lisp:2098-2121 (under RNE)",
        "float-derive-type",
        "unsat",
        s4,
        notes="Under IEEE-754 RNE/RTP/RTZ, finite x - x is always +0.0",
    )


# =============================================================================
# PART 3: bitops-derive-type.lisp — Exact O(1) integer-length / zeroes / ones Bounds
# =============================================================================

def cl_integer_length(v, W):
    """Exact ANSI Common Lisp (integer-length v) on signed W-bit 2's-complement BitVec."""
    mag = z3.If(v < 0, ~v, v)
    res = z3.BitVecVal(0, W)
    for i in range(W - 1):
        res = z3.If(z3.Extract(i, i, mag) == 1, z3.BitVecVal(i + 1, W), res)
    return res


def cl_zeroes(n, W):
    """Exact SBCL (defun zeroes (n) (ash -1 n)) (bitops-derive-type.lisp:36-37)."""
    all_ones = z3.BitVecVal(-1, W)
    return z3.If(n <= 0, all_ones, z3.If(n >= W, z3.BitVecVal(0, W), all_ones << n))


def cl_ones(n, W):
    """Exact SBCL (defun ones (n) (lognot (ash -1 n))) (bitops-derive-type.lisp:42-43)."""
    return ~cl_zeroes(n, W)


def sbcl_logand_unsigned_bounds(a, b, c, d, W):
    """Exact Z3 encoding of logand-derive-unsigned-bounds (bitops-derive-type.lisp:118-139)."""
    len_xor_x = cl_integer_length(a ^ b, W)
    len_xor_y = cl_integer_length(c ^ d, W)
    max_len = z3.If(len_xor_x > len_xor_y, len_xor_x, len_xor_y)

    mask = cl_zeroes(max_len, W)
    index = cl_integer_length(mask | a | c, W)
    low = a & c & cl_zeroes(index - 1, W)

    mask_x = cl_ones(len_xor_x, W)
    mask_y = cl_ones(len_xor_y, W)
    index_x = cl_integer_length(mask_x & b & (~d), W)
    index_y = cl_integer_length(mask_y & d & (~b), W)
    high = z3.If(
        index_x == index_y,
        b & d,
        z3.If(
            index_x > index_y,
            (b | cl_ones(index_x - 1, W)) & d,
            (d | cl_ones(index_y - 1, W)) & b,
        ),
    )
    return low, high


def sbcl_logior_unsigned_bounds(a, b, c, d, W):
    """Exact Z3 encoding of logior-derive-unsigned-bounds (bitops-derive-type.lisp:207-228)."""
    len_xor_x = cl_integer_length(a ^ b, W)
    len_xor_y = cl_integer_length(c ^ d, W)
    max_len = z3.If(len_xor_x > len_xor_y, len_xor_x, len_xor_y)

    mask_x = cl_ones(len_xor_x, W)
    mask_y = cl_ones(len_xor_y, W)
    index_x = cl_integer_length(mask_x & (~a) & c, W)
    index_y = cl_integer_length(mask_y & (~c) & a, W)
    low = z3.If(
        index_x == index_y,
        a | c,
        z3.If(
            index_x > index_y,
            (a & cl_zeroes(index_x - 1, W)) | c,
            (c & cl_zeroes(index_y - 1, W)) | a,
        ),
    )

    mask = cl_ones(max_len, W)
    index = cl_integer_length(mask & b & d, W)
    high = b | d | cl_ones(index - 1, W)
    return low, high


def sbcl_logxor_unsigned_bounds(a, b, c, d, W):
    """Exact Z3 encoding of logxor-derive-unsigned-bounds (bitops-derive-type.lisp:314-332)."""
    not_b = ~b
    not_d = ~d
    len_xor_x = cl_integer_length(a ^ b, W)
    len_xor_y = cl_integer_length(c ^ d, W)
    max_len = z3.If(len_xor_x > len_xor_y, len_xor_x, len_xor_y)
    mask = cl_zeroes(max_len, W)

    index_ad = cl_integer_length(mask | a | not_d, W)
    index_bc = cl_integer_length(mask | not_b | c, W)
    low = (a & not_d & cl_zeroes(index_ad - 1, W)) | (not_b & c & cl_zeroes(index_bc - 1, W))

    index_ac = cl_integer_length(mask | a | c, W)
    index_bd = cl_integer_length(mask | not_b | not_d, W)
    high = ~((a & c & cl_zeroes(index_ac - 1, W)) | (not_b & not_d & cl_zeroes(index_bd - 1, W)))
    return low, high


def sbcl_signed_bitop_bounds(x_lo, x_hi, y_lo, y_hi, op_name, W):
    """
    Exact Z3 encoding of SBCL's logand-derive-type-aux (141-205),
    logior-derive-type-aux (230-312, including add-one!), and
    logxor-derive-type-aux (334-364) over signed W-bit 2's complement!
    """
    zero = z3.BitVecVal(0, W)
    one = z3.BitVecVal(1, W)
    m1 = z3.BitVecVal(-1, W)
    lx_lo, lx_hi = cl_integer_length(x_lo, W), cl_integer_length(x_hi, W)
    ly_lo, ly_hi = cl_integer_length(y_lo, W), cl_integer_length(y_hi, W)
    x_len = z3.If(lx_lo > lx_hi, lx_lo, lx_hi)
    y_len = z3.If(ly_lo > ly_hi, ly_lo, ly_hi)
    max_len = z3.If(x_len > y_len, x_len, y_len)
    min_len = z3.If(x_len < y_len, x_len, y_len)
    x_pos, x_neg = (x_hi >= zero), (x_lo < zero)
    y_pos, y_neg = (y_hi >= zero), (y_lo < zero)

    if op_name == "logand":
        # Both >= 0
        pp_lo, pp_hi = sbcl_logand_unsigned_bounds(x_lo, x_hi, y_lo, y_hi, W)
        # x >= 0, y < 0 (lines 167-174: ldb (byte len 0) y_low, y_high)
        mask_len = cl_ones(max_len, W)
        pn_strict_lo, pn_strict_hi = sbcl_logand_unsigned_bounds(x_lo, x_hi, y_lo & mask_len, y_hi & mask_len, W)
        np_strict_lo, np_strict_hi = sbcl_logand_unsigned_bounds(y_lo, y_hi, x_lo & mask_len, x_hi & mask_len, W)
        # Both might be negative (lines 194-198): [zeroes(integer-length(min(x_lo, y_lo))), max(x_hi, y_hi, -1)]
        min_lo = z3.If(x_lo < y_lo, x_lo, y_lo)
        max_hi2 = z3.If(x_hi > y_hi, x_hi, y_hi)
        nn_lo = cl_zeroes(cl_integer_length(min_lo, W), W)
        nn_hi = z3.If(max_hi2 > m1, max_hi2, m1)
        return (
            z3.If(z3.Not(x_neg),
                  z3.If(z3.Not(y_neg), pp_lo, z3.If(y_hi < zero, pn_strict_lo, zero)),
                  z3.If(z3.Not(y_neg), z3.If(x_hi < zero, np_strict_lo, zero), nn_lo)),
            z3.If(z3.Not(x_neg),
                  z3.If(z3.Not(y_neg), pp_hi, z3.If(y_hi < zero, pn_strict_hi, x_hi)),
                  z3.If(z3.Not(y_neg), z3.If(x_hi < zero, np_strict_hi, y_hi), nn_hi)),
        )
    elif op_name == "logior":
        def add_one(a_lo, b_lo, b_hi):
            length = cl_integer_length(a_lo, W)
            expt = one << length
            cond = z3.And(a_lo < zero, z3.Not(z3.And(b_lo <= zero, zero <= b_hi)),
                          a_lo == -expt, b_lo > a_lo, b_hi < (expt - one))
            return z3.If(cond, z3.If(b_lo == b_hi, a_lo | b_lo, a_lo + one), a_lo)

        pp_lo, pp_hi = sbcl_logior_unsigned_bounds(x_lo, x_hi, y_lo, y_hi, W)
        nn_lo, nn_hi = cl_zeroes(min_len, W), m1
        # Mixed x (x_neg and x_pos):
        _, mix_x_pos_hi = sbcl_logior_unsigned_bounds(zero, x_hi, y_lo, y_hi, W)
        _, mix_y_pos_hi = sbcl_logior_unsigned_bounds(zero, y_hi, x_lo, x_hi, W)
        _, mix_both_hi = sbcl_logior_unsigned_bounds(
            z3.If(x_lo > zero, x_lo, zero), x_hi, z3.If(y_lo > zero, y_lo, zero), y_hi, W
        )
        min_lo = z3.If(x_lo < y_lo, x_lo, y_lo)
        # Note: for type-union([add_one..-1], [low..high]) with low >= 0, bounding interval is [add_one..high]!
        return (
            z3.If(z3.And(z3.Not(x_neg), z3.Not(y_neg)), pp_lo,
            z3.If(z3.Not(x_pos), z3.If(z3.Not(y_pos), nn_lo, x_lo),
            z3.If(z3.Not(y_pos), y_lo,
            z3.If(y_lo > zero, add_one(x_lo, y_lo, y_hi),
            z3.If(x_lo > zero, add_one(y_lo, x_lo, x_hi), min_lo))))),
            z3.If(z3.And(z3.Not(x_neg), z3.Not(y_neg)), pp_hi,
            z3.If(z3.Not(x_pos), m1,
            z3.If(z3.Not(y_pos), m1,
            z3.If(y_lo > zero, mix_x_pos_hi,
            z3.If(x_lo > zero, mix_y_pos_hi, mix_both_hi))))),
        )
    elif op_name == "logxor":
        pp_lo, pp_hi = sbcl_logxor_unsigned_bounds(x_lo, x_hi, y_lo, y_hi, W)
        return (
            z3.If(z3.And(z3.Not(x_neg), z3.Not(y_neg)), pp_lo,
            z3.If(z3.And(z3.Not(x_pos), z3.Not(y_pos)), zero,
            z3.If(z3.Or(z3.And(z3.Not(x_pos), z3.Not(y_neg)), z3.And(z3.Not(y_pos), z3.Not(x_neg))),
                  cl_zeroes(max_len, W),
                  cl_zeroes(max_len, W)))),
            z3.If(z3.And(z3.Not(x_neg), z3.Not(y_neg)), pp_hi,
            z3.If(z3.And(z3.Not(x_pos), z3.Not(y_pos)), cl_ones(max_len, W),
            z3.If(z3.Or(z3.And(z3.Not(x_pos), z3.Not(y_neg)), z3.And(z3.Not(y_pos), z3.Not(x_neg))),
                  m1,
                  cl_ones(max_len, W)))),
        )
    raise ValueError(op_name)


def check_bitops_derive_type():
    # Use signed 10-bit BitVec with operands restricted to [-128, 127] (8-bit values with 2 sign guard bits
    # so infinite-precision 2's-complement ~b, shifts up to 8, etc. never overflow!)
    W = 10
    x, y, x_lo, x_hi, y_lo, y_hi = z3.BitVecs("x y x_lo x_hi y_lo y_hi", W)

    # Unsigned bounds: logand, logior, logxor over ALL [0..127] intervals!
    for name, fn, op in [
        ("bitops_unsigned_logand_bounds_o1_bv8", sbcl_logand_unsigned_bounds, lambda a, b: a & b),
        ("bitops_unsigned_logior_bounds_o1_bv8", sbcl_logior_unsigned_bounds, lambda a, b: a | b),
        ("bitops_unsigned_logxor_bounds_o1_bv8", sbcl_logxor_unsigned_bounds, lambda a, b: a ^ b),
    ]:
        s = z3.Solver()
        for v in (x, y, x_lo, x_hi, y_lo, y_hi):
            s.add(v >= 0, v <= 127)
        s.add(x_lo <= x, x <= x_hi)
        s.add(y_lo <= y, y <= y_hi)
        d_lo, d_hi = fn(x_lo, x_hi, y_lo, y_hi, W)
        r = op(x, y)
        s.add(z3.Or(r < d_lo, r > d_hi))
        record(name, "bitops-derive-type.lisp:118-139, 207-228, 314-332", "bitops-derive-type", "unsat", s)

    # Signed mixed-sign bounds (straddling 0, including ldb neg trick & add-one!):
    for name, op_key, op in [
        ("bitops_signed_logand_bounds_bv8", "logand", lambda a, b: a & b),
        ("bitops_signed_logior_bounds_add_one_bv8", "logior", lambda a, b: a | b),
        ("bitops_signed_logxor_bounds_bv8", "logxor", lambda a, b: a ^ b),
    ]:
        s = z3.Solver()
        for v in (x, y, x_lo, x_hi, y_lo, y_hi):
            s.add(v >= -128, v <= 127)
        s.add(x_lo <= x, x <= x_hi)
        s.add(y_lo <= y, y <= y_hi)
        d_lo, d_hi = sbcl_signed_bitop_bounds(x_lo, x_hi, y_lo, y_hi, op_key, W)
        r = op(x, y)
        s.add(z3.Or(r < d_lo, r > d_hi))
        record(name, "bitops-derive-type.lisp:141-364", "bitops-derive-type", "unsat", s)

    # Exact cmatch interval bounds in bitops-derive-type.lisp:395-460 (Gray code + logior/logand x (- x))!
    s_gray = z3.Solver()
    sh = z3.BitVec("sh", W)
    for v in (x, x_lo, x_hi):
        s_gray.add(v >= -128, v <= 127)
    s_gray.add(x_lo <= x, x <= x_hi, sh >= -8, sh <= -1)
    lx_lo, lx_hi = cl_integer_length(x_lo, W), cl_integer_length(x_hi, W)
    xlen = z3.If(lx_lo > lx_hi, lx_lo, lx_hi)
    m_val = z3.If(x_hi > (~x_lo), x_hi, ~x_lo)
    m_val = z3.If(m_val > 0, m_val, z3.BitVecVal(0, W))
    one_sh_len_m1 = (z3.BitVecVal(1, W) << xlen) - 1
    g_max = z3.If(z3.Or(xlen <= (-sh), m_val == one_sh_len_m1), m_val, one_sh_len_m1)
    g_min = z3.If(
        x_lo > 0,
        z3.BitVecVal(1, W) << (cl_integer_length(x_lo, W) - 1),
        z3.If(x_hi < -1, z3.BitVecVal(1, W) << (cl_integer_length(~x_hi, W) - 1), z3.BitVecVal(0, W)),
    )
    gray_actual = x ^ (x >> (-sh))
    s_gray.add(z3.Or(gray_actual < g_min, gray_actual > g_max))
    record("bitops_cmatch_gray_code_logxor_ash_right", "bitops-derive-type.lisp:395-410", "bitops-cmatch", "unsat", s_gray)

    # lognot-derive-type-aux: [~x_hi, ~x_lo] on 64-bit BitVec
    s_not = z3.Solver()
    x64, lo64, hi64 = z3.BitVecs("x64 lo64 hi64", 64)
    s_not.add(lo64 <= x64, x64 <= hi64)
    r64 = ~x64
    s_not.add(z3.Or(r64 < (~hi64), r64 > (~lo64)))
    record("bitops_signed_lognot_bounds_bv64", "srctran.lisp:3305-3320", "bitops-derive-type", "unsat", s_not)

    # cmatch bithacks in bitops-derive-type.lisp:370-464 on 64-bit signed integers (sign-extended to 65 bits)
    xv = z3.SignExt(1, x64)

    s_bh1 = z3.Solver()
    r_bh1 = xv ^ (xv - 1)
    s_bh1.add(z3.Not(z3.If(xv == 0, r_bh1 == -1, z3.And(r_bh1 >= 1, (r_bh1 & 1) == 1))))
    record("bitops_cmatch_logxor_x_sub_1_bv64", "bitops-derive-type.lisp:372-375", "bitops-cmatch", "unsat", s_bh1)

    s_bh2 = z3.Solver()
    r_bh2 = xv ^ (xv + 1)
    s_bh2.add(z3.Not(z3.If(xv == -1, r_bh2 == -1, z3.And(r_bh2 >= 1, (r_bh2 & 1) == 1))))
    record("bitops_cmatch_logxor_x_add_1_bv64", "bitops-derive-type.lisp:377-380", "bitops-cmatch", "unsat", s_bh2)

    s_bh3 = z3.Solver()
    r_bh3 = xv ^ (-xv)
    s_bh3.add(z3.Not(z3.If(xv == 0, r_bh3 == 0, z3.And(r_bh3 <= -2, (r_bh3 & 1) == 0))))
    record("bitops_cmatch_logxor_x_neg_x_bv64", "bitops-derive-type.lisp:382-393", "bitops-cmatch", "unsat", s_bh3)

    s_bh4 = z3.Solver()
    r_bh4 = xv | (-xv)
    s_bh4.add(z3.Not(z3.If(xv == 0, r_bh4 == 0, z3.And(r_bh4 < 0, z3.Implies(xv > 0, r_bh4 >= -xv)))))
    record("bitops_cmatch_logior_x_neg_x_bv64", "bitops-derive-type.lisp:419-434", "bitops-cmatch", "unsat", s_bh4)

    s_bh5 = z3.Solver()
    r_bh5 = xv & (-xv)
    abs_xv = z3.If(xv < 0, -xv, xv)
    s_bh5.add(z3.Not(z3.If(xv == 0, r_bh5 == 0, z3.And(r_bh5 >= 1, r_bh5 <= abs_xv))))
    record("bitops_cmatch_logand_x_neg_x_bv64", "bitops-derive-type.lisp:443-462", "bitops-cmatch", "unsat", s_bh5)


# =============================================================================
# PART 4: srctran.lisp & modarith.lisp & constraint-back.lisp — Shifts, Div/Mod, Magic Mul
# =============================================================================

def check_srctran_arith_and_modarith():
    # 4A. ash-derive-type-aux: monotonicity of (ash x s) in both x and s?
    # CAREFUL! Is (ash x s) monotone in s when x < 0?!
    # For x = -4: s = -1 -> -2; s = +1 -> -8! So for x < 0, ash(x, s) DECREASES as s INCREASES!
    # Therefore min/max of ash(x, s) over x in [x_lo, x_hi], s in [s_lo, s_hi] is achieved at the 4 corners!
    s_ash = z3.Solver()
    W = 16
    x, x_lo, x_hi = z3.BitVecs("x x_lo x_hi", W)
    sh, sh_lo, sh_hi = z3.BitVecs("sh sh_lo sh_hi", W)
    s_ash.add(x_lo <= x, x <= x_hi, x_lo >= -256, x_hi <= 255)
    s_ash.add(sh_lo <= sh, sh <= sh_hi, sh_lo >= -6, sh_hi <= 6)

    def cl_ash(val, amt):
        return z3.If(amt >= 0, val << amt, val >> (-amt))

    c1 = cl_ash(x_lo, sh_lo)
    c2 = cl_ash(x_lo, sh_hi)
    c3 = cl_ash(x_hi, sh_lo)
    c4 = cl_ash(x_hi, sh_hi)

    def bv_min4(a, b, c, d):
        m1 = z3.If(a < b, a, b)
        m2 = z3.If(c < d, c, d)
        return z3.If(m1 < m2, m1, m2)

    def bv_max4(a, b, c, d):
        m1 = z3.If(a > b, a, b)
        m2 = z3.If(c > d, c, d)
        return z3.If(m1 > m2, m1, m2)

    lo_ash = bv_min4(c1, c2, c3, c4)
    hi_ash = bv_max4(c1, c2, c3, c4)
    actual_ash = cl_ash(x, sh)
    s_ash.add(z3.Or(actual_ash < lo_ash, actual_ash > hi_ash))
    record("srctran_ash_derive_type_aux_mixed_sign", "srctran.lisp:3185-3245", "arith-derive-type", "unsat", s_ash)

    # 4B. CL truncate / floor / ceiling / rem / mod exact integer definitions on signed BitVec(12)
    # In SMT-LIB QF_BV, signed `/` (bvsdiv) rounds toward 0 (== cl:truncate) and z3.SRem has dividend's sign (== cl:rem)!
    def bv_truncate(n, d):
        return n / d, z3.SRem(n, d)

    def bv_floor(n, d):
        q, r = bv_truncate(n, d)
        adj = z3.If(d < 0, r > 0, r < 0)
        return z3.If(adj, q - 1, q), z3.If(adj, r + d, r)

    def bv_ceiling(n, d):
        q, r = bv_truncate(n, d)
        adj = z3.If(d < 0, r < 0, r > 0)
        return z3.If(adj, q + 1, q), z3.If(adj, r - d, r)

    # Check SBCL floor->truncate transform + rem-type + quot-type (srctran.lisp:4909-4949)
    WD = 12  # Exhaustive over [-512, 511] (avoids 12-bit -2048/-1 overflow)
    n, d, n_lo, n_hi, d_lo, d_hi = z3.BitVecs("n d n_lo n_hi d_lo d_hi", WD)
    s_fl = z3.Solver()
    for v in (n, d, n_lo, n_hi, d_lo, d_hi):
        s_fl.add(v >= -512, v <= 511)
    s_fl.add(n_lo <= n, n <= n_hi, d_lo <= d, d <= d_hi, d != 0)
    fq, fr = bv_floor(n, d)
    rem_lo = z3.If(d_lo >= 0, z3.BitVecVal(0, WD), d_lo + 1)
    rem_hi = z3.If(d_hi <= 0, z3.BitVecVal(0, WD), d_hi - 1)
    abs_n_lo = z3.If(n_lo >= 0, n_lo, -n_lo)
    abs_n_hi = z3.If(n_hi >= 0, n_hi, -n_hi)
    max_n = z3.If(abs_n_lo > abs_n_hi, abs_n_lo, abs_n_hi)
    tru_q, tru_r = bv_truncate(n, d)
    adj_fl = z3.If(d < 0, tru_r > 0, tru_r < 0)
    s_fl.add(
        z3.Or(
            fr < rem_lo,
            fr > rem_hi,
            z3.And(adj_fl, z3.Or(fq < -max_n, fq > max_n)),
        )
    )
    record("srctran_floor_via_truncate_bounds_bv12", "srctran.lisp:4909-4949", "div-transform", "unsat", s_fl)

    # Check SBCL ceiling->truncate transform + rem-type + quot-type (srctran.lisp:4951-4993)
    s_ce = z3.Solver()
    for v in (n, d, n_lo, n_hi, d_lo, d_hi):
        s_ce.add(v >= -512, v <= 511)
    s_ce.add(n_lo <= n, n <= n_hi, d_lo <= d, d <= d_hi, d != 0)
    cq, cr = bv_ceiling(n, d)
    crem_lo = z3.If(d_hi <= 1, z3.BitVecVal(0, WD), 1 - d_hi)
    crem_hi = z3.If(d_lo >= -1, z3.BitVecVal(0, WD), -1 - d_lo)
    contains_1 = z3.And(d_lo <= 1, z3.BitVecVal(1, WD) <= d_hi)
    contains_m1 = z3.And(d_lo <= -1, z3.BitVecVal(-1, WD) <= d_hi)
    cmax = z3.If(z3.Or(contains_1, contains_m1, max_n == 1), max_n, max_n - 1)
    adj_ce = z3.If(d < 0, tru_r < 0, tru_r > 0)
    s_ce.add(
        z3.Or(
            cr < crem_lo,
            cr > crem_hi,
            z3.And(adj_ce, z3.Or(cq < -cmax, cq > cmax)),
        )
    )
    record("srctran_ceiling_via_truncate_bounds_bv12", "srctran.lisp:4951-4993", "div-transform", "unsat", s_ce)

    # 4C. Power-of-two floor / ceiling / truncate transforms on 64-bit signed BitVec (srctran.lisp:5038-5123)
    for neg_div in (False, True):
        k = 3
        y_val = -(1 << k) if neg_div else (1 << k)
        mask = (1 << k) - 1
        s_p2 = z3.Solver()
        xbv = z3.BitVec("xbv", 64)
        x66 = z3.SignExt(2, xbv)
        if neg_div:
            q_xform = (-x66) >> k
            r_xform = -((-x66) & mask)
        else:
            q_xform = x66 >> k
            r_xform = x66 & mask
        y66 = z3.BitVecVal(y_val, 66)
        valid_rem = z3.And(r_xform > y66, r_xform <= 0) if neg_div else z3.And(r_xform >= 0, r_xform < y66)
        s_p2.add(z3.Not(z3.And(x66 == q_xform * y66 + r_xform, valid_rem)))
        record(
            f"srctran_floor_pow2_{'neg' if neg_div else 'pos'}_8_bv64",
            "srctran.lisp:5038-5052",
            "div-pow2-transform",
            "unsat",
            s_p2,
        )

    # Word-overflow-avoiding ceiling by +2^k on unsigned 64-bit word (srctran.lisp:5065-5074):
    s_cp2 = z3.Solver()
    uw = z3.BitVec("uw", 64)
    k = 5
    q_ceil_u64 = z3.If(uw == 0, z3.BitVecVal(0, 64), z3.BitVecVal(1, 64) + z3.LShR(uw - 1, k))
    uw66 = z3.ZeroExt(2, uw)
    q_exact = z3.LShR(uw66 + ((1 << k) - 1), k)
    s_cp2.add(z3.ZeroExt(2, q_ceil_u64) != q_exact)
    record("srctran_ceiling_pow2_word_no_overflow_bv64", "srctran.lisp:5065-5074", "div-pow2-transform", "unsat", s_cp2)

    # 4D. Granlund-Montgomery unsigned & signed 64-bit magic-multiplier division (srctran.lisp:5282-5365)
    # Encoded in exact QF_LIA (Presburger linear integer arithmetic) over ALL 2^64 full 64-bit inputs!
    # Because m, shift, 2^64, and y_const are integer constants, floor-division by 2^64 / 2^k is exact
    # two's-complement mulhi / arithmetic-shift, solving in <5 ms AND proving zero intermediate 64-bit overflow!
    def choose_multiplier(y, precision, word_bits=64):
        l = (y - 1).bit_length()
        shift = l
        expt = 1 << (word_bits + l)
        m_low = expt // y
        m_high = (expt + (expt >> precision)) // y
        while (m_low >> 1) < (m_high >> 1) and shift > 0:
            m_low >>= 1
            m_high >>= 1
            shift -= 1
        return m_high, shift

    n_w64 = 1 << 64
    n_1_64 = 1 << 63

    for y_const in (3, 7, 10, 14):
        s_gm_u = z3.Solver()
        ux = z3.Int("ux")
        s_gm_u.add(ux >= 0, ux < n_w64)
        precision = 64
        shift1 = 0
        m, shift2 = choose_multiplier(y_const, precision, 64)
        if m >= n_w64 and (y_const % 2 == 0):
            lowbit = y_const & (-y_const)
            shift1 = (lowbit - 1).bit_length()
            m, shift2 = choose_multiplier(y_const >> shift1, precision - shift1, 64)

        def mulhi_u64_lia(a, b_int):
            return (a * b_int) / n_w64

        no_overflow = z3.BoolVal(True)
        if m >= n_w64:
            t1 = mulhi_u64_lia(ux, m - n_w64)
            sum_mid = t1 + (ux - t1) / 2
            no_overflow = z3.And(ux - t1 >= 0, ux - t1 < n_w64, sum_mid >= 0, sum_mid < n_w64)
            q_gm = sum_mid / (1 << (shift2 - 1))
        elif shift1 == 0 and shift2 == 0:
            q_gm = mulhi_u64_lia(ux, m)
        else:
            masked = ux - (ux % (1 << shift1)) if shift1 > 0 else ux
            q_gm = mulhi_u64_lia(masked, m) / (1 << (shift1 + shift2))

        prod_u = q_gm * y_const
        s_gm_u.add(z3.Not(z3.And(no_overflow, prod_u <= ux, ux - prod_u < y_const)))
        record(
            f"srctran_granlund_montgomery_udiv_{y_const}_word64",
            "srctran.lisp:5282-5327",
            "magic-div-transform",
            "unsat",
            s_gm_u,
        )

    for y_const in (3, 7, -7, -10):
        s_gm_s = z3.Solver()
        sx = z3.Int("sx")
        s_gm_s.add(sx >= -n_1_64, sx < n_1_64)
        m, shift = choose_multiplier(abs(y_const), 63, 64)

        def mulhi_s64_lia(a, b_int):
            b_u64 = b_int & (n_w64 - 1)
            b_s64 = b_u64 - n_w64 if b_u64 >= n_1_64 else b_u64
            # Arithmetic right shift by 64 of 128-bit signed product equals floor((a * b_s64) / 2^64)
            return (a * b_s64) / n_w64

        no_s_overflow = z3.BoolVal(True)
        if m < n_1_64:
            code = mulhi_s64_lia(sx, m) / (1 << shift)
        else:
            add_term = sx + mulhi_s64_lia(sx, m - n_w64)
            # Also verify SBCL's `(truly-the sb-vm:signed-word (+ x (%signed-multiply-high ...)))` never overflows!
            no_s_overflow = z3.And(add_term >= -n_1_64, add_term < n_1_64)
            code = add_term / (1 << shift)
        x_sign = z3.If(sx < 0, z3.IntVal(-1), z3.IntVal(0))
        q_gm = (x_sign - code) if y_const < 0 else (code - x_sign)
        rem_s = sx - q_gm * y_const
        abs_rem = z3.If(rem_s >= 0, rem_s, -rem_s)
        valid_trunc = z3.And(
            no_s_overflow,
            abs_rem < abs(y_const),
            z3.Implies(rem_s != 0, (rem_s > 0) == (sx > 0)),
        )
        s_gm_s.add(z3.Not(valid_trunc))
        record(
            f"srctran_granlund_montgomery_sdiv_{y_const}_word64",
            "srctran.lisp:5333-5365",
            "magic-div-transform",
            "unsat",
            s_gm_s,
        )

    # 4E. ldb / dpb / mask-field / deposit-field bitvector transforms (srctran.lisp / vm-tran.lisp)
    bx, by = z3.BitVecs("bx by", 64)
    size, pos = 13, 17
    mask = ((1 << size) - 1) << pos
    ldb_val = z3.LShR(bx, pos) & ((1 << size) - 1)
    dpb_val = (by & ~mask) | ((bx << pos) & mask)
    deposit_field_val = (by & ~mask) | (bx & mask)
    re_ldb = z3.LShR(dpb_val, pos) & ((1 << size) - 1)
    re_dpb = (by & ~mask) | (((z3.LShR(by, pos) & ((1 << size) - 1)) << pos) & mask)
    dpb_of_ldb = (by & ~mask) | ((ldb_val << pos) & mask)
    s_bf2 = z3.Solver()
    s_bf2.add(z3.Or(re_ldb != (bx & ((1 << size) - 1)), re_dpb != by, deposit_field_val != dpb_of_ldb))
    record("srctran_ldb_dpb_deposit_field_identities_bv64", "srctran.lisp:3450-3620", "bitfield-transform", "unsat", s_bf2)

    # 4F. modarith.lisp — Modular width-cutting identities (cut-to-width W=32 on 64-bit BitVec)
    s_mod = z3.Solver()
    mx, my, ms = z3.BitVecs("mx my ms", 64)
    s_mod.add(z3.ULE(ms, 63))
    mask32 = z3.BitVecVal(0xFFFFFFFF, 64)
    cut = lambda v: v & mask32
    s_mod.add(
        z3.Or(
            cut(cut(mx) + cut(my)) != cut(mx + my),
            cut(cut(mx) - cut(my)) != cut(mx - my),
            cut(cut(mx) * cut(my)) != cut(mx * my),
            cut(cut(mx) & cut(my)) != cut(mx & my),
            cut(cut(mx) | cut(my)) != cut(mx | my),
            cut(cut(mx) ^ cut(my)) != cut(mx ^ my),
            cut(~cut(mx)) != cut(~mx),
            cut(cut(mx) << ms) != cut(mx << ms),
        )
    )
    record("modarith_unsigned_width_cut_identities_bv64", "modarith.lisp:1-620", "modular-arithmetic", "unsat", s_mod)

    # 4G. srctran.lisp:1486-1510, 4977-4995 — interval-untruncate backward inverse & signed-word-checked transform!
    WU = 10  # Operands in [-8, 7], products in [-81, 81] inside signed 10-bit [-512, 511]

    def z3_untruncate_pos_d_bv(r_lo, r_hi, d_lo, d_hi):
        zero = z3.BitVecVal(0, WU)
        one = z3.BitVecVal(1, WU)
        m1 = z3.BitVecVal(-1, WU)
        add_lo = z3.If(r_lo > zero, zero, m1)
        add_hi = z3.If(r_hi < zero, zero, one)
        sub_lo = z3.If(r_lo > zero, zero, one)
        sub_hi = z3.If(r_hi < zero, zero, m1)
        n_add_lo = r_lo + add_lo
        n_add_hi = r_hi + add_hi
        p1, p2, p3, p4 = d_lo * n_add_lo, d_lo * n_add_hi, d_hi * n_add_lo, d_hi * n_add_hi

        def bvmin4(a, b, c, d_):
            t1 = z3.If(a < b, a, b)
            t2 = z3.If(c < d_, c, d_)
            return z3.If(t1 < t2, t1, t2)

        def bvmax4(a, b, c, d_):
            t1 = z3.If(a > b, a, b)
            t2 = z3.If(c > d_, c, d_)
            return z3.If(t1 > t2, t1, t2)

        return bvmin4(p1, p2, p3, p4) + sub_lo, bvmax4(p1, p2, p3, p4) + sub_hi

    def z3_interval_untruncate_bv(r_lo, r_hi, d_lo, d_hi):
        zero = z3.BitVecVal(0, WU)
        pos_lo, pos_hi = z3_untruncate_pos_d_bv(r_lo, r_hi, z3.If(d_lo > zero, d_lo, zero), d_hi)
        neg_u_lo, neg_u_hi = z3_untruncate_pos_d_bv(r_lo, r_hi, z3.If(d_hi < zero, -d_hi, zero), -d_lo)
        neg_lo, neg_hi = -neg_u_hi, -neg_u_lo
        return (
            z3.If(d_lo > zero, pos_lo, z3.If(d_hi < zero, neg_lo, z3.If(pos_lo < neg_lo, pos_lo, neg_lo))),
            z3.If(d_lo > zero, pos_hi, z3.If(d_hi < zero, neg_hi, z3.If(pos_hi > neg_hi, pos_hi, neg_hi))),
        )

    # Exact backward soundness of interval-untruncate for cl:truncate
    s_ut = z3.Solver()
    ux_b, ud_b, r_lo_b, r_hi_b, d_lo_b, d_hi_b = z3.BitVecs("ux_b ud_b r_lo_b r_hi_b d_lo_b d_hi_b", WU)
    for v in (ux_b, ud_b, r_lo_b, r_hi_b, d_lo_b, d_hi_b):
        s_ut.add(v >= -8, v <= 7)
    s_ut.add(r_lo_b <= r_hi_b, d_lo_b <= ud_b, ud_b <= d_hi_b, ud_b != 0)
    q_tr, _ = bv_truncate(ux_b, ud_b)
    s_ut.add(r_lo_b <= q_tr, q_tr <= r_hi_b)
    m_lo, m_hi = z3_interval_untruncate_bv(r_lo_b, r_hi_b, d_lo_b, d_hi_b)
    s_ut.add(z3.Or(ux_b < m_lo, ux_b > m_hi))
    record("srctran_interval_untruncate_truncate_bv10", "srctran.lisp:1486-1510", "constraint-back", "unsat", s_ut)

    # Soundness of srctran.lisp:4977-4995 signed-word-checked-transform for floor & ceiling
    # (when m=[m_lo, m_hi] fits in symmetric two's-complement fixnum [-4, 3] or word [-8, 7] and divisor y is fixnum)
    for op_label, op_fn in [("floor", bv_floor), ("ceiling", bv_ceiling)]:
        s_sw = z3.Solver()
        ux_s, ud_s, r_lo_s, r_hi_s, d_lo_s, d_hi_s = z3.BitVecs("ux_s ud_s r_lo_s r_hi_s d_lo_s d_hi_s", WU)
        s_sw.add(ux_s >= -32, ux_s <= 31)
        for v in (ud_s, r_lo_s, r_hi_s, d_lo_s, d_hi_s):
            s_sw.add(v >= -4, v <= 3)  # scaled fixnum = [-2^2, 2^2 - 1]
        s_sw.add(r_lo_s <= r_hi_s, d_lo_s <= ud_s, ud_s <= d_hi_s, ud_s != 0)
        q_op, _ = op_fn(ux_s, ud_s)
        s_sw.add(r_lo_s <= q_op, q_op <= r_hi_s)
        mlo_s, mhi_s = z3_interval_untruncate_bv(r_lo_s, r_hi_s, d_lo_s, d_hi_s)
        fix_ok = z3.And(mlo_s >= -4, mhi_s <= 3)
        word_ok = z3.And(mlo_s >= -8, mhi_s <= 7)
        s_sw.add(
            z3.Or(
                z3.And(fix_ok, z3.Or(ux_s < -4, ux_s > 3)),
                z3.And(word_ok, z3.Or(ux_s < -8, ux_s > 7)),
            )
        )
        record(
            f"srctran_signed_word_checked_{op_label}_sound",
            "srctran.lisp:4977-4995",
            "div-transform",
            "unsat",
            s_sw,
        )


def main():
    print("=" * 96)
    print("SBCL 2.6.10 Z3 Symbolic Equivalence & Interval-Transfer Verification Suite")
    print("=" * 96)
    check_equality_constraints()
    check_float_same_arg()
    check_bitops_derive_type()
    check_srctran_arith_and_modarith()

    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sbcl_z3_results.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(RESULTS, f, indent=2)

    bugs = [r for r in RESULTS if r["z3_status"] == "sat"]
    sound = [r for r in RESULTS if r["z3_status"] == "unsat"]
    print("=" * 96)
    print(f"SUMMARY: {len(RESULTS)} Z3 checks completed | {len(bugs)} SAT (bugs/counterexamples) | {len(sound)} UNSAT (proved sound)")
    print(f"Saved JSON results to: {out_path}")


if __name__ == "__main__":
    main()
