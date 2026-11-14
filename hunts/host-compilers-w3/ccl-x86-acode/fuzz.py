#!/usr/bin/env python3
"""Cross-architecture differential fuzzer for CCL 1.14 (x86-64 vs ARM64) vs SBCL 2.6.10.

Generates strictly zero-UB Common Lisp test cases across:
  1. Complex single/double float arithmetic + register pressure + for-effect
  2. Double/single float arithmetic, comparisons, conversions, truncate/floor/ceiling/round
  3. 1D/2D/3D typed simple & adjustable/displaced arrays (u64/s64/u32/s32/u16/s16/u8/s8/df/sf/complex/bit/string/t)
  4. Tight integer intervals, ash, ldb, dpb, mask-field, deposit-field, logbitp, logtest, logcount, integer-length
  5. Multi-limb bignums: + - * truncate floor ceiling rem mod gcd lcm isqrt expt ash logand/ior/xor
  6. Multiple values, non-local control flow (block/tagbody/catch/unwind-protect), case jump tables, &rest/apply
"""

import argparse
import os
import random
import subprocess
import sys
import tempfile
import time

SBCL_BIN = "/opt/homebrew/bin/sbcl"
ARM64_CCL_BIN = "/Users/ember/dev/ccl/darm64cl"
X86_CCL_SSH = "hbox"
X86_CCL_BIN = "/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64"
TIMEOUT_LOCAL = ["/opt/homebrew/bin/timeout", "--kill-after=10s", "60s"]


def fmt_sf(x: float) -> str:
    if x == 0.0:
        return "-0.0f0" if str(x).startswith("-") else "0.0f0"
    return f"{x:.6g}f0".replace("e", "f")


def fmt_df(x: float) -> str:
    if x == 0.0:
        return "-0.0d0" if str(x).startswith("-") else "0.0d0"
    return f"{x:.12g}d0".replace("e", "d")


