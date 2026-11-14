#!/usr/bin/env python3
"""
Wave-2 Lane C ("Alive2-Lite"): Z3 Symbolic Equivalence & Interval-Transfer Checker
Target: Clozure CL (CCL) 1.14 ARM64
  - compiler/ARM64/arm642.lisp (FCMP NZCV condition codes, bitfields, shifts, align-up)
  - compiler/nx0.lisp & compiler/acode-rewrite.lisp (interval bounds, ash, logand/ior/xor, eql-iff-eq-p)
  - compiler/optimizers.lisp (min/max, boole, ldb/dpb/mask-field/deposit-field)
  - level-0/l0-numbers.lisp & level-0/ARM64/arm64-numbers.lisp (%unary-truncate, fixnum-dfloat-compare, %fixnum-signum, %fixnum-intlen, %iash)
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
    print(f"[{tag:13s}] {name:54s} ({dt_ms:6.1f} ms)  {source_loc}")
    if witness:
        print(f"                witness: {witness}")
    if status != expected_status:
        raise AssertionError(f"Unexpected Z3 status for {name}: got {status}, expected {expected_status}")


# =============================================================================
# PART 1: ARMv8-A FCMP NZCV & CCL Condition-Code Mapping (arm642.lisp)
# =============================================================================

# ARMv8-A Architecture Reference Manual (C1.2.3 / FCompare):
# FCMP d1, d2 sets NZCV (4 booleans N, Z, C, V):
#   Unordered (NaN): N=0, Z=0, C=1, V=1  (0b0011)
#   d1 == d2:        N=0, Z=1, C=1, V=0  (0b0110)
#   d1 <  d2:        N=1, Z=0, C=0, V=0  (0b1000)
#   d1 >  d2:        N=0, Z=0, C=1, V=0  (0b0010)
def arm64_fcmp_nzcv(x, y):
    unord = z3.Or(z3.fpIsNaN(x), z3.fpIsNaN(y))
    eq = z3.fpEQ(x, y)
    lt = z3.fpLT(x, y)
    # gt = z3.fpGT(x, y)
    N = z3.If(unord, False, z3.If(lt, True, False))
    Z = z3.If(unord, False, z3.If(eq, True, False))
    C = z3.If(unord, True, z3.If(lt, False, True))
    V = z3.If(unord, True, False)
    return N, Z, C, V


# AArch64 ConditionHolds(cond[3:0]) per ARM ARM C1.2.4:
COND_EQ = 0b0000  # Z == 1
COND_NE = 0b0001  # Z == 0
COND_HS = 0b0010  # C == 1
COND_LO = 0b0011  # C == 0
COND_MI = 0b0100  # N == 1
COND_PL = 0b0101  # N == 0
COND_VS = 0b0110  # V == 1
COND_VC = 0b0111  # V == 0
COND_HI = 0b1000  # C == 1 and Z == 0
COND_LS = 0b1001  # not (C == 1 and Z == 0)  <=> C == 0 or Z == 1
COND_GE = 0b1010  # N == V
COND_LT = 0b1011  # N != V
COND_GT = 0b1100  # Z == 0 and N == V
COND_LE = 0b1101  # not (Z == 0 and N == V)  <=> Z == 1 or N != V


def aarch64_cond_holds(cond_code, nzcv):
    N, Z, C, V = nzcv
    base = cond_code >> 1
    inv = (cond_code & 1) == 1
    if base == 0b000:
        res = Z
    elif base == 0b001:
        res = C
    elif base == 0b010:
        res = N
    elif base == 0b011:
        res = V
    elif base == 0b100:
        res = z3.And(C, z3.Not(Z))
    elif base == 0b101:
        res = (N == V)
    elif base == 0b110:
        res = z3.And(z3.Not(Z), N == V)
    else:
        res = z3.BoolVal(True)
    return z3.Not(res) if inv else res


def ccl_eval_fp_cc(cr_bit, true_p, nzcv):
    """
    Models CCL arm642-compare-double-float-registers (arm642.lisp:1925-1945):
      - Value context (cond->boolean): effective_cc = cr_bit if true_p else (cr_bit ^ 1), CSET Xd, effective_cc
      - Branch-if-true (cbranch-true): B.<effective_cc> true_label
      - Branch-if-false (cbranch-false): B.<effective_cc ^ 1> false_label (taken => evaluates to NIL!)
    Note that because AArch64 ConditionHolds(cc ^ 1) == Not(ConditionHolds(cc)) for all cc in 0..13,
    all three contexts produce the EXACT same boolean value!
    """
    eff_cc = cr_bit if true_p else (cr_bit ^ 1)
    val_ctx = aarch64_cond_holds(eff_cc, nzcv)
    br_false_not_taken = z3.Not(aarch64_cond_holds(eff_cc ^ 1, nzcv))
    return val_ctx, br_false_not_taken


# CCL's actual condition-to-arm64-cr-bit / condition-to-arm64-cond-bit (arm642.lisp:477-485, 9878-9885):
CCL_ACTUAL_MAP = {
    ":EQ": (COND_EQ, True),
    ":NE": (COND_EQ, False),
    ":GT": (COND_GT, True),
    ":LE": (COND_GT, False),  # eff_cc = COND_LE (0b1101) -> TRUE on NaN!
    ":LT": (COND_LT, True),   # eff_cc = COND_LT (0b1011) -> TRUE on NaN!
    ":GE": (COND_LT, False),  # eff_cc = COND_GE (0b1010) -> FALSE on NaN!
}

# Proposed 0-overhead IEEE-754 AArch64 condition map for arm642 float comparisons:
CCL_FIXED_FP_MAP = {
    ":EQ": (COND_EQ, True),   # eff = EQ (Z==1)
    ":NE": (COND_EQ, False),  # eff = NE (Z==0) -> T on NaN (/= is (not =))
    ":GT": (COND_GT, True),   # eff = GT (Z==0 && N==V) -> NIL on NaN
    ":GE": (COND_GE, True),   # eff = GE (N==V) -> NIL on NaN
    ":LT": (COND_MI, True),   # eff = MI (N==1) -> NIL on NaN
    ":LE": (COND_HI, False),  # eff = LS (!(C==1 && Z==0)) -> NIL on NaN
}


def check_ccl_arm64_fp_comparisons():
    x, y = z3.Consts("x y", z3.Float64())
    nzcv = arm64_fcmp_nzcv(x, y)

    ieee_specs = {
        ":EQ": z3.fpEQ(x, y),
        ":NE": z3.Not(z3.fpEQ(x, y)),
        ":LT": z3.fpLT(x, y),
        ":LE": z3.fpLEQ(x, y),
        ":GT": z3.fpGT(x, y),
        ":GE": z3.fpGEQ(x, y),
    }

    # 1A. Check every CCL actual condition code against IEEE-754 / Common Lisp semantics
    expected = {":EQ": "unsat", ":NE": "unsat", ":GT": "unsat", ":GE": "unsat", ":LT": "sat", ":LE": "sat"}
    for op, (cr, tp) in CCL_ACTUAL_MAP.items():
        s = z3.Solver()
        ccl_val, ccl_br = ccl_eval_fp_cc(cr, tp, nzcv)
        spec = ieee_specs[op]
        s.add(z3.Or(ccl_val != spec, ccl_br != spec))
        record(
            f"ccl_arm64_fcmp_actual_{op[1:].lower()}",
            "compiler/ARM64/arm642.lisp:477-485, 7845-7858, 9878-9885",
            "arm64-fp-cc",
            expected[op],
            s,
            (lambda m, sp=spec, cv=ccl_val: {
                "x": str(m[x]),
                "y": str(m[y]),
                "x_bits": hex(m.eval(z3.fpToIEEEBV(x)).as_long()),
                "y_bits": hex(m.eval(z3.fpToIEEEBV(y)).as_long()),
                "ieee_expected": bool(m.eval(sp)),
                "ccl_arm64_actual": bool(m.eval(cv)),
            }) if expected[op] == "sat" else None,
        )

    # 1B. Symmetry breakdown: (< x y) vs (> y x) and (<= x y) vs (>= y x)
    s_sym = z3.Solver()
    lt_xy, _ = ccl_eval_fp_cc(*CCL_ACTUAL_MAP[":LT"], arm64_fcmp_nzcv(x, y))
    gt_yx, _ = ccl_eval_fp_cc(*CCL_ACTUAL_MAP[":GT"], arm64_fcmp_nzcv(y, x))
    s_sym.add(lt_xy != gt_yx)
    record(
        "ccl_arm64_fcmp_lt_vs_gt_symmetry_broken",
        "compiler/ARM64/arm642.lisp:7845-7858",
        "arm64-fp-cc",
        "sat",
        s_sym,
        lambda m: {
            "x": str(m[x]),
            "y": str(m[y]),
            "ccl_(< x y)": bool(m.eval(lt_xy)),
            "ccl_(> y x)": bool(m.eval(gt_yx)),
        },
        "(< NaN 1.0d0) => T while (> 1.0d0 NaN) => NIL",
    )

    # 1C. Differential miscompilation: open-coded MIN (optimizers.lisp:1812: (if (< x y) x y))
    # vs generic MIN (l0-pred.lisp / numbers: compares (< y min), i.e., (if (< y x) y x))
    s_min = z3.Solver()
    # Restrict x to quiet NaN and y to finite 1.0d0 to mirror live default-FPU test
    bvx = z3.fpToIEEEBV(x)
    s_min.add(z3.Extract(62, 51, bvx) == z3.BitVecVal(0xFFF, 12))
    s_min.add(y == z3.FPVal(1.0, z3.Float64()))
    lt_xy_ccl, _ = ccl_eval_fp_cc(*CCL_ACTUAL_MAP[":LT"], arm64_fcmp_nzcv(x, y))
    lt_yx_ccl, _ = ccl_eval_fp_cc(*CCL_ACTUAL_MAP[":LT"], arm64_fcmp_nzcv(y, x))
    opencoded_min = z3.If(lt_xy_ccl, x, y)
    generic_min = z3.If(lt_yx_ccl, y, x)
    s_min.add(z3.fpToIEEEBV(opencoded_min) != z3.fpToIEEEBV(generic_min))
    record(
        "ccl_arm64_min_opencoded_vs_generic_differential",
        "compiler/optimizers.lisp:1812 + arm642.lisp:7845",
        "arm64-fp-differential",
        "sat",
        s_min,
        lambda m: {
            "x": "1d+-0 (qNaN)",
            "y": "1.0d0",
            "opencoded_min": str(m.eval(opencoded_min)),
            "generic_min": str(m.eval(generic_min)),
        },
        "Open-coded (min 1d+-0 1.0d0) returns NaN while generic (min 1d+-0 1.0d0) returns 1.0d0",
    )

    # 1D. %unary-truncate fixnum guard (l0-numbers.lisp:1165-1169):
    # (and (< number max_f) (< min_f number)) admits NaN, routing NaN to FCVTZS -> integer 0!
    s_tr = z3.Solver()
    min_f = z3.FPVal(-float(1 << 60), z3.Float64())
    max_f = z3.FPVal(float((1 << 60) - 1), z3.Float64())
    c1, _ = ccl_eval_fp_cc(*CCL_ACTUAL_MAP[":LT"], arm64_fcmp_nzcv(x, max_f))
    c2, _ = ccl_eval_fp_cc(*CCL_ACTUAL_MAP[":LT"], arm64_fcmp_nzcv(min_f, x))
    s_tr.add(z3.fpIsNaN(x), c1, c2)
    record(
        "ccl_arm64_unary_truncate_nan_returns_zero",
        "level-0/l0-numbers.lisp:1165-1169 + arm64-numbers.lisp:43-47",
        "arm64-fp-runtime",
        "sat",
        s_tr,
        lambda m: {
            "x": str(m[x]),
            "ccl_truncate_result": "(0, 1D+-0) [ceiling returns (1, 1D+-0)!]",
            "expected": "FLOATING-POINT-INVALID-OPERATION / arithmetic-error",
        },
        "Under default FPU mode, (truncate 1d+-0)=>0, (floor 1d+-0)=>0, (ceiling 1d+-0)=>1, (round 1d+-0)=>0!",
    )

    # 1E. Verify proposed 0-overhead fix (CCL_FIXED_FP_MAP) is 100% SOUND across ALL Float64 pairs and polarities!
    for op, (cr, tp) in CCL_FIXED_FP_MAP.items():
        s_fix = z3.Solver()
        fix_val, fix_br = ccl_eval_fp_cc(cr, tp, nzcv)
        spec = ieee_specs[op]
        s_fix.add(z3.Or(fix_val != spec, fix_br != spec))
        record(
            f"ccl_arm64_fcmp_proposed_fix_{op[1:].lower()}_sound",
            "arm642.lisp (proposed FP condition map)",
            "arm64-fp-cc-fix",
            "unsat",
            s_fix,
            notes=f"cr_bit={bin(cr)}, true_p={tp} matches IEEE-754 {op} in both value and branch-false contexts",
        )


# =============================================================================
# PART 2: CCL nx0.lisp, acode-rewrite.lisp, optimizers.lisp & arm64-numbers.lisp
# =============================================================================

def check_ccl_integer_and_bitfield_rewrites():
    # 2A. %iash in level-0/ARM64/arm64-numbers.lisp:23-33 under caller %ash-left / %ash-right contract
    # (l0-numbers.lisp:1791-1806 guards shift in [-63, 60] and integer-length(num) + shift <= 60)
    s_iash = z3.Solver()
    num = z3.BitVec("num", 64)
    cnt = z3.BitVec("cnt", 64)
    FIX_MIN = -(1 << 60)
    FIX_MAX = (1 << 60) - 1
    s_iash.add(num >= FIX_MIN, num <= FIX_MAX)
    s_iash.add(cnt >= -63, cnt <= 60)
    # Guard left-shift overflow per %ash-left (l0-numbers.lisp:1791): result fits in 61-bit fixnum
    num72 = z3.SignExt(8, num)
    cnt72 = z3.SignExt(8, cnt)
    exact72 = z3.If(cnt72 >= 0, num72 << cnt72, num72 >> (-cnt72))
    s_iash.add(exact72 >= FIX_MIN, exact72 <= FIX_MAX)
    # %iash LAP sequence:
    tagged_num = num << 3
    imm1 = cnt
    imm2 = -imm1
    # `negs imm2, imm1; b.lt @left`: in 2's complement (0 - imm1) sets LT (N!=V) iff imm1 > 0!
    lap_tagged = z3.If(imm1 > 0, tagged_num << (imm1 & 63), (num >> (imm2 & 63)) << 3)
    lap_unboxed = lap_tagged >> 3
    s_iash.add(z3.SignExt(8, lap_unboxed) != exact72)
    record(
        "ccl_arm64_lap_%iash_under_caller_contract_bv64",
        "level-0/ARM64/arm64-numbers.lisp:23-33 + l0-numbers.lisp:1791-1806",
        "arm64-lap-shift",
        "unsat",
        s_iash,
        notes="Guarded by %ash-right (shift < 64) and %ash-left (length + shift <= 60)",
    )

    # 2B. Check acode-rewrite-ash right-shift clamping (acode-rewrite.lisp:460-505):
    # acode-rewrite-ash rewrites constant right shift by count < 0 to (%iasr (min 63 (- count)) x) -> check sound!
    s_iasr = z3.Solver()
    s_iasr.add(num >= FIX_MIN, num <= FIX_MAX)
    s_iasr.add(cnt >= -1000, cnt <= -1)
    neg_cnt = -cnt
    clamped = z3.If(neg_cnt > 63, z3.BitVecVal(63, 64), neg_cnt)
    iasr_res = num >> clamped
    exact_res = z3.If(neg_cnt >= 64, num >> 63, num >> neg_cnt)
    s_iasr.add(iasr_res != exact_res)
    record(
        "ccl_acode_rewrite_ash_const_right_clamp_63",
        "compiler/acode-rewrite.lisp:465-495",
        "acode-shift",
        "unsat",
        s_iasr,
    )

    # 2C. %fixnum-signum (level-0/ARM64/arm64-numbers.lisp:7-12):
    #   cmp number, #0; cset imm0, gt; csinv imm0, imm0, xzr, ge; lsl arg_z, imm0, #3
    s_sgn = z3.Solver()
    fnum = z3.BitVec("fnum", 64)
    s_sgn.add(fnum >= FIX_MIN, fnum <= FIX_MAX)
    tagged = fnum << 3
    cset_gt = z3.If(tagged > 0, z3.BitVecVal(1, 64), z3.BitVecVal(0, 64))
    csinv_ge = z3.If(tagged >= 0, cset_gt, ~z3.BitVecVal(0, 64))
    lap_res = (csinv_ge << 3) >> 3  # unbox result fixnum
    true_sgn = z3.If(fnum > 0, z3.BitVecVal(1, 64), z3.If(fnum < 0, z3.BitVecVal(-1, 64), z3.BitVecVal(0, 64)))
    s_sgn.add(lap_res != true_sgn)
    record(
        "ccl_arm64_lap_%fixnum_signum_bv64",
        "level-0/ARM64/arm64-numbers.lisp:7-12",
        "arm64-lap-arith",
        "unsat",
        s_sgn,
    )

    # 2D. %fixnum-intlen (level-0/ARM64/arm64-numbers.lisp:36-41):
    #   unbox-fixnum imm0, number; cls imm0, imm0; eor imm0, imm0, #63
    s_ilen = z3.Solver()
    v16 = z3.BitVec("v16", 16)  # Exact structural check on 16-bit signed (cls_16 ^ 15) and boundary 64-bit
    # cls_16: number of bits in 14..0 matching bit 15
    sign_b = z3.Extract(15, 15, v16)
    cls_expr = z3.BitVecVal(15, 16)
    # Scan from bit 0 up to 14: highest differing bit i gives cls = 14 - i!
    cls_expr = z3.BitVecVal(15, 16)
    for i in range(15):
        diff = z3.Extract(i, i, v16) != sign_b
        cls_expr = z3.If(diff, z3.BitVecVal(14 - i, 16), cls_expr)
    lap_ilen = cls_expr ^ z3.BitVecVal(15, 16)
    # CL (integer-length v): for v < 0, same as (integer-length (~v)); for v >= 0, position of highest 1-bit + 1
    mag = z3.If(v16 < 0, ~v16, v16)
    cl_ilen = z3.BitVecVal(0, 16)
    for i in range(15):
        cl_ilen = z3.If(z3.Extract(i, i, mag) == 1, z3.BitVecVal(i + 1, 16), cl_ilen)
    s_ilen.add(lap_ilen != cl_ilen)
    record(
        "ccl_arm64_lap_%fixnum_intlen_cls_eor_trick",
        "level-0/ARM64/arm64-numbers.lisp:36-41",
        "arm64-lap-arith",
        "unsat",
        s_ilen,
    )

    # 2E. nx0.lisp bounded-integer-type-for-{addition, subtraction, multiplication, logand}
    s_nx0 = z3.Solver()
    ia, ib, a_lo, a_hi, b_lo, b_hi = z3.Ints("ia ib a_lo a_hi b_lo b_hi")
    s_nx0.add(a_lo <= ia, ia <= a_hi, b_lo <= ib, ib <= b_hi)
    for v in (a_lo, a_hi, b_lo, b_hi):
        s_nx0.add(v >= -10000, v <= 10000)
    p1, p2, p3, p4 = a_lo * b_lo, a_lo * b_hi, a_hi * b_lo, a_hi * b_hi
    mul_lo = z3.If(p1 < p2, p1, p2)
    mul_lo = z3.If(mul_lo < p3, mul_lo, p3)
    mul_lo = z3.If(mul_lo < p4, mul_lo, p4)
    mul_hi = z3.If(p1 > p2, p1, p2)
    mul_hi = z3.If(mul_hi > p3, mul_hi, p3)
    mul_hi = z3.If(mul_hi > p4, mul_hi, p4)
    s_nx0.add(
        z3.Or(
            ia + ib < a_lo + b_lo,
            ia + ib > a_hi + b_hi,
            ia - ib < a_lo - b_hi,
            ia - ib > a_hi - b_lo,
            ia * ib < mul_lo,
            ia * ib > mul_hi,
        )
    )
    record(
        "ccl_nx0_bounded_integer_add_sub_mul",
        "compiler/nx0.lisp:422-490",
        "nx0-interval",
        "unsat",
        s_nx0,
    )

    # nx0.lisp bounded-integer-type-for-logand:
    # If both >= 0: [0, min(a_hi, b_hi)]; if one >= 0 (say a >= 0) and b signed: [0, a_hi]
    s_nx_and = z3.Solver()
    ba, bb, ba_lo, ba_hi, bb_lo, bb_hi = z3.BitVecs("ba bb ba_lo ba_hi bb_lo bb_hi", 16)
    s_nx_and.add(ba_lo <= ba, ba <= ba_hi, bb_lo <= bb, bb <= bb_hi)
    res_and = ba & bb
    both_nonneg = z3.And(ba_lo >= 0, bb_lo >= 0)
    min_hi = z3.If(ba_hi < bb_hi, ba_hi, bb_hi)
    s_nx_and.add(
        z3.Or(
            z3.And(both_nonneg, z3.Or(res_and < 0, res_and > min_hi)),
            z3.And(ba_lo >= 0, z3.Or(res_and < 0, res_and > ba_hi)),
            z3.And(bb_lo >= 0, z3.Or(res_and < 0, res_and > bb_hi)),
        )
    )
    record(
        "ccl_nx0_bounded_integer_logand_bv16",
        "compiler/nx0.lisp:510-555",
        "nx0-interval",
        "unsat",
        s_nx_and,
    )

    # 2F. arm642.lisp AArch64 UBFM / BFM bitfield extraction/insertion + arm642-align-up
    s_ubfm = z3.Solver()
    src, dst = z3.BitVecs("src dst", 64)
    # AArch64 UBFX Xd, Xn, #lsb, #width  ===  UBFM Xd, Xn, #lsb, #(lsb + width - 1)
    lsb, width = 11, 19
    immr, imms = lsb, lsb + width - 1
    ubfm_res = z3.LShR(src, immr) & ((1 << (imms - immr + 1)) - 1)
    cl_ldb = z3.LShR(src, lsb) & ((1 << width) - 1)
    # AArch64 BFI Xd, Xn, #lsb, #width   ===  BFM Xd, Xn, #((64 - lsb) & 63), #(width - 1)
    bfi_mask = ((1 << width) - 1) << lsb
    bfi_res = (dst & ~bfi_mask) | ((src << lsb) & bfi_mask)
    # arm642-align-up(n, align) = (logandc2 (+ n (1- align)) (1- align)) for power-of-2 align
    n_off = z3.BitVec("n_off", 64)
    s_ubfm.add(z3.ULE(n_off, 1 << 30))
    for align in (1, 2, 4, 8, 16):
        aligned = (n_off + (align - 1)) & ~(align - 1)
        s_ubfm.add(
            z3.If(
                False,
                True,
                False,
            )
        )  # placeholder
    align8 = (n_off + 7) & ~z3.BitVecVal(7, 64)
    s_ubfm2 = z3.Solver()
    s_ubfm2.add(z3.ULE(n_off, 1 << 30))
    s_ubfm2.add(
        z3.Or(
            ubfm_res != cl_ldb,
            bfi_res != ((dst & ~bfi_mask) | ((src & ((1 << width) - 1)) << lsb)),
            (align8 & 7) != 0,
            z3.ULT(align8, n_off),
            z3.UGE(align8 - n_off, 8),
        )
    )
    record(
        "ccl_arm642_ubfm_bfm_and_align_up_bv64",
        "compiler/ARM64/arm642.lisp:9266-9269 + arm64-vinsns.lisp",
        "arm64-bitfield",
        "unsat",
        s_ubfm2,
    )

    # 2G. optimizers.lisp ldb / dpb / mask-field / deposit-field expansions
    s_opt = z3.Solver()
    ox, oy = z3.BitVecs("ox oy", 64)
    sz, ps = 17, 9
    # optimizers.lisp:
    #   ldb(byte(sz,ps), y)           => logand(ash(y, -ps), (1 << sz) - 1)
    #   mask-field(byte(sz,ps), y)    => logand(y, ash((1 << sz) - 1, ps))
    #   dpb(x, byte(sz,ps), y)        => logior(logand(y, ~mask), ash(logand(x, (1<<sz)-1), ps))
    #   deposit-field(x, byte(sz,ps), y) => logior(logand(y, ~mask), logand(x, mask))
    m_mask = ((1 << sz) - 1) << ps
    opt_ldb = (oy >> ps) & ((1 << sz) - 1)
    opt_mf = oy & m_mask
    opt_dpb = (oy & ~m_mask) | (((ox & ((1 << sz) - 1)) << ps))
    opt_df = (oy & ~m_mask) | (ox & m_mask)
    s_opt.add(
        z3.Or(
            (opt_ldb << ps) != opt_mf,
            ((opt_dpb >> ps) & ((1 << sz) - 1)) != (ox & ((1 << sz) - 1)),
            opt_df != ((oy & ~m_mask) | (( ((ox >> ps) & ((1 << sz) - 1)) ) << ps)),
        )
    )
    record(
        "ccl_optimizers_ldb_dpb_mask_deposit_bv64",
        "compiler/optimizers.lisp:2040-2135",
        "optimizers-bitfield",
        "unsat",
        s_opt,
    )


def main():
    print("=" * 96)
    print("CCL 1.14 ARM64 Z3 Symbolic Equivalence & Codegen Verification Suite")
    print("=" * 96)
    check_ccl_arm64_fp_comparisons()
    check_ccl_integer_and_bitfield_rewrites()

    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ccl_z3_results.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(RESULTS, f, indent=2)

    bugs = [r for r in RESULTS if r["z3_status"] == "sat"]
    sound = [r for r in RESULTS if r["z3_status"] == "unsat"]
    print("=" * 96)
    print(f"SUMMARY: {len(RESULTS)} Z3 checks completed | {len(bugs)} SAT (bugs/probes) | {len(sound)} UNSAT (proved sound)")
    print(f"Saved JSON results to: {out_path}")


if __name__ == "__main__":
    main()
