#!/usr/bin/env python3
"""
Stage 2 Differential Fuzzer: Expression Continuation Contexts
(Value vs Predicate vs For-Effect) across Optimization Policies & Host Targets.

Targets:
  - sbcl-arm64  (/opt/homebrew/bin/sbcl)
  - sbcl-x86-64 (ssh hbox .../run-sbcl.sh)
  - ccl-arm64   (/Users/ember/dev/ccl/darm64cl)
  - ccl-x86-64  (ssh hbox .../lx86cl64)

Wraps generated typed, inferred (if/let/the), and untyped zero-UB ANSI CL
expressions in four continuation contexts per policy:
  1. Value context:          (op ...)
  2. Predicate context:      (if (op ...) :t :f), (if (not (op ...)) :f :t),
                             boolean (t/nil), flag-shift (0/8), flag-add (-1/1)
  3. Pure for-effect:        (progn (op ...) :ok)
  4. Side-effecting effect:  ordered trace hash (setq eff (+ (* eff 13) k))

Policies tested per case:
  - P0: (optimize (speed 1) (safety 3) (debug 1) (space 1))
  - P1: (optimize (speed 3) (safety 3) (debug 0) (space 0))
  - P2: (optimize (speed 1) (safety 1) (debug 1) (space 1))
  - P3: (optimize (speed 1) (safety 1)) + (notinline <op>)
"""

import argparse
import os
import random
import shlex
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from typing import List, Optional, Tuple


LOCAL_TIMEOUT = "/opt/homebrew/bin/timeout"
SBCL_ARM64 = "/opt/homebrew/bin/sbcl"
CCL_ARM64 = "/Users/ember/dev/ccl/darm64cl"
SBCL_X86_64 = "/home/hbox/ca-sbcl-root/dl-2.6.10/sbcl-2.6.10-x86-64-linux/run-sbcl.sh"
CCL_X86_64 = "/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64"


@dataclass
class ContextCase:
    cid: str
    family: str
    params: List[Tuple[str, str, str]]  # (var_name, cl_type_or_mode, arg_init_expr)
    let_bindings: List[Tuple[str, str]]  # inferred local bindings
    op_symbol: Optional[str]  # for (declare (notinline ...)) in P3 when applicable
    val_expr: str
    pred_expr: str  # boolean-producing expression (can be same as val_expr)
    eff_pure_expr: str
    eff_trace_expr: str
    expected_eff_trace: Optional[int]
    description: str


LISP_HARNESS_HEADER = r"""
(defpackage #:ctx-fuzz (:use #:cl))
(in-package #:ctx-fuzz)

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
     (format nil "BV:~D:~{~D~}" (length x) (coerce x 'list)))
    ((stringp x)
     (format nil "STR:~D:~{~D,~}" (length x) (map 'list #'char-code x)))
    ((consp x)
     (format nil "(~A . ~A)" (canon (car x)) (canon (cdr x))))
    ((arrayp x)
     (format nil "ARR:~S:~{~A;~}"
             (array-dimensions x)
             (loop for i below (array-total-size x)
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
            (declare (ignore e))
            "RT-ERR")))
    (error (e)
      (format nil "COMP-ERR:~A" (substitute #\Space #\Newline (princ-to-string e))))))
"""


INT_BOUNDARIES = [
    "0", "1", "-1", "2", "-2", "3", "-3", "7", "-8",
    "31", "32", "-32", "62", "63", "-63", "64", "-64",
    "127", "-128", "255", "256", "-256",
    "#x0fff", "#x1000", "(- #x1000)", "#xffff", "#x10000", "(- #x10000)",
    "#x7ffff", "#x80000", "#x0fffffff", "#x10000000",
    "#x7fffffff", "(- #x80000000)", "#xffffffff", "#x100000000",
    "(1- (ash 1 59))", "(ash 1 59)", "(- (ash 1 59))",
    "(1- (ash 1 60))", "(- (ash 1 60))",
    "(1- (ash 1 62))", "(- (ash 1 62))",
    "(1- (ash 1 63))", "(- (ash 1 63))", "(ash 1 63)", "(1- (ash 1 64))",
]

UNSIGNED_64_VALS = [
    "0", "1", "2", "31", "32", "63", "64", "127", "255", "256",
    "#x0fff", "#x1000", "#xffff", "#x10000", "#x7ffff", "#x80000",
    "#x0fffffff", "#x10000000", "#x7fffffff", "#xffffffff", "#x100000000",
    "(1- (ash 1 59))", "(ash 1 59)", "(1- (ash 1 60))",
    "(1- (ash 1 62))", "(1- (ash 1 63))", "(ash 1 63)", "(1- (ash 1 64))",
]

SIGNED_64_VALS = [
    "0", "1", "-1", "2", "-2", "31", "-32", "63", "-64", "127", "-128",
    "255", "-256", "#x0fff", "#x1000", "(- #x1000)", "#xffff", "#x10000",
    "(- #x10000)", "#x7ffff", "#x80000", "#x0fffffff", "#x10000000",
    "#x7fffffff", "(- #x80000000)", "#xffffffff", "#x100000000",
    "(1- (ash 1 59))", "(- (ash 1 59))", "(1- (ash 1 62))", "(- (ash 1 62))",
    "(1- (ash 1 63))", "(- (ash 1 63))",
]

FIXNUM_SAFE_VALS = [
    "0", "1", "-1", "2", "-2", "5", "-7", "15", "-16",
    "31", "32", "-32", "63", "-64", "255", "-256",
    "#x0fff", "#x1000", "(- #x1000)", "#xffff", "#x10000",
    "#x7fffffff", "(- #x80000000)",
    "(ash 1 40)", "(- (ash 1 40))",
    "(1- (ash 1 59))", "(- (ash 1 59))",
]

SMALL_SHIFTS = [-65, -64, -63, -62, -32, -31, -16, -7, -1, 0, 1, 2, 7, 15, 16, 31, 32, 48, 59, 60, 61, 62, 63, 64]

EXACT_SFLOATS = ["0.0f0", "1.0f0", "-1.0f0", "0.5f0", "-0.25f0", "1.5f0", "-3.5f0", "4.0f0", "8.0f0", "-16.0f0", "1024.0f0"]
EXACT_DFLOATS = ["0.0d0", "1.0d0", "-1.0d0", "0.5d0", "-0.25d0", "1.5d0", "-3.5d0", "4.0d0", "8.0d0", "-16.0d0", "1048576.0d0"]