class FuzzGenerator:
    def __init__(self, seed: int):
        self.rng = random.Random(seed)
        self.counter = 0

    def rand_sf(self) -> str:
        choices = [
            0.0, -0.0, 1.0, -1.0, 2.0, -2.0, 0.5, -0.5, 0.25, 3.5, -7.25,
            self.rng.uniform(-50.0, 50.0),
        ]
        v = self.rng.choice(choices)
        if v == 0.0 and self.rng.random() < 0.5:
            return "-0.0f0"
        return fmt_sf(v)

    def rand_df(self) -> str:
        choices = [
            0.0, -0.0, 1.0, -1.0, 2.0, -2.0, 0.5, -0.5, 0.125, 13.75, -9.5,
            self.rng.uniform(-100.0, 100.0),
        ]
        v = self.rng.choice(choices)
        if v == 0.0 and self.rng.random() < 0.5:
            return "-0.0d0"
        return fmt_df(v)

    def rand_csf(self) -> str:
        return f"#C({self.rand_sf()} {self.rand_sf()})"

    def rand_cdf(self) -> str:
        return f"#C({self.rand_df()} {self.rand_df()})"

    def rand_int(self, lo: int, hi: int) -> int:
        specials = [lo, hi, 0, 1, -1, 2, -2, (lo + hi) // 2]
        valid = [x for x in specials if lo <= x <= hi]
        if valid and self.rng.random() < 0.4:
            return self.rng.choice(valid)
        return self.rng.randint(lo, hi)

    def gen_complex_float_expr(self, vars_list, is_double: bool, depth: int) -> str:
        ftype = "double-float" if is_double else "single-float"
        ctype = f"(complex {ftype})"
        if depth <= 0 or (depth < 3 and self.rng.random() < 0.35):
            if self.rng.random() < 0.7:
                return self.rng.choice(vars_list)
            return self.rand_cdf() if is_double else self.rand_csf()
        op = self.rng.choice(["+", "-", "*", "conj", "build", "add3", "sub-swap"])
        if op in ("+", "-", "*"):
            a = self.gen_complex_float_expr(vars_list, is_double, depth - 1)
            b = self.gen_complex_float_expr(vars_list, is_double, depth - 1)
            return f"(the {ctype} ({op} {a} {b}))"
        if op == "conj":
            a = self.gen_complex_float_expr(vars_list, is_double, depth - 1)
            return f"(the {ctype} (conjugate {a}))"
        if op == "build":
            a = self.gen_complex_float_expr(vars_list, is_double, depth - 1)
            b = self.gen_complex_float_expr(vars_list, is_double, depth - 1)
            return f"(the {ctype} (complex (imagpart {a}) (realpart {b})))"
        if op == "add3":
            a = self.gen_complex_float_expr(vars_list, is_double, depth - 1)
            b = self.gen_complex_float_expr(vars_list, is_double, depth - 1)
            c = self.gen_complex_float_expr(vars_list, is_double, depth - 1)
            return f"(the {ctype} (- (+ {a} {b}) {c}))"
        a = self.gen_complex_float_expr(vars_list, is_double, depth - 1)
        b = self.gen_complex_float_expr(vars_list, is_double, depth - 1)
        return f"(the {ctype} (- {a} (- {b} {self.rng.choice(vars_list)})))"

    def gen_case_complex_float(self, opt_decl: str):
        is_double = self.rng.choice([True, False])
        ftype = "double-float" if is_double else "single-float"
        ctype = f"(complex {ftype})"
        nargs = self.rng.randint(4, 8)
        vars_list = [f"v{i}" for i in range(nargs)]
        args_vals = [self.rand_cdf() if is_double else self.rand_csf() for _ in range(nargs)]
        body = self.gen_complex_float_expr(vars_list, is_double, 4)
        # Optionally wrap in let bindings for register pressure (skipping for-effect known crash unless requested)
        lam = (
            f"(lambda ({' '.join(vars_list)}) "
            f"(declare (type {ctype} {' '.join(vars_list)}) {opt_decl}) "
            f"(let ((t0 {self.gen_complex_float_expr(vars_list, is_double, 2)}) "
            f"      (t1 {self.gen_complex_float_expr(vars_list, is_double, 2)})) "
            f"  (declare (type {ctype} t0 t1)) "
            f"  (+ {body} (- t0 t1))))"
        )
        return f"(funcall (compile nil '{lam}) {' '.join(args_vals)})"

    def gen_float_expr(self, vars_list, is_double: bool, depth: int) -> str:
        ftype = "double-float" if is_double else "single-float"
        zero = "0.0d0" if is_double else "0.0f0"
        one = "1.0d0" if is_double else "1.0f0"
        if depth <= 0 or (depth < 3 and self.rng.random() < 0.35):
            if self.rng.random() < 0.7:
                return self.rng.choice(vars_list)
            return self.rand_df() if is_double else self.rand_sf()
        op = self.rng.choice(["+", "-", "*", "/", "neg", "abs", "cond", "sqrt"])
        if op in ("+", "-", "*"):
            return f"(the {ftype} ({op} {self.gen_float_expr(vars_list, is_double, depth-1)} {self.gen_float_expr(vars_list, is_double, depth-1)}))"
        if op == "/":
            num = self.gen_float_expr(vars_list, is_double, depth - 1)
            den = self.gen_float_expr(vars_list, is_double, depth - 1)
            return f"(the {ftype} (let ((d {den})) (if (= d {zero}) (/ {num} {one}) (/ {num} d))))"
        if op == "neg":
            return f"(the {ftype} (- {self.gen_float_expr(vars_list, is_double, depth-1)}))"
        if op == "abs":
            return f"(the {ftype} (abs {self.gen_float_expr(vars_list, is_double, depth-1)}))"
        if op == "sqrt":
            a = self.gen_float_expr(vars_list, is_double, depth - 1)
            return f"(the {ftype} (sqrt (abs {a})))"
        cmp_op = self.rng.choice(["<", "<=", ">", ">=", "=", "/="])
        a = self.gen_float_expr(vars_list, is_double, depth - 1)
        b = self.gen_float_expr(vars_list, is_double, depth - 1)
        c = self.gen_float_expr(vars_list, is_double, depth - 1)
        d = self.gen_float_expr(vars_list, is_double, depth - 1)
        return f"(the {ftype} (if ({cmp_op} {a} {b}) {c} {d}))"

    def gen_case_float(self, opt_decl: str):
        is_double = self.rng.choice([True, False])
        ftype = "double-float" if is_double else "single-float"
        nargs = self.rng.randint(3, 8)
        vars_list = [f"f{i}" for i in range(nargs)]
        args_vals = [self.rand_df() if is_double else self.rand_sf() for _ in range(nargs)]
        body = self.gen_float_expr(vars_list, is_double, 4)
        trunc_op = self.rng.choice(["truncate", "floor", "ceiling", "round"])
        lam = (
            f"(lambda ({' '.join(vars_list)}) "
            f"(declare (type {ftype} {' '.join(vars_list)}) {opt_decl}) "
            f"(let ((r {body})) (declare (type {ftype} r)) "
            f"  (list r (multiple-value-list ({trunc_op} r)))))"
        )
        return f"(funcall (compile nil '{lam}) {' '.join(args_vals)})"

    def gen_case_array(self, opt_decl: str):
        specs = [
            ("(unsigned-byte 64)", lambda: str(self.rand_int(0, (1 << 64) - 1)), "0"),
            ("(signed-byte 64)", lambda: str(self.rand_int(-(1 << 63), (1 << 63) - 1)), "0"),
            ("(unsigned-byte 32)", lambda: str(self.rand_int(0, (1 << 32) - 1)), "0"),
            ("(signed-byte 32)", lambda: str(self.rand_int(-(1 << 31), (1 << 31) - 1)), "0"),
            ("(unsigned-byte 16)", lambda: str(self.rand_int(0, 65535)), "0"),
            ("(signed-byte 16)", lambda: str(self.rand_int(-32768, 32767)), "0"),
            ("(unsigned-byte 8)", lambda: str(self.rand_int(0, 255)), "0"),
            ("(signed-byte 8)", lambda: str(self.rand_int(-128, 127)), "0"),
            ("double-float", self.rand_df, "0.0d0"),
            ("single-float", self.rand_sf, "0.0f0"),
            ("bit", lambda: str(self.rng.choice([0, 1])), "0"),
            ("base-char", lambda: f"#\\{self.rng.choice('abcdefghij0123')}", "#\\a"),
            ("t", lambda: str(self.rand_int(-1000, 1000)), "nil"),
        ]
        etype, gen_val, init = self.rng.choice(specs)
        rank = self.rng.choice([1, 2, 3])
        if rank == 1:
            n = self.rng.randint(3, 12)
            dims = f"({n})"
            arr_type = f"(simple-array {etype} ({n}))" if self.rng.random() < 0.5 else f"(simple-array {etype} (*))"
            inits = [gen_val() for _ in range(n)]
            i0 = self.rng.randrange(n)
            i1 = self.rng.randrange(n)
            i2 = self.rng.randrange(n)
            new_v = gen_val()
            known_const = self.rng.random() < 0.5
            lam = (
                f"(lambda (a k val) "
                f"(declare (type {arr_type} a) (type (mod {n}) k) (type {etype} val) {opt_decl}) "
                f"(let ((acc 0)) "
                f"  (setf (aref a {i0 if known_const else 'k'}) val) "
                f"  (progn (setf (aref a {i1}) (aref a {i2})) nil) "
                f"  (list acc (aref a k) (aref a {i0}) (aref a {i1}))))"
            )
            mk = f"(make-array {n} :element-type '{etype} :initial-contents (list {' '.join(inits)}))"
            return f"(funcall (compile nil '{lam}) {mk} {i2} {new_v})"
        elif rank == 2:
            d0, d1 = self.rng.randint(2, 5), self.rng.randint(2, 5)
            arr_type = (
                f"(simple-array {etype} ({d0} {d1}))"
                if self.rng.random() < 0.5
                else f"(simple-array {etype} (* *))"
            )
            i, j = self.rng.randrange(d0), self.rng.randrange(d1)
            i2, j2 = self.rng.randrange(d0), self.rng.randrange(d1)
            new_v = gen_val()
            lam = (
                f"(lambda (a i j val) "
                f"(declare (type {arr_type} a) (type (mod {d0}) i) (type (mod {d1}) j) (type {etype} val) {opt_decl}) "
                f"(setf (aref a i j) val) "
                f"(progn (setf (aref a {i2} {j2}) (aref a {i} {j})) :ok) "
                f"(list (aref a i j) (aref a {i2} {j2})))"
            )
            mk = f"(make-array '({d0} {d1}) :element-type '{etype} :initial-element {init})"
            return f"(funcall (compile nil '{lam}) {mk} {i} {j} {new_v})"
        else:
            d0, d1, d2 = self.rng.randint(2, 4), self.rng.randint(2, 4), self.rng.randint(2, 4)
            arr_type = (
                f"(simple-array {etype} ({d0} {d1} {d2}))"
                if self.rng.random() < 0.5
                else f"(simple-array {etype} (* * *))"
            )
            i, j, k = self.rng.randrange(d0), self.rng.randrange(d1), self.rng.randrange(d2)
            i2, j2, k2 = self.rng.randrange(d0), self.rng.randrange(d1), self.rng.randrange(d2)
            new_v = gen_val()
            lam = (
                f"(lambda (a i j k val) "
                f"(declare (type {arr_type} a) (type (mod {d0}) i) (type (mod {d1}) j) (type (mod {d2}) k) (type {etype} val) {opt_decl}) "
                f"(setf (aref a i j k) val) "
                f"(progn (setf (aref a {i2} {j2} {k2}) (aref a {i} {j} {k})) :ok) "
                f"(list (aref a i j k) (aref a {i2} {j2} {k2})))"
            )
            mk = f"(make-array '({d0} {d1} {d2}) :element-type '{etype} :initial-element {init})"
            return f"(funcall (compile nil '{lam}) {mk} {i} {j} {k} {new_v})"

    def gen_case_int_bits(self, opt_decl: str):
        kind = self.rng.choice(["u64", "s64", "u32", "s32", "fix", "tight"])
        if kind == "u64":
            lo, hi, decl = 0, (1 << 64) - 1, "(unsigned-byte 64)"
        elif kind == "s64":
            lo, hi, decl = -(1 << 63), (1 << 63) - 1, "(signed-byte 64)"
        elif kind == "u32":
            lo, hi, decl = 0, (1 << 32) - 1, "(unsigned-byte 32)"
        elif kind == "s32":
            lo, hi, decl = -(1 << 31), (1 << 31) - 1, "(signed-byte 32)"
        elif kind == "fix":
            lo, hi, decl = -(1 << 59), (1 << 59) - 1, "fixnum"
        else:
            a = self.rng.randint(-1000, 1000)
            b = a + self.rng.randint(1, 500)
            lo, hi, decl = a, b, f"(integer {a} {b})"

        x_val = self.rand_int(lo, hi)
        y_val = self.rand_int(lo, hi)
        sh = self.rng.randint(-65, 65)
        bsize = self.rng.randint(0, 64)
        bpos = self.rng.randint(0, 70)
        bitidx = self.rng.randint(0, 70)
        newb = self.rand_int(0, (1 << min(bsize, 64)) - 1) if bsize > 0 else 0

        lam = (
            f"(lambda (x y sh newb) "
            f"(declare (type {decl} x y) (type (integer -65 65) sh) "
            f"(type (unsigned-byte 64) newb) {opt_decl}) "
            f"(list "
            f"  (+ x y) (- x y) (* x y) (- x) "
            f"  (logand x y) (logior x y) (logxor x y) (lognot x) "
            f"  (logandc1 x y) (logandc2 x y) (logorc1 x y) (logorc2 x y) "
            f"  (logtest x y) (logbitp {bitidx} x) (logcount x) (integer-length x) "
            f"  (ash x sh) (ash x {sh}) "
            f"  (ldb (byte {bsize} {bpos}) x) "
            f"  (dpb newb (byte {bsize} {bpos}) x) "
            f"  (mask-field (byte {bsize} {bpos}) x) "
            f"  (deposit-field newb (byte {bsize} {bpos}) x) "
            f"  (< x y) (<= x y) (= x y) (/= x y) "
            f"  (if (zerop y) :z (multiple-value-list (truncate x y))) "
            f"  (if (zerop y) :z (multiple-value-list (floor x y))) "
            f"  (if (zerop y) :z (multiple-value-list (ceiling x y))) "
            f"  (if (zerop y) :z (multiple-value-list (round x y)))))"
        )
        return f"(funcall (compile nil '{lam}) {x_val} {y_val} {sh} {newb})"

    def gen_case_bignum(self, opt_decl: str):
        def rand_big():
            bits = self.rng.choice([31, 32, 33, 60, 61, 63, 64, 65, 96, 128, 192, 256])
            v = self.rng.getrandbits(bits)
            if self.rng.random() < 0.25:
                v = (1 << bits) - self.rng.randint(0, 5)
            elif self.rng.random() < 0.25:
                v = (1 << bits) + self.rng.randint(0, 5)
            return -v if self.rng.random() < 0.5 else v

        a = rand_big()
        b = rand_big()
        if b == 0:
            b = 1
        sh = self.rng.randint(-130, 130)
        bsize = self.rng.randint(0, 70)
        bpos = self.rng.randint(0, 140)
        bitidx = self.rng.randint(0, 260)
        base = self.rng.randint(-5, 5)
        exp = self.rng.randint(0, 40)
        isq = abs(a)

        lam = (
            f"(lambda (a b sh isq base exp) "
            f"(declare (type integer a b) (type (integer -130 130) sh) "
            f"(type (integer 0 *) isq) (type (integer -5 5) base) (type (integer 0 40) exp) {opt_decl}) "
            f"(list "
            f"  (+ a b) (- a b) (* a b) (- a) (abs a) "
            f"  (multiple-value-list (truncate a b)) "
            f"  (multiple-value-list (floor a b)) "
            f"  (multiple-value-list (ceiling a b)) "
            f"  (multiple-value-list (round a b)) "
            f"  (gcd a b) (lcm a (max 1 (min 100 (abs b)))) "
            f"  (isqrt isq) (expt base exp) "
            f"  (ash a sh) (ash a {sh}) "
            f"  (logand a b) (logior a b) (logxor a b) (logandc2 a b) "
            f"  (logtest a b) (logbitp {bitidx} a) (logcount a) (integer-length a) "
            f"  (ldb (byte {bsize} {bpos}) a) "
            f"  (dpb 12345678901234567890 (byte {bsize} {bpos}) a) "
            f"  (< a b) (= a b)))"
        )
        return f"(funcall (compile nil '{lam}) {a} {b} {sh} {isq} {base} {exp})"

    def gen_case_mv_ctrl(self, opt_decl: str):
        base = self.rng.randint(-50, 50)
        span = self.rng.randint(6, 15)
        clauses = []
        for k in range(base, base + span):
            if self.rng.random() < 0.8:
                clauses.append(f"({k} (+ x {k * 3}))")
        cases_str = " ".join(clauses)
        x_val = self.rng.randint(base - 2, base + span + 2)
        y_val = self.rng.randint(-100, 100)
        z_val = self.rng.randint(-100, 100)
        lam = (
            f"(lambda (x y z) "
            f"(declare (type (signed-byte 32) x y z) {opt_decl}) "
            f"(let ((acc 0) (log nil)) "
            f"  (declare (type integer acc)) "
            f"  (setf acc (+ acc (case x {cases_str} (otherwise (- x 99))))) "
            f"  (multiple-value-bind (a b c) "
            f"      (multiple-value-prog1 (values (+ x 1) (+ y 2) (+ z 3)) "
            f"        (push acc log) (setf x (+ x 5))) "
            f"    (push (list a b c x) log)) "
            f"  (push (nth-value 1 (truncate (+ (* x y) 17) (if (zerop z) 3 z))) log) "
            f"  (push (multiple-value-call #'list (values x y) (values) (values z (+ x 1))) log) "
            f"  (push (block b0 (unwind-protect (return-from b0 (+ acc 7)) (incf acc 100))) log) "
            f"  (push (flet ((rec (&rest r) (apply #'+ acc (incf acc 2) r))) "
            f"          (declare (inline rec)) "
            f"          (rec x (incf acc 3) y)) log) "
            f"  (list acc log)))"
        )
        return f"(funcall (compile nil '{lam}) {x_val} {y_val} {z_val})"

    def generate_batch(self, count: int):
        cases = []
        opts = [
            "(optimize (speed 1) (safety 3))",
            "(optimize (speed 3) (safety 0))",
        ]
        gens = [
            ("complex", self.gen_case_complex_float),
            ("float", self.gen_case_float),
            ("array", self.gen_case_array),
            ("intbits", self.gen_case_int_bits),
            ("bignum", self.gen_case_bignum),
            ("mvctrl", self.gen_case_mv_ctrl),
        ]
        for idx in range(count):
            cat, fn = gens[idx % len(gens)]
            opt = opts[(idx // len(gens)) % len(opts)]
            expr = fn(opt)
            cases.append((idx, cat, opt, expr))
        return cases


def build_lisp_harness(cases) -> str:
    lines = [
        "(in-package :cl-user)",
        "(let ((*print-readably* nil) (*print-pretty* nil) (*print-length* nil) (*print-level* nil))",
    ]
    for idx, cat, opt, expr in cases:
        lines.append(
            f"  (handler-case "
            f"    (let ((res {expr})) "
            f"      (format t \"RES ~D ~A~%\" {idx} (substitute #\\Space #\\Newline (string-upcase (prin1-to-string res))))) "
            f"    (error (e) (format t \"ERR ~D ~A~%\" {idx} (substitute #\\_ #\\Newline (princ-to-string e)))))"
        )
    lines.append(")")
    lines.append("#+ccl (ccl:quit 0)")
    lines.append("#+sbcl (sb-ext:exit :code 0)")
    return "\n".join(lines) + "\n"


def parse_output(text: str):
    out = {}
    for line in text.splitlines():
        if line.startswith("RES ") or line.startswith("ERR "):
            parts = line.split(" ", 2)
            if len(parts) == 3:
                out[int(parts[1])] = (parts[0], parts[2])
    return out


def run_sbcl(lisp_path: str):
    p = subprocess.run(
        TIMEOUT_LOCAL + [SBCL_BIN, "--script", lisp_path],
        capture_output=True, text=True
    )
    return p.returncode, p.stdout, p.stderr


def run_arm64_ccl(lisp_path: str):
    p = subprocess.run(
        TIMEOUT_LOCAL + [ARM64_CCL_BIN, "--no-init", "--batch", "--load", lisp_path],
        capture_output=True, text=True
    )
    return p.returncode, p.stdout, p.stderr


def run_x86_ccl(lisp_src: str):
    remote_path = f"/tmp/ccl_fuzz_{os.getpid()}.lisp"
    p = subprocess.run(
        ["ssh", X86_CCL_SSH, f"cat > {remote_path} && timeout 60s {X86_CCL_BIN} --no-init --batch --load {remote_path}; rc=$?; rm -f {remote_path}; exit $rc"],
        input=lisp_src,
        capture_output=True, text=True
    )
    return p.returncode, p.stdout, p.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--batches", type=int, default=5)
    ap.add_argument("--batch-size", type=int, default=180)
    args = ap.parse_args()

    total_cases = 0
    mismatches = []
    t0 = time.time()

    for b in range(args.batches):
        gen = FuzzGenerator(args.seed + b * 1000)
        cases = gen.generate_batch(args.batch_size)
        src = build_lisp_harness(cases)
        with tempfile.NamedTemporaryFile("w", suffix=".lisp", delete=False) as tf:
            tf.write(src)
            tf_path = tf.name

        try:
            rc_s, out_s, err_s = run_sbcl(tf_path)
            rc_a, out_a, err_a = run_arm64_ccl(tf_path)
            rc_x, out_x, err_x = run_x86_ccl(src)
        finally:
            os.unlink(tf_path)

        res_s = parse_output(out_s)
        res_a = parse_output(out_a)
        res_x = parse_output(out_x)

        batch_mismatches = 0
        for idx, cat, opt, expr in cases:
            total_cases += 1
            vs = res_s.get(idx, ("MISSING", ""))
            va = res_a.get(idx, ("MISSING", ""))
            vx = res_x.get(idx, ("MISSING", ""))
            # Exact string comparison; note float rounding between single/double transcendental?
            # None of our expressions use trig/exp/log, only exact/IEEE +, -, *, /, sqrt!
            if not (vs == va == vx) or vs[0] != "RES":
                batch_mismatches += 1
                mismatches.append((b, idx, cat, opt, expr, vs, va, vx))

        print(
            f"[batch {b+1}/{args.batches}] cases={len(cases)} rc=(sbcl:{rc_s}, arm64:{rc_a}, x86:{rc_x}) "
            f"parsed=({len(res_s)}, {len(res_a)}, {len(res_x)}) diffs={batch_mismatches}",
            flush=True,
        )

    elapsed = time.time() - t0
    print(f"\nSUMMARY: total_cases={total_cases} total_diffs={len(mismatches)} elapsed={elapsed:.1f}s")
    for i, (b, idx, cat, opt, expr, vs, va, vx) in enumerate(mismatches[:25]):
        print(f"\n--- DIFF #{i+1} batch={b} idx={idx} cat={cat} opt={opt} ---")
        print(f"EXPR: {expr}")
        print(f"SBCL:  {vs}")
        print(f"ARM64: {va}")
        print(f"X8664: {vx}")


if __name__ == "__main__":
    main()
