#!/usr/bin/env python3
"""
Stage 3 Differential Fuzzer: Register Pressure, Target Aliasing, Stack Spills,
DX/MV/Closure Frames, and Backend Immediate / Array Displacement Boundaries.

Targets:
  - sbcl-arm64  (/opt/homebrew/bin/sbcl)
  - sbcl-x86-64 (ssh hbox .../run-sbcl.sh)
  - ccl-arm64   (/Users/ember/dev/ccl/darm64cl)
  - ccl-x86-64  (ssh hbox .../lx86cl64)

Test families:
  1. gpr_pressure_trees: 3..10 live GPR temporaries (fixnum, s64, u64) with
     nested non-commutative ops (- (- a b) (- c d)), logandc2/logorc2, ash,
     ldb/dpb, truncate/rem, and backend immediate boundary constants.
  2. fpr_pressure_trees: 4..12 live single-float / double-float temporaries
     with nested non-commutative FP trees & GPR-FPR conversions.
  3. complex_spill_trees: 4..20 live (complex double-float) & (complex single-float)
     temporaries forcing complex-double-stack / complex-single-stack spills,
     realpart/imagpart extraction, multiplication, and array round-trips
     (excludes known HC-W3-6 ccl-x86-64 complex-single + / -).
  4. mv_dx_closure_pressure: multiple-value-call, multiple-value-prog1,
     dynamic-extent &rest / &key local functions, and closures mutating shared
     lexical cells while 4..8 unboxed/boxed values remain live across calls
     (excludes known SB-2610-1 (values-list (cdr rest))).
  5. array_imm_boundaries_1d: 1D simple & displaced specialized arrays across
     bit, u8/s8, u16/s16, u32/s32, u64/s64, fixnum, single-float, double-float,
     (complex single-float), (complex double-float) at constant & dynamic indices
     spanning backend displacement boundaries (0, 31/32, 255/256, 507/508/512,
     1023/1024, 2047/2048, 4095/4096, 8191/8192, 32792/32793/32800).
  6. array_multidim_2d_3d: 2D and 3D simple & displaced specialized arrays across
     element types at constant & dynamic indices (filtering known CCL-CG-1
     untargeted-reg subform clobber by using clean lexical/constant operands).
  7. bitfield_shift_boundaries: nested ldb/dpb/mask-field/deposit-field/logbitp/ash
     at all backend immediate boundaries (#x0fff/#x1000, #xffff/#x10000,
     #x7ffff/#x80000, #x0fffffff/#x10000000, 2^31-1/2^31/2^32, 2^59/2^60/2^62/2^63-1).
"""

import argparse
import os
import random
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import List, Tuple


LOCAL_TIMEOUT = "/opt/homebrew/bin/timeout"
SBCL_ARM64 = "/opt/homebrew/bin/sbcl"
CCL_ARM64 = "/Users/ember/dev/ccl/darm64cl"
SBCL_X86_64 = "/home/hbox/ca-sbcl-root/dl-2.6.10/sbcl-2.6.10-x86-64-linux/run-sbcl.sh"
CCL_X86_64 = "/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64"


@dataclass
class RegImmCase:
    cid: str
    family: str
    params: List[Tuple[str, str, str]]  # (name, cl_type, init_expr)
    body: str
    description: str


LISP_HEADER = r"""
(defpackage #:regimm-fuzz (:use #:cl))
(in-package #:regimm-fuzz)

(declaim (notinline opaque-idx))
(defun opaque-idx (i) i)

(defun canon (x)
  (cond
    ((eq x t) "T")
    ((null x) "NIL")
    ((integerp x) (format nil "I:~D" x))
    ((rationalp x) (format nil "R:~D/~D" (numerator x) (denominator x)))
    ((typep x 'single-float)
     (if (zerop x)
         "SF:0"
         (multiple-value-bind (sig exp sgn) (integer-decode-float x)
           (format nil "SF:~D:~D:~D" sig exp sgn))))
    ((typep x 'double-float)
     (if (zerop x)
         "DF:0"
         (multiple-value-bind (sig exp sgn) (integer-decode-float x)
           (format nil "DF:~D:~D:~D" sig exp sgn))))
    ((complexp x)
     (format nil "C(~A,~A)" (canon (realpart x)) (canon (imagpart x))))
    ((characterp x)
     (format nil "CH:~D" (char-code x)))
    ((symbolp x)
     (format nil "SYM:~A:~A"
             (if (symbol-package x) (package-name (symbol-package x)) "#")
             (symbol-name x)))
    ((bit-vector-p x)
     ;; Summarize large bit-vectors by length + list of set bit indices!
     (if (> (length x) 64)
         (format nil "BVL:~D:~{~D,~}"
                 (length x)
                 (loop for i below (length x) when (= 1 (aref x i)) collect i))
         (format nil "BV:~D:~{~D~}" (length x) (coerce x 'list))))
    ((stringp x)
     (format nil "STR:~D:~{~D,~}" (length x) (map 'list #'char-code x)))
    ((consp x)
     (format nil "(~A . ~A)" (canon (car x)) (canon (cdr x))))
    ((arrayp x)
     (format nil "ARR:~S:~{~A;~}"
             (array-dimensions x)
             (loop for i below (min 64 (array-total-size x))
                   collect (canon (row-major-aref x i)))))
    (t (format nil "OTHER:~A" (type-of x)))))

(defun run-form (form arg-thunks)
  (handler-case
      (let ((fn (handler-bind ((warning #'muffle-warning)
                               #+sbcl (sb-ext:compiler-note #'muffle-warning))
                  (compile nil form))))
        (handler-case
            (let ((args (mapcar #'funcall arg-thunks)))
              (canon (multiple-value-list (apply fn args))))
          (error (e)
            (format nil "RT-ERR:~A" (substitute #\Space #\Newline (princ-to-string e))))))
    (error (e)
      (format nil "COMP-ERR:~A" (substitute #\Space #\Newline (princ-to-string e))))))
"""