def trace_hash(n_args: int) -> int:
    eff = 1
    for k in range(1, n_args + 1):
        eff = eff * 13 + k
    return eff


def wrap_trace_args(args: List[str]) -> Tuple[List[str], int]:
    wrapped = []
    for i, a in enumerate(args, 1):
        wrapped.append(f"(progn (setq eff (+ (* eff 13) {i})) {a})")
    return wrapped, trace_hash(len(args))


def make_typing_variant(rng: random.Random, base_vars: List[Tuple[str, str, str, Optional[Tuple[str, str]]]]) -> Tuple[List[Tuple[str, str, str]], List[Tuple[str, str]], str]:
    """
    Choose typing mode:
      - 'typed': explicit (declare (type T v))
      - 'inferred': untyped parameter narrowed via (let ((v (if p c1 (the T v_in)))) ...) or mask
      - 'untyped': no type declarations
    base_vars entries: (name, cl_type, init_expr, optional_alt_const_pair)
    """
    mode = rng.choice(["typed", "inferred", "untyped"])
    params = []
    lets = []
    if mode == "typed":
        for name, ctype, init_expr, _ in base_vars:
            params.append((name, ctype, init_expr))
    elif mode == "untyped":
        for name, _, init_expr, _ in base_vars:
            params.append((name, "t", init_expr))
    else:
        params.append(("pflag", "boolean", rng.choice(["t", "nil"])))
        for name, ctype, init_expr, alt_pair in base_vars:
            raw = f"{name}_raw"
            params.append((raw, "t", init_expr))
            if alt_pair is not None and rng.random() < 0.5:
                c_true, c_false = alt_pair
                # pflag=t selects c_true or raw while teaching type inference a union/interval
                lets.append((name, f"(if pflag (the {ctype} {raw}) {c_false})"))
            else:
                lets.append((name, f"(the {ctype} {raw})"))
    return params, lets, mode