IMM_CONSTS_S64 = [
    "0", "1", "-1", "31", "-32", "63", "-64", "255", "-256",
    "#x0fff", "(- #x0fff)", "#x1000", "(- #x1000)", "#x1001", "(- #x1001)",
    "#xffff", "(- #xffff)", "#x10000", "(- #x10000)",
    "#x7ffff", "(- #x7ffff)", "#x80000", "(- #x80000)",
    "#x0fffffff", "(- #x0fffffff)", "#x10000000", "(- #x10000000)",
    "#x7fffffff", "(- #x80000000)", "#xffffffff", "(- #xffffffff)", "#x100000000", "(- #x100000000)",
    "(1- (ash 1 59))", "(ash 1 59)", "(- (ash 1 59))",
    "(1- (ash 1 60))", "(ash 1 60)", "(- (ash 1 60))",
    "(1- (ash 1 62))", "(ash 1 62)", "(- (ash 1 62))",
    "(1- (ash 1 63))", "(- (ash 1 63))",
]

IMM_CONSTS_U64 = [
    "0", "1", "31", "32", "63", "64", "255", "256",
    "#x0fff", "#x1000", "#x1001", "#xffff", "#x10000",
    "#x7ffff", "#x80000", "#x0fffffff", "#x10000000",
    "#x7fffffff", "#x80000000", "#xffffffff", "#x100000000",
    "(1- (ash 1 59))", "(ash 1 59)", "(1- (ash 1 60))", "(ash 1 60)",
    "(1- (ash 1 62))", "(ash 1 62)", "(1- (ash 1 63))", "(ash 1 63)", "(1- (ash 1 64))",
]

IMM_CONSTS_FIXNUM = [
    "0", "1", "-1", "31", "-32", "255", "-256",
    "#x0fff", "(- #x0fff)", "#x1000", "(- #x1000)",
    "#xffff", "(- #xffff)", "#x10000", "(- #x10000)",
    "#x7ffff", "#x80000", "#x0fffffff", "#x10000000",
    "#x7fffffff", "(- #x80000000)",
    "(1- (ash 1 58))", "(- (ash 1 58))",
]

DYADIC_SF = ["-8.0f0", "-3.5f0", "-1.5f0", "-0.5f0", "0.0f0", "0.25f0", "0.5f0", "1.0f0", "1.5f0", "2.0f0", "4.0f0"]
DYADIC_DF = ["-8.0d0", "-3.5d0", "-1.5d0", "-0.5d0", "0.0d0", "0.25d0", "0.5d0", "1.0d0", "1.5d0", "2.0d0", "4.0d0"]


def build_nested_int_tree(rng: random.Random, vars_pool: List[str], const_pool: List[str], depth: int, mod_bits: int) -> str:
    if depth <= 0:
        if rng.random() < 0.72:
            return rng.choice(vars_pool)
        return rng.choice(const_pool)
    kind = rng.choice(["sub", "add", "xor", "ior", "andc2", "ash", "dpb"])
    lhs = build_nested_int_tree(rng, vars_pool, const_pool, depth - 1, mod_bits)
    rhs = build_nested_int_tree(rng, vars_pool, const_pool, depth - 1, mod_bits)
    if kind == "sub":
        return f"(ldb (byte {mod_bits} 0) (- {lhs} {rhs}))"
    if kind == "add":
        return f"(ldb (byte {mod_bits} 0) (+ {lhs} {rhs}))"
    if kind == "xor":
        return f"(logxor {lhs} {rhs})"
    if kind == "ior":
        return f"(logior {lhs} {rhs})"
    if kind == "andc2":
        return f"(logandc2 {lhs} {rhs})"
    if kind == "ash":
        sh = rng.choice([-33, -32, -16, -7, -1, 0, 1, 3, 8, 16, 31, 32])
        return f"(ldb (byte {mod_bits} 0) (ash {lhs} {sh}))"
    sz = rng.choice([1, 4, 8, 16, 31, 32])
    pos = rng.choice([0, 1, 7, 15, 16, 31, 32])
    if pos + sz > mod_bits:
        pos = max(0, mod_bits - sz)
    return f"(dpb {lhs} (byte {sz} {pos}) {rhs})"