def generate_cases(seed: int, count: int) -> List[ContextCase]:
    rng = random.Random(seed)
    cases: List[ContextCase] = []

    families = [
        "int_binop",
        "int_cmp",
        "bitwise_boole",
        "shift_ash_logbitp",
        "byte_ldb_dpb",
        "div_trunc_floor",
        "pred_typep_eql",
        "float_arith_cmp",
        "complex_ops",
        "char_cmp",
        "array_sbit_aref",
        "seq_find_pos_every",
        "control_mv_nlx",
    ]

    for idx in range(count):
        fam = families[idx % len(families)]
        cid = f"C{idx:04d}_{fam}"

        if fam == "int_binop":
            op = rng.choice(["+", "-", "*", "min", "max", "gcd", "lcm"])
            use_const_rhs = rng.random() < 0.55
            ty_choice = rng.choice([
                ("fixnum", FIXNUM_SAFE_VALS, ("0", "1")),
                ("(integer -1000000 1000000)", ["-1000000", "-257", "-1", "0", "1", "255", "4095", "4096", "65536", "999999"], ("0", "42")),
                ("(unsigned-byte 32)", ["0", "1", "255", "#x0fff", "#x1000", "#xffff", "#x10000", "#x7fffffff", "#xffffffff"], ("0", "7")),
                ("(signed-byte 64)", ["-9223372036854775808", "-4294967296", "-4096", "-1", "0", "1", "4095", "4096", "#x100000000", "4611686018427387903", "9223372036854775807"], ("0", "-1")),
                ("(unsigned-byte 64)", ["0", "1", "#x0fff", "#x1000", "#xffff", "#x10000", "#xffffffff", "#x100000000", "(ash 1 62)", "(ash 1 63)", "(1- (ash 1 64))"], ("0", "1")),
            ])
            ctype, pool, alt = ty_choice
            if op in ("*", "lcm") and ctype in ("fixnum", "(signed-byte 64)", "(unsigned-byte 64)"):
                # Keep inputs in range if result doesn't need to fit, CL promotes to bignum cleanly!
                pass
            v1 = rng.choice(pool)
            v2 = rng.choice(pool)
            if use_const_rhs:
                params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt)])
                args = ["x", v2]
            else:
                params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt), ("y", ctype, v2, alt)])
                args = ["x", "y"]
            t_args, exp_tr = wrap_trace_args(args)
            expr = f"({op} {' '.join(args)})"
            texpr = f"({op} {' '.join(t_args)})"
            cases.append(ContextCase(cid, fam, params, lets, op, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))

        elif fam == "int_cmp":
            op = rng.choice(["=", "/=", "<", "<=", ">", ">=", "eql"])
            arity = rng.choice([2, 2, 3]) if op != "eql" else 2
            ctype, pool, alt = rng.choice([
                ("fixnum", FIXNUM_SAFE_VALS, ("0", "1")),
                ("(signed-byte 64)", SIGNED_64_VALS, ("0", "-1")),
                ("(unsigned-byte 64)", UNSIGNED_64_VALS, ("0", "1")),
                ("integer", INT_BOUNDARIES, ("0", "1")),
            ])
            v1 = rng.choice(pool)
            v2 = rng.choice(pool)
            if arity == 2:
                if rng.random() < 0.6:
                    params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt)])
                    args = ["x", v2] if rng.random() < 0.7 else [v2, "x"]
                else:
                    params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt), ("y", ctype, v2, alt)])
                    args = ["x", "y"]
            else:
                v3 = rng.choice(pool)
                params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt), ("y", ctype, v2, alt)])
                args = ["x", "y", v3]
            t_args, exp_tr = wrap_trace_args(args)
            expr = f"({op} {' '.join(args)})"
            texpr = f"({op} {' '.join(t_args)})"
            cases.append(ContextCase(cid, fam, params, lets, op, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))

        elif fam == "bitwise_boole":
            op = rng.choice([
                "logand", "logior", "logxor", "logeqv", "lognand", "lognor",
                "logandc1", "logandc2", "logorc1", "logorc2", "logtest",
                "lognot", "logcount", "integer-length", "boole",
            ])
            ctype, pool, alt = rng.choice([
                ("fixnum", FIXNUM_SAFE_VALS, ("0", "-1")),
                ("(unsigned-byte 32)", ["0", "1", "#xff", "#x0fff", "#x1000", "#xffff", "#x80000000", "#xffffffff"], ("0", "1")),
                ("(signed-byte 64)", SIGNED_64_VALS, ("0", "-1")),
                ("(unsigned-byte 64)", UNSIGNED_64_VALS, ("0", "1")),
            ])
            v1 = rng.choice(pool)
            if op in ("lognot", "logcount", "integer-length"):
                params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt)])
                args = ["x"]
                t_args, exp_tr = wrap_trace_args(args)
                expr = f"({op} {args[0]})"
                texpr = f"({op} {t_args[0]})"
            elif op == "boole":
                boole_const = rng.choice([
                    "boole-clr", "boole-set", "boole-1", "boole-2",
                    "boole-c1", "boole-c2", "boole-and", "boole-ior",
                    "boole-xor", "boole-eqv", "boole-nand", "boole-nor",
                    "boole-andc1", "boole-andc2", "boole-orc1", "boole-orc2",
                ])
                v2 = rng.choice(pool)
                params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt), ("y", ctype, v2, alt)])
                args = [boole_const, "x", "y"]
                t_args, exp_tr = wrap_trace_args(args)
                expr = f"(boole {' '.join(args)})"
                texpr = f"(boole {' '.join(t_args)})"
            else:
                v2 = rng.choice(pool)
                if rng.random() < 0.55:
                    params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt)])
                    args = ["x", v2]
                else:
                    params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt), ("y", ctype, v2, alt)])
                    args = ["x", "y"]
                t_args, exp_tr = wrap_trace_args(args)
                expr = f"({op} {' '.join(args)})"
                texpr = f"({op} {' '.join(t_args)})"
            cases.append(ContextCase(cid, fam, params, lets, op, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))

        elif fam == "shift_ash_logbitp":
            op = rng.choice(["ash", "logbitp"])
            ctype, pool, alt = rng.choice([
                ("fixnum", FIXNUM_SAFE_VALS, ("0", "1")),
                ("(signed-byte 64)", SIGNED_64_VALS, ("0", "1")),
                ("(unsigned-byte 64)", UNSIGNED_64_VALS, ("0", "1")),
                ("(integer -256 256)", ["-256", "-129", "-1", "0", "1", "127", "256"], ("0", "1")),
            ])
            v1 = rng.choice(pool)
            if op == "ash":
                sh = rng.choice(SMALL_SHIFTS)
                if rng.random() < 0.5:
                    params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt)])
                    args = ["x", str(sh)]
                else:
                    sh_ty = rng.choice(["(integer -64 64)", "(integer -63 0)", "(integer 0 63)", "fixnum"])
                    if sh_ty == "(integer -64 64)":
                        sh_val = max(-64, min(64, sh))
                    elif sh_ty == "(integer -63 0)":
                        sh_val = -min(63, abs(sh))
                    elif sh_ty == "(integer 0 63)":
                        sh_val = min(63, abs(sh))
                    else:
                        sh_val = sh
                    params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt), ("s", sh_ty, str(sh_val), ("0", "1"))])
                    args = ["x", "s"]
                wrap_mod = rng.choice(["none", "mod64", "mod60"])
                t_args, exp_tr = wrap_trace_args(args)
                core = f"(ash {' '.join(args)})"
                tcore = f"(ash {' '.join(t_args)})"
                if wrap_mod == "mod64":
                    expr = f"(ldb (byte 64 0) {core})"
                    texpr = f"(ldb (byte 64 0) {tcore})"
                elif wrap_mod == "mod60":
                    expr = f"(ldb (byte 60 0) {core})"
                    texpr = f"(ldb (byte 60 0) {tcore})"
                else:
                    expr = core
                    texpr = tcore
            else:
                bit_idx = rng.choice([0, 1, 2, 7, 15, 31, 32, 59, 60, 61, 62, 63, 64, 65, 100])
                if rng.random() < 0.55:
                    params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt)])
                    args = [str(bit_idx), "x"]
                else:
                    params, lets, mode = make_typing_variant(rng, [("k", "(integer 0 128)", str(bit_idx), ("0", "1")), ("x", ctype, v1, alt)])
                    args = ["k", "x"]
                t_args, exp_tr = wrap_trace_args(args)
                expr = f"(logbitp {' '.join(args)})"
                texpr = f"(logbitp {' '.join(t_args)})"
            cases.append(ContextCase(cid, fam, params, lets, op, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))

        elif fam == "byte_ldb_dpb":
            op = rng.choice(["ldb", "ldb-test", "dpb", "mask-field", "deposit-field"])
            sz = rng.choice([0, 1, 2, 7, 8, 15, 16, 31, 32, 60, 61, 62, 63, 64, 65])
            pos = rng.choice([0, 1, 2, 7, 8, 15, 16, 31, 32, 59, 60, 61, 62, 63, 64])
            ctype, pool, alt = rng.choice([
                ("fixnum", FIXNUM_SAFE_VALS, ("0", "-1")),
                ("(signed-byte 64)", SIGNED_64_VALS, ("0", "-1")),
                ("(unsigned-byte 64)", UNSIGNED_64_VALS, ("0", "1")),
            ])
            v_int = rng.choice(pool)
            const_byte = rng.random() < 0.7
            if op in ("ldb", "ldb-test", "mask-field"):
                if const_byte:
                    params, lets, mode = make_typing_variant(rng, [("x", ctype, v_int, alt)])
                    expr = f"({op} (byte {sz} {pos}) x)"
                    t_args, exp_tr = wrap_trace_args([str(sz), str(pos), "x"])
                    texpr = f"({op} (byte {t_args[0]} {t_args[1]}) {t_args[2]})"
                else:
                    params, lets, mode = make_typing_variant(rng, [
                        ("s", "(integer 0 65)", str(sz), ("1", "8")),
                        ("p", "(integer 0 64)", str(pos), ("0", "4")),
                        ("x", ctype, v_int, alt),
                    ])
                    expr = f"({op} (byte s p) x)"
                    t_args, exp_tr = wrap_trace_args(["s", "p", "x"])
                    texpr = f"({op} (byte {t_args[0]} {t_args[1]}) {t_args[2]})"
            else:
                v_new = rng.choice(pool)
                if const_byte:
                    params, lets, mode = make_typing_variant(rng, [("nv", ctype, v_new, alt), ("x", ctype, v_int, alt)])
                    expr = f"({op} nv (byte {sz} {pos}) x)"
                    t_args, exp_tr = wrap_trace_args(["nv", str(sz), str(pos), "x"])
                    texpr = f"({op} {t_args[0]} (byte {t_args[1]} {t_args[2]}) {t_args[3]})"
                else:
                    params, lets, mode = make_typing_variant(rng, [
                        ("nv", ctype, v_new, alt),
                        ("s", "(integer 0 65)", str(sz), ("1", "8")),
                        ("p", "(integer 0 64)", str(pos), ("0", "4")),
                        ("x", ctype, v_int, alt),
                    ])
                    expr = f"({op} nv (byte s p) x)"
                    t_args, exp_tr = wrap_trace_args(["nv", "s", "p", "x"])
                    texpr = f"({op} {t_args[0]} (byte {t_args[1]} {t_args[2]}) {t_args[3]})"
            cases.append(ContextCase(cid, fam, params, lets, op, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))

        elif fam == "div_trunc_floor":
            op = rng.choice(["truncate", "floor", "ceiling", "round", "mod", "rem"])
            ctype, pool, alt = rng.choice([
                ("fixnum", FIXNUM_SAFE_VALS, ("0", "7")),
                ("(signed-byte 64)", SIGNED_64_VALS, ("0", "5")),
                ("(unsigned-byte 64)", UNSIGNED_64_VALS, ("0", "3")),
            ])
            divisors_signed = ["-256", "-129", "-17", "-8", "-3", "-2", "-1", "1", "2", "3", "5", "8", "17", "129", "255", "256", "65536"]
            divisors_unsigned = ["1", "2", "3", "5", "7", "8", "16", "17", "129", "255", "256", "65536"]
            divs = divisors_unsigned if "unsigned" in ctype else divisors_signed
            v1 = rng.choice(pool)
            v2 = rng.choice(divs)
            if rng.random() < 0.6:
                params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt)])
                args = ["x", v2]
            else:
                d_ty = "(integer 1 65536)" if "unsigned" in ctype else "(or (integer -65536 -1) (integer 1 65536))"
                params, lets, mode = make_typing_variant(rng, [("x", ctype, v1, alt), ("d", d_ty, v2, ("1", "3"))])
                args = ["x", "d"]
            t_args, exp_tr = wrap_trace_args(args)
            expr = f"({op} {' '.join(args)})"
            texpr = f"({op} {' '.join(t_args)})"
            cases.append(ContextCase(cid, fam, params, lets, op, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))

        elif fam == "pred_typep_eql":
            subkind = rng.choice(["typep", "unary_pred", "equal_family"])
            if subkind == "typep":
                target_type = rng.choice([
                    "fixnum", "bignum", "integer", "rational", "real", "number",
                    "single-float", "double-float", "float", "complex",
                    "(signed-byte 8)", "(unsigned-byte 8)", "(signed-byte 16)", "(unsigned-byte 16)",
                    "(signed-byte 32)", "(unsigned-byte 32)", "(signed-byte 64)", "(unsigned-byte 64)",
                    "(integer -10 20)", "(integer 0 4095)", "(float -4.0 8.0)",
                    "null", "cons", "list", "symbol", "keyword", "character", "base-char",
                    "simple-vector", "simple-bit-vector", "string", "vector", "array",
                    "(or fixnum cons)", "(and integer (not fixnum))",
                ])
                sample_vals = [
                    "0", "-1", "15", "255", "-128", "65536", "(1- (ash 1 58))",
                    "(ash 1 63)", "(- (ash 1 64))", "1.5f0", "-2.5d0", "#c(1 2)", "#c(1.0f0 2.0f0)",
                    "nil", "t", ":kw", "'sym", "#\\A", "(list 1 2)", "(vector 1 2)", "#*1011",
                    "(make-string 3 :initial-element #\\x)",
                ]
                val = rng.choice(sample_vals)
                params = [("x", "t", val)]
                expr = f"(typep x '{target_type})"
                t_args, exp_tr = wrap_trace_args(["x"])
                texpr = f"(typep {t_args[0]} '{target_type})"
                cases.append(ContextCase(cid, fam, params, [], "typep", expr, expr, expr, texpr, exp_tr, expr))
            elif subkind == "unary_pred":
                op = rng.choice(["zerop", "plusp", "minusp", "oddp", "evenp"])
                pool = ["-9223372036854775808", "(- (ash 1 59))", "-3", "-2", "-1", "0", "1", "2", "3", "(1- (ash 1 59))", "9223372036854775807"]
                if op in ("zerop", "plusp", "minusp") and rng.random() < 0.35:
                    ctype = rng.choice(["single-float", "double-float"])
                    val = rng.choice(EXACT_SFLOATS if ctype == "single-float" else EXACT_DFLOATS)
                    alt = ("0.0f0", "1.0f0") if ctype == "single-float" else ("0.0d0", "1.0d0")
                else:
                    ctype = rng.choice(["fixnum", "(signed-byte 64)", "integer"])
                    val = rng.choice(FIXNUM_SAFE_VALS if ctype == "fixnum" else pool)
                    alt = ("0", "1")
                params, lets, mode = make_typing_variant(rng, [("x", ctype, val, alt)])
                expr = f"({op} x)"
                t_args, exp_tr = wrap_trace_args(["x"])
                texpr = f"({op} {t_args[0]})"
                cases.append(ContextCase(cid, fam, params, lets, op, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))
            else:
                op = rng.choice(["eq", "eql", "equal", "equalp"])
                if op == "eq":
                    pairs = [
                        ("0", "0"), ("-1", "-1"), ("42", "42"),
                        ("(1- (ash 1 58))", "(1- (ash 1 58))"),
                        (":foo", ":foo"), ("nil", "nil"), ("t", "t"),
                    ]
                else:
                    pairs = [
                        ("0", "0"), ("0", "0.0f0"), ("1.5d0", "1.5d0"), ("-1", "-1"),
                        ("(1- (ash 1 59))", "(1- (ash 1 59))"),
                        ("(- (ash 1 59))", "(- (ash 1 59))"),
                        ("(ash 1 63)", "(ash 1 63)"), ("(- (ash 1 63))", "(- (ash 1 63))"),
                        ("(1- (ash 1 63))", "(1- (ash 1 63))"),
                        (":foo", ":foo"), ("nil", "nil"), ("#\\a", "#\\A"),
                        ("(list 1 2)", "(list 1 2)"), ("#*1010", "#*1010"),
                    ]
                v1, v2 = rng.choice(pairs)
                if rng.random() < 0.4:
                    v2 = rng.choice([p[0] for p in pairs])
                if rng.random() < 0.5 and op in ("eq", "eql"):
                    params = [("x", "t", v1)]
                    args = ["x", v2]
                else:
                    params = [("x", "t", v1), ("y", "t", v2)]
                    args = ["x", "y"]
                t_args, exp_tr = wrap_trace_args(args)
                expr = f"({op} {' '.join(args)})"
                texpr = f"({op} {' '.join(t_args)})"
                cases.append(ContextCase(cid, fam, params, [], op, expr, expr, expr, texpr, exp_tr, expr))

        elif fam == "float_arith_cmp":
            # Exclude unary float negate in for-effect (HC-W3-7) & (/ (* c1 x) c2) (CCL-CG-3) & NaN (HC-W3-9)
            ftype = rng.choice(["single-float", "double-float"])
            pool = EXACT_SFLOATS if ftype == "single-float" else EXACT_DFLOATS
            nonzero_pool = [v for v in pool if not v.startswith("0.0")]
            op = rng.choice(["+", "-", "*", "/", "=", "/=", "<", "<=", ">", ">=", "min", "max", "float"])
            v1 = rng.choice(pool)
            v2 = rng.choice(nonzero_pool if op == "/" else pool)
            alt = ("1.0f0", "2.0f0") if ftype == "single-float" else ("1.0d0", "2.0d0")
            if op == "float":
                src_ty = rng.choice(["fixnum", "(signed-byte 32)", "single-float", "double-float"])
                if src_ty in ("fixnum", "(signed-byte 32)"):
                    sv = rng.choice(["-1024", "-1", "0", "1", "42", "1024"])
                    salt = ("0", "1")
                elif src_ty == "single-float":
                    sv = rng.choice(EXACT_SFLOATS)
                    salt = ("0.0f0", "1.0f0")
                else:
                    sv = rng.choice(EXACT_DFLOATS)
                    salt = ("0.0d0", "1.0d0")
                proto = "0.0f0" if ftype == "single-float" else "0.0d0"
                params, lets, mode = make_typing_variant(rng, [("x", src_ty, sv, salt)])
                args = ["x", proto]
            else:
                if rng.random() < 0.5:
                    params, lets, mode = make_typing_variant(rng, [("x", ftype, v1, alt)])
                    args = ["x", v2]
                else:
                    params, lets, mode = make_typing_variant(rng, [("x", ftype, v1, alt), ("y", ftype, v2, alt)])
                    args = ["x", "y"]
            t_args, exp_tr = wrap_trace_args(args)
            expr = f"({op} {' '.join(args)})"
            texpr = f"({op} {' '.join(t_args)})"
            cases.append(ContextCase(cid, fam, params, lets, op, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))

        elif fam == "complex_ops":
            # Exclude complex float +,-,*,negate in for-effect (HC-W3-6, HC-W3-7); test complex creation, realpart, imagpart, =, /=, rational complex arithmetic!
            sub = rng.choice(["realpart", "imagpart", "complex_make", "complex_eq", "rational_complex_arith"])
            if sub in ("realpart", "imagpart"):
                cty = rng.choice(["(complex single-float)", "(complex double-float)", "(complex rational)"])
                if cty == "(complex single-float)":
                    cv = f"#c({rng.choice(EXACT_SFLOATS)} {rng.choice(EXACT_SFLOATS)})"
                    alt = ("#c(1.0f0 2.0f0)", "#c(-1.0f0 0.5f0)")
                elif cty == "(complex double-float)":
                    cv = f"#c({rng.choice(EXACT_DFLOATS)} {rng.choice(EXACT_DFLOATS)})"
                    alt = ("#c(1.0d0 2.0d0)", "#c(-1.0d0 0.5d0)")
                else:
                    cv = "#c(3 -5)"
                    alt = ("#c(1 2)", "#c(3 -5)")
                params, lets, mode = make_typing_variant(rng, [("z", cty, cv, alt)])
                expr = f"({sub} z)"
                t_args, exp_tr = wrap_trace_args(["z"])
                texpr = f"({sub} {t_args[0]})"
                cases.append(ContextCase(cid, fam, params, lets, sub, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))
            elif sub == "complex_make":
                fty = rng.choice(["single-float", "double-float", "fixnum"])
                pool = EXACT_SFLOATS if ftype_is_sf(fty) else (EXACT_DFLOATS if fty == "double-float" else ["-5", "0", "1", "7"])
                alt = ("1.0f0", "2.0f0") if fty == "single-float" else (("1.0d0", "2.0d0") if fty == "double-float" else ("1", "2"))
                v1, v2 = rng.choice(pool), rng.choice(pool)
                params, lets, mode = make_typing_variant(rng, [("r", fty, v1, alt), ("im", fty, v2, alt)])
                expr = "(complex r im)"
                t_args, exp_tr = wrap_trace_args(["r", "im"])
                texpr = f"(complex {t_args[0]} {t_args[1]})"
                cases.append(ContextCase(cid, fam, params, lets, "complex", expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))
            elif sub == "complex_eq":
                op = rng.choice(["=", "/=", "eql"])
                cty = rng.choice(["(complex single-float)", "(complex double-float)"])
                pool = EXACT_SFLOATS if "single" in cty else EXACT_DFLOATS
                c1 = f"#c({rng.choice(pool)} {rng.choice(pool)})"
                c2 = c1 if rng.random() < 0.5 else f"#c({rng.choice(pool)} {rng.choice(pool)})"
                alt = (c1, c2)
                params, lets, mode = make_typing_variant(rng, [("z1", cty, c1, alt), ("z2", cty, c2, alt)])
                expr = f"({op} z1 z2)"
                t_args, exp_tr = wrap_trace_args(["z1", "z2"])
                texpr = f"({op} {t_args[0]} {t_args[1]})"
                cases.append(ContextCase(cid, fam, params, lets, op, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))
            else:
                op = rng.choice(["+", "-", "*", "="])
                c1 = f"(complex {rng.randint(-10, 10)} {rng.randint(1, 10)})"
                c2 = f"(complex {rng.randint(-10, 10)} {rng.randint(1, 10)})"
                params = [("z1", "number", c1), ("z2", "number", c2)]
                expr = f"({op} z1 z2)"
                t_args, exp_tr = wrap_trace_args(["z1", "z2"])
                texpr = f"({op} {t_args[0]} {t_args[1]})"
                cases.append(ContextCase(cid, fam, params, [], op, expr, expr, expr, texpr, exp_tr, expr))

        elif fam == "char_cmp":
            # ASCII/Latin-1 chars (avoid Unicode titlecase HC-W3-3 & char-code constraint-back HC-W3-2)
            op = rng.choice(["char=", "char/=", "char<", "char<=", "char>", "char>=", "char-equal", "char-not-equal"])
            chars = ["#\\a", "#\\A", "#\\b", "#\\z", "#\\Z", "#\\0", "#\\9", "#\\Space", "#\\~"]
            arity = rng.choice([1, 2, 2, 3])
            selected = [rng.choice(chars) for _ in range(arity)]
            pvars = [(f"c{i}", "character", ch, ("#\\a", "#\\b")) for i, ch in enumerate(selected)]
            params, lets, mode = make_typing_variant(rng, pvars)
            args = [f"c{i}" for i in range(arity)]
            t_args, exp_tr = wrap_trace_args(args)
            expr = f"({op} {' '.join(args)})"
            texpr = f"({op} {' '.join(t_args)})"
            cases.append(ContextCase(cid, fam, params, lets, op, expr, expr, expr, texpr, exp_tr, f"{mode} {expr}"))

        elif fam == "array_sbit_aref":
            # 1D specialized array reads across small & large sizes (note: keep index <= 1024 here so we also test normal constant/var paths; Stage 3 hammers > 32792 & 2 GiB!)
            el_spec = rng.choice([
                ("bit", "(simple-bit-vector 128)", "(let ((a (make-array 128 :element-type 'bit :initial-element 0))) (setf (aref a 0) 1 (aref a 31) 1 (aref a 32) 1 (aref a 63) 1 (aref a 64) 1 (aref a 127) 1) a)", [0, 1, 31, 32, 63, 64, 127], "sbit"),
                ("(unsigned-byte 8)", "(simple-array (unsigned-byte 8) (64))", "(let ((a (make-array 64 :element-type '(unsigned-byte 8) :initial-element 7))) (setf (aref a 0) 255 (aref a 63) 128) a)", [0, 1, 31, 63], "aref"),
                ("(signed-byte 8)", "(simple-array (signed-byte 8) (64))", "(let ((a (make-array 64 :element-type '(signed-byte 8) :initial-element -5))) (setf (aref a 0) -128 (aref a 63) 127) a)", [0, 1, 31, 63], "aref"),
                ("(unsigned-byte 16)", "(simple-array (unsigned-byte 16) (64))", "(let ((a (make-array 64 :element-type '(unsigned-byte 16) :initial-element 513))) (setf (aref a 15) 65535) a)", [0, 15, 16, 63], "aref"),
                ("(signed-byte 32)", "(simple-array (signed-byte 32) (64))", "(let ((a (make-array 64 :element-type '(signed-byte 32) :initial-element -100000))) (setf (aref a 32) 2147483647) a)", [0, 31, 32, 63], "aref"),
                ("(unsigned-byte 64)", "(simple-array (unsigned-byte 64) (64))", "(let ((a (make-array 64 :element-type '(unsigned-byte 64) :initial-element 9))) (setf (aref a 8) #x8000000000000001) a)", [0, 8, 63], "aref"),
                ("double-float", "(simple-array double-float (32))", "(let ((a (make-array 32 :element-type 'double-float :initial-element 1.5d0))) (setf (aref a 7) -4.25d0) a)", [0, 7, 31], "aref"),
                ("t", "(simple-vector 16)", "(vector :a nil 0 -1 42 'x #\\Z 3.5d0 8 9 10 11 12 13 14 :end)", [0, 1, 2, 4, 7, 15], "svref"),
            ])
            _, arr_ty, arr_init, indices, acc_op = el_spec
            ix = rng.choice(indices)
            use_const_ix = rng.random() < 0.6
            if use_const_ix:
                params = [("a", arr_ty if rng.random() < 0.75 else "t", arr_init)]
                if params[0][1] == "t" and acc_op in ("sbit", "svref"):
                    acc_op = "aref"
                args = ["a", str(ix)]
            else:
                params = [
                    ("a", arr_ty if rng.random() < 0.75 else "t", arr_init),
                    ("i", "(integer 0 15)", str(min(ix, 15))),
                ]
                if params[0][1] == "t" and acc_op in ("sbit", "svref"):
                    acc_op = "aref"
                args = ["a", "i"]
            t_args, exp_tr = wrap_trace_args(args)
            expr = f"({acc_op} {' '.join(args)})"
            texpr = f"({acc_op} {' '.join(t_args)})"
            cases.append(ContextCase(cid, fam, params, [], acc_op, expr, expr, expr, texpr, exp_tr, expr))

        elif fam == "seq_find_pos_every":
            sub = rng.choice(["find", "position", "member", "assoc", "getf", "some", "every", "notany", "notevery"])
            if sub in ("find", "position"):
                is_vec = rng.random() < 0.5
                seq_ty = "(simple-vector 6)" if is_vec else "list"
                seq_init = "(vector 10 -3 0 42 7 -3)" if is_vec else "(list 10 -3 0 42 7 -3)"
                item = rng.choice(["0", "-3", "42", "99"])
                params = [("item", "fixnum", item), ("seq", seq_ty if rng.random() < 0.7 else "sequence", seq_init)]
                expr = f"({sub} item seq)"
                t_args, exp_tr = wrap_trace_args(["item", "seq"])
                texpr = f"({sub} {t_args[0]} {t_args[1]})"
                cases.append(ContextCase(cid, fam, params, [], sub, expr, expr, expr, texpr, exp_tr, expr))
            elif sub == "member":
                test_kw = rng.choice(["", " :test #'eq", " :test #'eql", " :test #'equal"])
                item = rng.choice([":b", ":z", "2", "99"])
                lst = "(list :a 1 :b 2 :c 3)"
                params = [("item", "t", item), ("lst", "list", lst)]
                expr = f"(member item lst{test_kw})"
                t_args, exp_tr = wrap_trace_args(["item", "lst"])
                texpr = f"(member {t_args[0]} {t_args[1]}{test_kw})"
                cases.append(ContextCase(cid, fam, params, [], "member", expr, expr, expr, texpr, exp_tr, expr))
            elif sub == "assoc":
                item = rng.choice([":b", ":missing", "2"])
                alist = "(list (cons :a 10) (cons 2 20) (cons :b nil) (cons :c 30))"
                params = [("item", "t", item), ("al", "list", alist)]
                expr = "(assoc item al)"
                t_args, exp_tr = wrap_trace_args(["item", "al"])
                texpr = f"(assoc {t_args[0]} {t_args[1]})"
                cases.append(ContextCase(cid, fam, params, [], "assoc", expr, expr, expr, texpr, exp_tr, expr))
            elif sub == "getf":
                key = rng.choice([":a", ":b", ":missing"])
                plist = "(list :a 11 :b nil :c 33)"
                params = [("pl", "list", plist), ("k", "symbol", key)]
                expr = "(getf pl k :def)"
                t_args, exp_tr = wrap_trace_args(["pl", "k", ":def"])
                texpr = f"(getf {t_args[0]} {t_args[1]} {t_args[2]})"
                cases.append(ContextCase(cid, fam, params, [], "getf", expr, expr, expr, texpr, exp_tr, expr))
            else:
                pred_fn = rng.choice(["#'evenp", "#'plusp", "(lambda (z) (> z 5))"])
                is_vec = rng.random() < 0.5
                seq_ty = "(simple-vector 4)" if is_vec else "list"
                vals = [rng.randint(-4, 10) for _ in range(4)]
                seq_init = f"(vector {' '.join(map(str, vals))})" if is_vec else f"(list {' '.join(map(str, vals))})"
                params = [("seq", seq_ty if rng.random() < 0.7 else "sequence", seq_init)]
                expr = f"({sub} {pred_fn} seq)"
                t_args, exp_tr = wrap_trace_args(["seq"])
                texpr = f"({sub} {pred_fn} {t_args[0]})"
                cases.append(ContextCase(cid, fam, params, [], sub, expr, expr, expr, texpr, exp_tr, expr))

        elif fam == "control_mv_nlx":
            sub = rng.choice(["mv_prog1", "catch_throw", "block_return", "unwind_protect", "tagbody_go"])
            v1 = str(rng.choice([-7, 0, 1, 42]))
            v2 = rng.choice(["nil", "t", "99", "0"])
            params = [("x", "fixnum", v1), ("y", "t", v2)]
            if sub == "mv_prog1":
                expr = "(multiple-value-prog1 (if (> x 0) y (values nil x)) (+ x 1))"
                t_args, exp_tr = wrap_trace_args(["x", "y"])
                texpr = f"(multiple-value-prog1 (progn {t_args[0]} {t_args[1]}) (+ x 1))"
            elif sub == "catch_throw":
                expr = "(catch 'ctag (if (eql x 0) (throw 'ctag y) (+ x 5)))"
                t_args, exp_tr = wrap_trace_args(["x", "y"])
                texpr = f"(catch 'ctag (progn {t_args[0]} (throw 'ctag {t_args[1]})))"
            elif sub == "block_return":
                expr = "(block blk (when (< x 0) (return-from blk y)) (eql x 42))"
                t_args, exp_tr = wrap_trace_args(["x", "y"])
                texpr = f"(block blk (return-from blk (progn {t_args[0]} {t_args[1]})))"
            elif sub == "unwind_protect":
                expr = "(let ((u 0)) (unwind-protect (if y (+ x 10) nil) (incf u)))"
                t_args, exp_tr = wrap_trace_args(["x", "y"])
                texpr = f"(unwind-protect (progn {t_args[0]} nil) {t_args[1]})"
            else:
                expr = "(let ((acc x)) (tagbody (when (> acc 0) (go done)) (setq acc 0) done) (if (= acc 0) nil acc))"
                t_args, exp_tr = wrap_trace_args(["x", "y"])
                texpr = f"(let ((acc 0)) (tagbody (setq acc {t_args[0]}) (go end) (setq acc -1) end (progn {t_args[1]})) acc)"
            cases.append(ContextCase(cid, fam, params, [], None, expr, expr, expr, texpr, exp_tr, sub))

    return cases