def build_nested_fp_tree(rng: random.Random, vars_pool: List[str], const_pool: List[str], depth: int, is_double: bool) -> str:
    if depth <= 0:
        return rng.choice(vars_pool) if rng.random() < 0.75 else rng.choice(const_pool)
    op = rng.choice(["-", "+", "*", "div_pow2"])
    lhs = build_nested_fp_tree(rng, vars_pool, const_pool, depth - 1, is_double)
    if op == "div_pow2":
        denom = rng.choice(["2.0d0", "4.0d0", "-2.0d0"] if is_double else ["2.0f0", "4.0f0", "-2.0f0"])
        return f"(/ {lhs} {denom})"
    rhs = build_nested_fp_tree(rng, vars_pool, const_pool, depth - 1, is_double)
    if op == "*":
        # Scale down by 0.25 so deep products stay strictly exact without underflow/overflow
        scale = "0.25d0" if is_double else "0.25f0"
        return f"(* {scale} (* {lhs} {rhs}))"
    return f"({op} {lhs} {rhs})"


def generate_cases(seed: int, count: int) -> List[RegImmCase]:
    rng = random.Random(seed)
    cases: List[RegImmCase] = []

    families = [
        "gpr_pressure_trees",
        "fpr_pressure_trees",
        "complex_spill_trees",
        "mv_dx_closure_pressure",
        "array_imm_boundaries_1d",
        "array_multidim_2d_3d",
        "bitfield_shift_boundaries",
    ]

    for idx in range(count):
        fam = families[idx % len(families)]
        cid = f"R{idx:04d}_{fam}"

        if fam == "gpr_pressure_trees":
            n_temps = rng.randint(4, 10)
            rep = rng.choice([
                ("fixnum", IMM_CONSTS_FIXNUM, 58),
                ("(signed-byte 64)", IMM_CONSTS_S64, 62),
                ("(unsigned-byte 64)", IMM_CONSTS_U64, 64),
            ])
            ctype, cpool, mod_bits = rep
            n_params = rng.randint(3, 6)
            params = [(f"p{i}", ctype, rng.choice(cpool)) for i in range(n_params)]
            avail = [f"p{i}" for i in range(n_params)]
            let_lines = []
            for t_i in range(n_temps):
                tname = f"t{t_i}"
                expr = build_nested_int_tree(rng, avail, cpool, rng.choice([2, 3]), mod_bits)
                let_lines.append(f"({tname} {expr})")
                avail.append(tname)
            final_tree = build_nested_int_tree(rng, avail, cpool, 3, mod_bits)
            # Keep ALL temporaries live past final_tree to force maximum register pressure & spills!
            live_xor = f"(logxor {' '.join([f't{i}' for i in range(n_temps)])})"
            body = f"(let* ({' '.join(let_lines)}) (values {final_tree} {live_xor}))"
            cases.append(RegImmCase(cid, fam, params, body, f"GPR pressure n={n_temps} {ctype}"))

        elif fam == "fpr_pressure_trees":
            is_double = rng.random() < 0.6
            fty = "double-float" if is_double else "single-float"
            cpool = DYADIC_DF if is_double else DYADIC_SF
            n_temps = rng.randint(5, 14)
            n_params = rng.randint(3, 6)
            params = [(f"x{i}", fty, rng.choice(cpool)) for i in range(n_params)]
            # Also add 2 fixnum GPR params converted to float mid-tree
            params.append(("gi0", "(integer -64 64)", str(rng.randint(-32, 32))))
            params.append(("gi1", "(integer -64 64)", str(rng.randint(-32, 32))))
            proto = "0.0d0" if is_double else "0.0f0"
            avail = [f"x{i}" for i in range(n_params)]
            let_lines = [
                f"(gf0 (float gi0 {proto}))",
                f"(gf1 (float gi1 {proto}))",
            ]
            avail.extend(["gf0", "gf1"])
            for t_i in range(n_temps):
                tname = f"f{t_i}"
                expr = build_nested_fp_tree(rng, avail, cpool, 2, is_double)
                let_lines.append(f"({tname} (the {fty} {expr}))")
                avail.append(tname)
            final_tree = build_nested_fp_tree(rng, avail, cpool, 2, is_double)
            # Combine all f_i in exact addition/subtraction pairs so all FPRs stay live!
            live_sum = f"(+ {' '.join([f'f{i}' for i in range(n_temps)])})"
            body = f"(let* ({' '.join(let_lines)}) (values {final_tree} {live_sum} (+ gi0 gi1)))"
            cases.append(RegImmCase(cid, fam, params, body, f"FPR pressure n={n_temps} {fty}"))

        elif fam == "complex_spill_trees":
            is_double = rng.random() < 0.65
            if is_double:
                cty = "(complex double-float)"
                fty = "double-float"
                fpool = ["-2.0d0", "-1.0d0", "-0.5d0", "0.0d0", "0.5d0", "1.0d0", "2.0d0"]
                ops = ["+", "-", "*"]
            else:
                # Exclude + / - on (complex single-float) per known HC-W3-6 on ccl-x86-64;
                # test *, complex, realpart, imagpart, =, and stack spills up to 20 live temporaries!
                cty = "(complex single-float)"
                fty = "single-float"
                fpool = ["-2.0f0", "-1.0f0", "-0.5f0", "0.0f0", "0.5f0", "1.0f0", "2.0f0"]
                ops = ["*"]
            # Use up to 20 live complex temporaries to force complex-double-stack / complex-single-stack spills!
            n_temps = rng.choice([4, 8, 14, 20])
            params = [
                ("z0", cty, f"#c({rng.choice(fpool)} {rng.choice(fpool)})"),
                ("z1", cty, f"#c({rng.choice(fpool)} {rng.choice(fpool)})"),
                ("r0", fty, rng.choice(fpool)),
                ("im0", fty, rng.choice(fpool)),
            ]
            avail = ["z0", "z1"]
            let_lines = [f"(z2 (complex r0 im0))"]
            avail.append("z2")
            scale = "#c(0.5d0 0.0d0)" if is_double else "#c(0.5f0 0.0f0)"
            for t_i in range(n_temps):
                tname = f"cz{t_i}"
                a = rng.choice(avail)
                b = rng.choice(avail)
                op = rng.choice(ops)
                if op == "*":
                    expr = f"(* {scale} (* {a} {b}))"
                else:
                    expr = f"({op} {a} {b})"
                if rng.random() < 0.3:
                    expr = f"(complex (imagpart {a}) (realpart {b}))"
                let_lines.append(f"({tname} (the {cty} {expr}))")
                avail.append(tname)
            # Extract realpart & imagpart of ALL spilled/register temporaries so all 20 stay live simultaneously!
            re_parts = " ".join(f"(realpart cz{i})" for i in range(n_temps))
            im_parts = " ".join(f"(imagpart cz{i})" for i in range(n_temps))
            body = f"(let* ({' '.join(let_lines)}) (values cz{n_temps - 1} (+ {re_parts}) (+ {im_parts})))"
            cases.append(RegImmCase(cid, fam, params, body, f"Complex spill n={n_temps} {cty}"))

        elif fam == "mv_dx_closure_pressure":
            sub = rng.choice(["mv_call_pressure", "mv_prog1_pressure", "dx_rest_key", "closure_shared_cells"])
            params = [
                ("a", "fixnum", str(rng.randint(-500, 500))),
                ("b", "(signed-byte 64)", rng.choice(IMM_CONSTS_S64[:18])),
                ("c", "double-float", rng.choice(DYADIC_DF)),
                ("d", "fixnum", str(rng.randint(1, 100))),
            ]
            if sub == "mv_call_pressure":
                n_mv = rng.choice([0, 1, 3, 6, 8])
                vals1 = " ".join(f"(+ a {k})" for k in range(n_mv))
                vals2 = " ".join(f"(- d {k})" for k in range(3))
                body = (
                    f"(let ((t0 (- a d)) (t1 (logxor b #x1000)) (t2 (* c 2.0d0)) (t3 (+ a d 7))) "
                    f"  (flet ((prod1 (x) (declare (notinline prod1)) (values {vals1})) "
                    f"         (prod2 (x) (declare (notinline prod2)) (values {vals2})) "
                    f"         (comb (&rest xs) (declare (dynamic-extent xs)) (reduce #'+ xs :initial-value 0))) "
                    f"    (declare (notinline prod1 prod2)) "
                    f"    (list (multiple-value-call #'comb (prod1 a) (prod2 d)) t0 t1 t2 t3)))"
                )
            elif sub == "mv_prog1_pressure":
                body = (
                    "(let ((u0 (ldb (byte 64 0) (+ b #x10000))) (u1 (- c 0.5d0)) (u2 (* a d))) "
                    "  (flet ((gen (k) (values (+ k 1) (- k 2) (ash k 3) :tag))) "
                    "    (declare (notinline gen)) "
                    "    (multiple-value-bind (v0 v1 v2 v3) "
                    "        (multiple-value-prog1 (gen a) "
                    "          (setq u0 (logxor u0 d)) "
                    "          (setq u1 (+ u1 1.5d0))) "
                    "      (list v0 v1 v2 v3 u0 u1 u2))))"
                )
            elif sub == "dx_rest_key":
                # Avoid (values-list (cdr rest)) per SB-2610-1
                body = (
                    "(let ((live0 (+ a 19)) (live1 (logand b #xffffffff)) (live2 (+ c 4.0d0))) "
                    "  (flet ((kfn (x &key (alpha 10 alpha-p) (beta -3 beta-p) (gamma 0) &allow-other-keys) "
                    "           (list x alpha (not (not alpha-p)) beta (not (not beta-p)) gamma)) "
                    "         (rfn (x &rest more) "
                    "           (declare (dynamic-extent more)) "
                    "           (list x (length more) (nth 0 more) (nth 2 more)))) "
                    "    (declare (dynamic-extent #'kfn #'rfn) (notinline kfn rfn)) "
                    "    (list (kfn a :beta d :extra 99 :alpha (+ a d)) "
                    "          (rfn d a live0 live1 live2) "
                    "          live0 live1 live2)))"
                )
            else:
                body = (
                    "(let ((cell-i a) (cell-s b) (cell-f c)) "
                    "  (flet ((mut1 (delta) (incf cell-i delta) (setq cell-s (ldb (byte 60 0) (+ cell-s delta))) cell-i) "
                    "         (mut2 (scale) (setq cell-f (* cell-f scale)) (decf cell-i 3) cell-f)) "
                    "    (declare (dynamic-extent #'mut1 #'mut2) (notinline mut1 mut2)) "
                    "    (let ((r1 (mut1 d)) (r2 (mut2 0.5d0)) (r3 (mut1 7))) "
                    "      (list r1 r2 r3 cell-i cell-s cell-f))))"
                )
            cases.append(RegImmCase(cid, fam, params, body, f"MV/DX/Closure {sub}"))

        elif fam == "array_imm_boundaries_1d":
            # Critical 1D array boundary indices across all specialized element types!
            # Includes > 32792 on simple-bit-vector, > 255 on single-float, > 507 on complex-double-float,
            # > 1023 on 64-bit, > 2047 on 32-bit, > 4095 on 16-bit, > 8191 on 8-bit, plus displaced vectors!
            elem_specs = [
                ("bit", 33024, [0, 1, 31, 32, 63, 64, 4095, 4096, 32791, 32792, 32793, 32800, 33000], "0", "1", "1"),
                ("(unsigned-byte 8)", 8300, [0, 1, 255, 256, 4095, 4096, 8191, 8192, 8250], "3", "200", "129"),
                ("(signed-byte 8)", 8300, [0, 1, 127, 255, 4095, 4096, 8191, 8192, 8250], "-3", "-120", "105"),
                ("(unsigned-byte 16)", 4200, [0, 1, 255, 256, 2047, 2048, 4095, 4096, 4150], "7", "60000", "32769"),
                ("(signed-byte 16)", 4200, [0, 1, 255, 256, 2047, 2048, 4095, 4096, 4150], "-7", "-30000", "16385"),
                ("(unsigned-byte 32)", 2200, [0, 1, 255, 256, 1023, 1024, 2047, 2048, 2150], "11", "#xf0000001", "#x80001234"),
                ("(signed-byte 32)", 2200, [0, 1, 255, 256, 1023, 1024, 2047, 2048, 2150], "-11", "(- #x70000001)", "#x40001234"),
                ("(unsigned-byte 64)", 1150, [0, 1, 255, 511, 512, 1023, 1024, 1100], "13", "#x9000000000000005", "#x123456789abcdef0"),
                ("(signed-byte 64)", 1150, [0, 1, 255, 511, 512, 1023, 1024, 1100], "-13", "(- #x7000000000000005)", "#x123456789abcdef0"),
                ("fixnum", 1150, [0, 1, 255, 511, 512, 1023, 1024, 1100], "5", "(1- (ash 1 50))", "(- (ash 1 49))"),
                ("single-float", 2200, [0, 1, 254, 255, 256, 257, 2047, 2048, 2150], "0.5f0", "-3.25f0", "6.5f0"),
                ("double-float", 1150, [0, 1, 255, 511, 512, 1023, 1024, 1100], "0.5d0", "-3.25d0", "6.5d0"),
                ("(complex single-float)", 1150, [0, 1, 255, 511, 512, 1023, 1024, 1100], "#c(0.5f0 -0.5f0)", "#c(-2.5f0 1.25f0)", "#c(4.0f0 -1.5f0)"),
                ("(complex double-float)", 600, [0, 1, 255, 506, 507, 508, 509, 512, 580], "#c(0.5d0 -0.5d0)", "#c(-2.5d0 1.25d0)", "#c(4.0d0 -1.5d0)"),
            ]
            ety, alen, idx_choices, init_el, v_pre, v_set = rng.choice(elem_specs)
            k1 = rng.choice(idx_choices)
            k2 = rng.choice(idx_choices)
            while k2 == k1:
                k2 = rng.choice(idx_choices)
            displaced = rng.random() < 0.25
            if not displaced:
                arr_ty = f"(simple-array {ety} ({alen}))"
                arr_init = (
                    f"(let ((a (make-array {alen} :element-type '{ety} :initial-element {init_el})) "
                    f"      (i1 (opaque-idx {k1}))) "
                    f"  (setf (aref a i1) {v_pre}) a)"
                )
            else:
                arr_ty = f"(array {ety} ({alen}))"
                arr_init = (
                    f"(let* ((base (make-array {alen + 16} :element-type '{ety} :initial-element {init_el})) "
                    f"       (a (make-array {alen} :element-type '{ety} :displaced-to base :displaced-index-offset 8)) "
                    f"       (i1 (opaque-idx {k1}))) "
                    f"  (setf (aref a i1) {v_pre}) a)"
                )
            params = [
                ("arr", arr_ty, arr_init),
                ("dyn_k1", f"(integer 0 {alen - 1})", str(k1)),
                ("dyn_k2", f"(integer 0 {alen - 1})", str(k2)),
                ("newv", ety, v_set),
            ]
            # Read at constant k1, write at constant k2, then read back via dynamic dyn_k2 AND constant k2!
            body = (
                f"(let ((r_const_pre (aref arr {k1})) "
                f"      (r_dyn_pre (aref arr dyn_k1))) "
                f"  (setf (aref arr {k2}) newv) "
                f"  (list r_const_pre r_dyn_pre (aref arr {k2}) (aref arr dyn_k2)))"
            )
            cases.append(RegImmCase(cid, fam, params, body, f"1D {'displaced' if displaced else 'simple'} {ety} k1={k1} k2={k2}"))

        elif fam == "array_multidim_2d_3d":
            rank = rng.choice([2, 3])
            elem_specs_md = [
                ("bit", "0", "1"),
                ("(unsigned-byte 8)", "2", "240"),
                ("(signed-byte 16)", "-5", "-20000"),
                ("(unsigned-byte 32)", "9", "#x9abcdef0"),
                ("(signed-byte 64)", "-9", "(- #x123456789abc)"),
                ("double-float", "0.25d0", "-7.5d0"),
                ("(complex double-float)", "#c(1.0d0 -1.0d0)", "#c(-3.5d0 2.25d0)"),
                ("t", ":init", ":stored"),
            ]
            ety, init_el, v_set = rng.choice(elem_specs_md)
            displaced = rng.random() < 0.25
            if rank == 2:
                # Include large bit 2D array (400 x 100 = 40,000 > 32792) as well as compact 2D arrays!
                dims = (400, 100) if (ety == "bit" and rng.random() < 0.5) else (12, 16)
                d0, d1 = dims
                i0 = rng.choice([0, d0 - 1, min(328, d0 - 1), rng.randint(0, d0 - 1)])
                j0 = rng.choice([0, d1 - 1, rng.randint(0, d1 - 1)])
                arr_kind = "array" if displaced else "simple-array"
                arr_ty = f"({arr_kind} {ety} ({d0} {d1}))"
                if displaced:
                    arr_init = (
                        f"(let ((base (make-array {d0 * d1 + 8} :element-type '{ety} :initial-element {init_el}))) "
                        f"  (make-array '({d0} {d1}) :element-type '{ety} :displaced-to base :displaced-index-offset 4))"
                    )
                else:
                    arr_init = f"(make-array '({d0} {d1}) :element-type '{ety} :initial-element {init_el})"
                params = [
                    ("a", arr_ty, arr_init),
                    ("di", f"(integer 0 {d0 - 1})", str(i0)),
                    ("dj", f"(integer 0 {d1 - 1})", str(j0)),
                    ("nv", ety, v_set),
                ]
                body = (
                    f"(progn "
                    f"  (setf (aref a {i0} {j0}) nv) "
                    f"  (list (aref a {i0} {j0}) (aref a di dj) (row-major-aref a (+ (* di {d1}) dj))))"
                )
            else:
                dims = (400, 10, 10) if (ety == "bit" and rng.random() < 0.4) else (5, 6, 8)
                d0, d1, d2 = dims
                i0 = rng.choice([0, d0 - 1, min(328, d0 - 1), rng.randint(0, d0 - 1)])
                j0 = rng.randint(0, d1 - 1)
                k0 = rng.randint(0, d2 - 1)
                arr_kind = "array" if displaced else "simple-array"
                arr_ty = f"({arr_kind} {ety} ({d0} {d1} {d2}))"
                if displaced:
                    arr_init = (
                        f"(let ((base (make-array {d0 * d1 * d2 + 8} :element-type '{ety} :initial-element {init_el}))) "
                        f"  (make-array '({d0} {d1} {d2}) :element-type '{ety} :displaced-to base :displaced-index-offset 4))"
                    )
                else:
                    arr_init = f"(make-array '({d0} {d1} {d2}) :element-type '{ety} :initial-element {init_el})"
                params = [
                    ("a", arr_ty, arr_init),
                    ("di", f"(integer 0 {d0 - 1})", str(i0)),
                    ("dj", f"(integer 0 {d1 - 1})", str(j0)),
                    ("dk", f"(integer 0 {d2 - 1})", str(k0)),
                    ("nv", ety, v_set),
                ]
                body = (
                    f"(progn "
                    f"  (setf (aref a {i0} {j0} {k0}) nv) "
                    f"  (list (aref a {i0} {j0} {k0}) (aref a di dj dk)))"
                )
            cases.append(RegImmCase(cid, fam, params, body, f"{rank}D {'displaced' if displaced else 'simple'} {ety}"))

        elif fam == "bitfield_shift_boundaries":
            ctype, cpool = rng.choice([
                ("fixnum", IMM_CONSTS_FIXNUM),
                ("(signed-byte 64)", IMM_CONSTS_S64),
                ("(unsigned-byte 64)", IMM_CONSTS_U64),
            ])
            sz1 = rng.choice([0, 1, 7, 8, 15, 16, 31, 32, 59, 60, 62, 63, 64])
            pos1 = rng.choice([0, 1, 7, 8, 15, 16, 31, 32, 59, 60, 62, 63, 64])
            sz2 = rng.choice([1, 4, 8, 16, 31, 32, 63, 64])
            pos2 = rng.choice([0, 1, 15, 16, 31, 32, 62, 63])
            bit_k = rng.choice([0, 1, 15, 31, 32, 58, 59, 60, 61, 62, 63, 64])
            sh = rng.choice([-64, -63, -32, -31, -1, 0, 1, 15, 16, 31, 32, 59, 60, 62, 63])
            imm = rng.choice(cpool)
            params = [
                ("x", ctype, rng.choice(cpool)),
                ("y", ctype, rng.choice(cpool)),
                ("dsz", "(integer 0 64)", str(sz1)),
                ("dpos", "(integer 0 64)", str(pos1)),
            ]
            body = (
                f"(let* ((f1 (ldb (byte {sz1} {pos1}) x)) "
                f"       (f1_dyn (ldb (byte dsz dpos) x)) "
                f"       (f2 (dpb y (byte {sz2} {pos2}) x)) "
                f"       (f3 (mask-field (byte {sz1} {pos1}) y)) "
                f"       (f4 (deposit-field x (byte {sz2} {pos2}) y)) "
                f"       (f5 (ldb (byte 64 0) (ash (logxor x {imm}) {sh}))) "
                f"       (b0 (logbitp {bit_k} f2))) "
                f"  (list f1 f1_dyn f2 f3 f4 f5 b0))"
            )
            cases.append(RegImmCase(cid, fam, params, body, f"bitfield/shift {ctype} sz={sz1} pos={pos1} sh={sh}"))

    return cases