def ftype_is_sf(fty: str) -> bool:
    return fty == "single-float"


POLICIES = [
    ("P0_s1_saf3", "((speed 1) (safety 3) (debug 1) (space 1))", False),
    ("P1_s3_saf3", "((speed 3) (safety 3) (debug 0) (space 0))", False),
    ("P2_s1_saf1", "((speed 1) (safety 1) (debug 1) (space 1))", False),
    ("P3_notinline", "((speed 1) (safety 1) (debug 1) (space 1))", True),
]


def build_case_lambda(case: ContextCase, opt_qualities: str, use_notinline: bool) -> str:
    param_names = [p[0] for p in case.params]
    type_decls = [f"(type {p[1]} {p[0]})" for p in case.params if p[1] != "t"]
    notinline_decl = ""
    if use_notinline and case.op_symbol and case.op_symbol not in ("the", "if", "block", "catch", "tagbody", "unwind-protect", "multiple-value-prog1"):
        notinline_decl = f"(notinline {case.op_symbol})"
    decl_parts = [f"(optimize {opt_qualities})"] + type_decls + ([notinline_decl] if notinline_decl else [])
    decl_str = f"(declare {' '.join(decl_parts)})"

    def wrap_lets(inner: str) -> str:
        if not case.let_bindings:
            return inner
        b_str = " ".join(f"({k} {v})" for k, v in case.let_bindings)
        return f"(let* ({b_str}) {inner})"

    v_body = wrap_lets(case.val_expr)
    # Predicate body exercises branch-if (direct & inverted), boolean flag, shl flag, add flag
    p_e = case.pred_expr
    p_body = wrap_lets(
        f"(list (if {p_e} :t :f) "
        f"(if (not {p_e}) :f :t) "
        f"(if {p_e} t nil) "
        f"(if (not {p_e}) 0 8) "
        f"(if {p_e} -1 1))"
    )
    e0_body = wrap_lets(f"(progn {case.eff_pure_expr} :ok)")
    e1_body = wrap_lets(f"(let ((eff 1)) (declare (type fixnum eff)) {case.eff_trace_expr} eff)")

    p_list = " ".join(param_names)
    return (
        f"'(lambda ({p_list}) {decl_str} "
        f"(flet ((v-fn () (multiple-value-list {v_body})) "
        f"       (p-fn () {p_body}) "
        f"       (e0-fn () {e0_body}) "
        f"       (e1-fn () {e1_body})) "
        f"  (declare (notinline v-fn p-fn e0-fn e1-fn)) "
        f"  (list (v-fn) (p-fn) (e0-fn) (e1-fn))))"
    )