POLICIES = [
    ("P0_s1_saf3", "((speed 1) (safety 3) (debug 1) (space 1))"),
    ("P1_s3_saf3", "((speed 3) (safety 3) (debug 0) (space 0))"),
    ("P2_s1_saf1", "((speed 1) (safety 1) (debug 1) (space 1))"),
    ("P3_s3_saf0", "((speed 3) (safety 0) (debug 0) (space 0))"),
]


def build_case_lambda(c: RegImmCase, opt_qual: str) -> str:
    pnames = " ".join(p[0] for p in c.params)
    tdecls = " ".join(f"(type {p[1]} {p[0]})" for p in c.params if p[1] != "t")
    return f"'(lambda ({pnames}) (declare (optimize {opt_qual}) {tdecls}) {c.body})"


def build_lisp_batch(cases: List[RegImmCase], active_policies: List[Tuple[str, str]]) -> str:
    lines = [LISP_HEADER]
    for c in cases:
        thunks = " ".join(f"(lambda () {p[2]})" for p in c.params)
        lines.append(f"(let ((thunks (list {thunks})))")
        pexprs = [f"(run-form {build_case_lambda(c, pq)} thunks)" for _, pq in active_policies]
        slots = "|".join(["~A"] * len(active_policies))
        lines.append(f'  (format t "RES|{c.cid}|{slots}~%" {" ".join(pexprs)}))')
    lines.append("(finish-output)")
    return "\n".join(lines) + "\n"