def build_lisp_batch(cases: List[ContextCase]) -> str:
    lines = [LISP_HARNESS_HEADER]
    for c in cases:
        thunks = " ".join(f"(lambda () {p[2]})" for p in c.params)
        lines.append(f"(let ((thunks (list {thunks})))")
        pol_exprs = []
        for pname, pqual, pni in POLICIES:
            lam = build_case_lambda(c, pqual, pni)
            pol_exprs.append(f"(run-form {lam} thunks)")
        fmt_slots = "|".join(["~A"] * len(POLICIES))
        lines.append(f'  (format t "RES|{c.cid}|{fmt_slots}~%" {" ".join(pol_exprs)}))')
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
            remote_tmp = f"/tmp/w4_ctx_{os.getpid()}_{random.randint(10000, 99999)}.lisp"
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
            raise RuntimeError(f"Target {target} failed (rc={proc.returncode}):\nSTDOUT:\n{proc.stdout[-1000:]}\nSTDERR:\n{proc.stderr[-1000:]}")

        results = {}
        for line in proc.stdout.splitlines():
            line = line.strip()
            if line.startswith("RES|"):
                parts = line.split("|")
                cid = parts[1]
                results[cid] = parts[2:]
        return results
    finally:
        if os.path.exists(local_path):
            os.remove(local_path)