def run_target(target: str, lisp_source: str, timeout_sec: int = 90) -> dict:
    with tempfile.NamedTemporaryFile("w", suffix=".lisp", delete=False) as tf:
        tf.write(lisp_source)
        local_path = tf.name

    try:
        if target == "sbcl-arm64":
            cmd = [
                LOCAL_TIMEOUT, "--kill-after=5s", f"{timeout_sec}s",
                SBCL_ARM64, "--noinform", "--non-interactive", "--load", local_path,
            ]
            proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        elif target == "ccl-arm64":
            cmd = [
                LOCAL_TIMEOUT, "--kill-after=5s", f"{timeout_sec}s",
                CCL_ARM64, "--no-init", "--batch", "--load", local_path, "--eval", "(ccl:quit 0)",
            ]
            proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        elif target in ("sbcl-x86-64", "ccl-x86-64"):
            remote_tmp = f"/tmp/w4_regimm_{os.getpid()}_{random.randint(10000, 99999)}.lisp"
            try:
                subprocess.run(
                    [LOCAL_TIMEOUT, "--kill-after=5s", "30s", "scp", "-q", local_path, f"hbox:{remote_tmp}"],
                    check=True, capture_output=True, text=True,
                )
                if target == "sbcl-x86-64":
                    rcmd = f"swarm-build timeout {timeout_sec}s {shlex.quote(SBCL_X86_64)} --noinform --non-interactive --load {shlex.quote(remote_tmp)}"
                else:
                    rcmd = f"swarm-build timeout {timeout_sec}s {shlex.quote(CCL_X86_64)} --no-init --batch --load {shlex.quote(remote_tmp)} --eval '(ccl:quit 0)'"
                proc = subprocess.run(
                    [LOCAL_TIMEOUT, "--kill-after=5s", f"{timeout_sec + 15}s", "ssh", "hbox", rcmd],
                    capture_output=True, text=True, check=False,
                )
            finally:
                subprocess.run(
                    [LOCAL_TIMEOUT, "--kill-after=5s", "15s", "ssh", "hbox", f"rm -f {shlex.quote(remote_tmp)}"],
                    capture_output=True, text=True, check=False,
                )
        else:
            raise ValueError(f"Unknown target: {target}")

        if proc.returncode != 0:
            raise RuntimeError(
                f"Target {target} exited with rc={proc.returncode}:\n"
                f"STDOUT:\n{proc.stdout[-1200:]}\nSTDERR:\n{proc.stderr[-1200:]}"
            )

        results = {}
        for line in proc.stdout.splitlines():
            line = line.strip()
            if line.startswith("RES|"):
                parts = line.split("|")
                results[parts[1]] = parts[2:]
        return results
    finally:
        if os.path.exists(local_path):
            os.remove(local_path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Stage 3 Register-Pressure & Immediate-Boundary Differential Fuzzer")
    parser.add_argument("--seed", type=int, default=20261114)
    parser.add_argument("--count", type=int, default=560)
    parser.add_argument("--batch-size", type=int, default=280)
    parser.add_argument("--include-safety0", action="store_true", help="Also run P3 (speed 3) (safety 0) policy")
    parser.add_argument(
        "--targets",
        default="sbcl-arm64,sbcl-x86-64,ccl-arm64,ccl-x86-64",
        help="Comma-separated targets",
    )
    args = parser.parse_args()

    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    active_policies = POLICIES if args.include_safety0 else POLICIES[:3]
    cases = generate_cases(args.seed, args.count)

    print(f"[Stage 3] Generated {len(cases)} cases x {len(active_policies)} policies "
          f"= {len(cases) * len(active_policies)} compiled functions per target across {targets}")

    all_res = {t: {} for t in targets}
    for bstart in range(0, len(cases), args.batch_size):
        batch = cases[bstart:bstart + args.batch_size]
        lisp_src = build_lisp_batch(batch, active_policies)
        print(f"[Stage 3] Running batch {bstart}..{bstart + len(batch) - 1}...")
        for t in targets:
            res = run_target(t, lisp_src)
            all_res[t].update(res)
            print(f"  - {t}: collected {len(res)}/{len(batch)} results")

    anomalies = []
    for c in cases:
        cid = c.cid
        per_t = {}
        for t in targets:
            vals = all_res[t].get(cid)
            if not vals or len(vals) != len(active_policies):
                anomalies.append((cid, f"Missing output on {t}: {vals}", c))
                continue
            for (pname, _), v in zip(active_policies, vals):
                if "COMP-ERR" in v or "RT-ERR" in v:
                    anomalies.append((cid, f"ICE/Error on {t}/{pname}: {v}", c))
            if len(set(vals)) > 1:
                anomalies.append((cid, f"Intra-target policy divergence on {t}: {dict(zip([p[0] for p in active_policies], vals))}", c))
            per_t[t] = vals[0]
        if len(set(per_t.values())) > 1:
            anomalies.append((cid, f"Cross-target divergence: {per_t}", c))

    total_fns = len(cases) * len(active_policies) * len(targets)
    print(f"\n[Stage 3 Summary] seed={args.seed} cases={len(cases)} "
          f"compiled_functions={total_fns} anomalies={len(anomalies)}")
    for cid, msg, c in anomalies[:40]:
        print(f"  [ANOMALY] {cid} ({c.description}): {msg}")
        print(f"    body={c.body}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