def check_internal_context_consistency(cid: str, target: str, pol_name: str, raw: str, expected_trace: Optional[int]) -> Optional[str]:
    """
    Verify that within ((v_vals) (b1 b2 b3 b4 b5) e0 e1):
      - No COMP-ERR or RT-ERR
      - Predicate context matches truthiness of primary value v_vals[0]
      - Pure effect returned SYM:KEYWORD:OK
      - Trace effect returned I:<expected_trace>
    """
    if "COMP-ERR" in raw or raw == "RT-ERR":
        return f"{target}/{pol_name}: {raw}"

    # Check expected truthiness patterns in canonical string:
    # raw has structure: (((<v0> . ...) . ((<b1> . (<b2> . (<b3> . (<b4> . (<b5> . NIL))))) . (SYM:KEYWORD:OK . (I:<trace> . NIL)))) . NIL)
    truthy_pred = "(SYM:KEYWORD:T . (SYM:KEYWORD:T . (T . (I:8 . (I:-1 . NIL)))))"
    falsy_pred = "(SYM:KEYWORD:F . (SYM:KEYWORD:F . (NIL . (I:0 . (I:1 . NIL)))))"

    # Extract primary value: if v_vals is NIL (0 values), primary value is NIL (falsy)
    if raw.startswith("((NIL . ("):
        is_truthy = False
    elif raw.startswith("(((NIL . "):
        is_truthy = False
    else:
        is_truthy = True

    expected_pred = truthy_pred if is_truthy else falsy_pred
    if expected_pred not in raw:
        return f"{target}/{pol_name}: predicate/value mismatch! truthy={is_truthy}, got={raw}"

    if "SYM:KEYWORD:OK" not in raw:
        return f"{target}/{pol_name}: pure for-effect missing :OK! got={raw}"

    if expected_trace is not None and f"I:{expected_trace}" not in raw:
        return f"{target}/{pol_name}: side-effect trace mismatch (expected I:{expected_trace})! got={raw}"

    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Stage 2 Context-Position Differential Fuzzer")
    parser.add_argument("--seed", type=int, default=20261113)
    parser.add_argument("--count", type=int, default=520)
    parser.add_argument("--batch-size", type=int, default=260)
    parser.add_argument(
        "--targets",
        default="sbcl-arm64,sbcl-x86-64,ccl-arm64,ccl-x86-64",
        help="Comma-separated targets",
    )
    args = parser.parse_args()

    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    cases = generate_cases(args.seed, args.count)
    case_map = {c.cid: c for c in cases}

    print(f"[Stage 2] Generated {len(cases)} multi-context cases "
          f"({len(cases) * len(POLICIES) * 4} context-policy subfunctions per target) "
          f"across {targets}")

    all_target_results = {t: {} for t in targets}
    for bstart in range(0, len(cases), args.batch_size):
        batch = cases[bstart:bstart + args.batch_size]
        lisp_src = build_lisp_batch(batch)
        print(f"[Stage 2] Running batch {bstart}..{bstart + len(batch) - 1}...")
        for t in targets:
            res = run_target(t, lisp_src)
            all_target_results[t].update(res)
            print(f"  - {t}: collected {len(res)}/{len(batch)} results")

    anomalies = []
    for c in cases:
        cid = c.cid
        # 1. Check intra-target & context self-consistency
        per_target_canonical = {}
        for t in targets:
            pol_vals = all_target_results[t].get(cid)
            if not pol_vals or len(pol_vals) != len(POLICIES):
                anomalies.append((cid, f"Missing output on {t}: {pol_vals}", c))
                continue
            for (pname, _, _), val in zip(POLICIES, pol_vals):
                err = check_internal_context_consistency(cid, t, pname, val, c.expected_eff_trace)
                if err:
                    anomalies.append((cid, f"Context/ICE failure {err}", c))
            if len(set(pol_vals)) > 1:
                anomalies.append((cid, f"Intra-target policy divergence on {t}: {dict(zip([p[0] for p in POLICIES], pol_vals))}", c))
            per_target_canonical[t] = pol_vals[0]

        # 2. Check cross-target equivalence
        if len(set(per_target_canonical.values())) > 1:
            anomalies.append((cid, f"Cross-target divergence: {per_target_canonical}", c))

    total_compiled = len(cases) * len(POLICIES) * len(targets)
    total_context_fns = total_compiled * 4
    print(f"\n[Stage 2 Summary] seed={args.seed} cases={len(cases)} "
          f"compiled_lambdas={total_compiled} context_subfns={total_context_fns} "
          f"anomalies={len(anomalies)}")

    for cid, msg, c in anomalies[:30]:
        print(f"  [ANOMALY] {cid} ({c.description}): {msg}")
        print(f"    params={c.params} lets={c.let_bindings}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
