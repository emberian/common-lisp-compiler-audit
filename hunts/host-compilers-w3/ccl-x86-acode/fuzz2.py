#!/usr/bin/env python3
"""Targeted differential fuzzer v2 for CCL 1.14 (x86-64 vs ARM64) vs SBCL 2.6.10.

Covers:
  1. For-effect compilation & execution of every operator in (progn <op> :ok)
  2. Complex double-float (and complex single-float without sub) + conjugate/realpart/imagpart/complex
  3. Non-simple, adjustable, displaced arrays + fill-pointers + string/bit-vector ops + 2D/3D unknown dims
  4. acode-rewrite edge cases: constant folding, tight integer bounds, ash/logops/mul/add/sub/neg,
     -0.0/+0.0 float identities, boolean/comparison inversions, typed-form nesting
  5. High register pressure: 12-16 live integers/floats/complexes across nested calls, closures, tagbody, catch
  6. Dense/sparse CASE jump tables (negative min, 32-bit span, fixnum/non-fixnum), &rest/apply aliasing
"""

import argparse
import os
import random
import subprocess
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


class Fuzz2:
    def __init__(self, seed: int):
        self.rng = random.Random(seed)

    def rand_sf(self) -> str:
        choices = [0.0, -0.0, 1.0, -1.0, 2.0, -2.0, 0.5, -0.5, self.rng.uniform(-50.0, 50.0)]
        v = self.rng.choice(choices)
        if v == 0.0 and self.rng.random() < 0.5:
            return "-0.0f0"
        return fmt_sf(v)

    def rand_df(self) -> str:
        choices = [0.0, -0.0, 1.0, -1.0, 2.0, -2.0, 0.5, -0.5, self.rng.uniform(-100.0, 100.0)]
        v = self.rng.choice(choices)
        if v == 0.0 and self.rng.random() < 0.5:
            return "-0.0d0"
        return fmt_df(v)

    def gen_for_effect(self, opt: str) -> str:
        # Stress vreg = NIL (and test-only if context) across CCL acode operators!
        ops = [
            "(lambda (a b) (declare (type (signed-byte 64) a b) {opt}) (progn (+ a b) (- a b) (* a b) (- a) (ash a 3) (logand a b) (logior a b) (logxor a b) (lognot a) (logbitp 5 a) (logtest a b) (= a b) (< a b) :ok))",
            "(lambda (a b) (declare (type (unsigned-byte 64) a b) {opt}) (progn (+ a b) (- a b) (* a b) (ash a -3) (ldb (byte 8 4) a) (dpb 3 (byte 8 4) a) :ok))",
            "(lambda (x y) (declare (type double-float x y) {opt}) (progn (+ x y) (- x y) (* x y) (/ x (if (zerop y) 1.0d0 y)) (- x) (abs x) (sqrt (abs x)) (= x y) (< x y) (<= x y) (float x 1.0f0) :ok))",
            "(lambda (x y) (declare (type single-float x y) {opt}) (progn (+ x y) (- x y) (* x y) (/ x (if (zerop y) 1.0f0 y)) (- x) (abs x) (sqrt (abs x)) (= x y) (< x y) (<= x y) (float x 1.0d0) :ok))",
            "(lambda (c) (declare (type (complex double-float) c) {opt}) (progn (realpart c) (imagpart c) (conjugate c) (complex (realpart c) (imagpart c)) :ok))",
            "(lambda (c) (declare (type (complex single-float) c) {opt}) (progn (realpart c) (imagpart c) (conjugate c) (complex (realpart c) (imagpart c)) :ok))",
            "(lambda (x y) (declare (type double-float x y) {opt}) (progn (complex x y) :ok))",
            "(lambda (x y) (declare (type single-float x y) {opt}) (progn (complex x y) :ok))",
            "(lambda (s c n) (declare (type simple-base-string s) (type base-char c) (type fixnum n) {opt}) (progn (schar s 0) (char-code c) (code-char (mod (abs n) 128)) (characterp c) :ok))",
            "(lambda (v) (declare (type (simple-array (unsigned-byte 64) (*)) v) {opt}) (progn (aref v 0) (setf (aref v 0) 7) :ok))",
            "(lambda (v) (declare (type (simple-array double-float (*)) v) {opt}) (progn (aref v 0) (setf (aref v 0) 1.0d0) :ok))",
            "(lambda (v) (declare (type (simple-array (complex double-float) (*)) v) {opt}) (progn (aref v 0) (setf (aref v 0) #c(1d0 2d0)) :ok))",
            "(lambda (v) (declare (type (simple-array (complex single-float) (*)) v) {opt}) (progn (aref v 0) (setf (aref v 0) #c(1f0 2f0)) :ok))",
            "(lambda (x) (declare (type cons x) {opt}) (progn (car x) (cdr x) (consp x) (endp x) :ok))",
        ]
        choice = self.rng.randrange(len(ops))
        lam = ops[choice].format(opt=opt)
        args_map = {
            0: "-5 17",
            1: "123456789012345 999",
            2: "1.5d0 -2.25d0",
            3: "1.5f0 -2.25f0",
            4: "#c(1d0 2d0)",
            5: "#c(1f0 2f0)",
            6: "1.0d0 2.0d0",
            7: "1.0f0 2.0f0",
            8: "(copy-seq \"abc\") #\\z 65",
            9: "(make-array 2 :element-type '(unsigned-byte 64) :initial-element 1)",
            10: "(make-array 2 :element-type 'double-float :initial-element 1.0d0)",
            11: "(make-array 2 :element-type '(complex double-float) :initial-element #c(1d0 0d0))",
            12: "(make-array 2 :element-type '(complex single-float) :initial-element #c(1f0 0f0))",
            13: "(cons 1 2)",
        }
        return f"(funcall (compile nil '{lam}) {args_map[choice]})"

    def gen_complex_double(self, opt: str) -> str:
        # Deep complex double-float expressions + conjugate + complex-single without subtraction
        nargs = self.rng.randint(5, 9)
        vs = [f"z{i}" for i in range(nargs)]
        vals = [f"#C({self.rand_df()} {self.rand_df()})" for _ in range(nargs)]
        def expr(d):
            if d <= 0 or (d < 3 and self.rng.random() < 0.35):
                return self.rng.choice(vs) if self.rng.random() < 0.7 else f"#C({self.rand_df()} {self.rand_df()})"
            op = self.rng.choice(["+", "-", "*", "conj", "mk", "r", "i"])
            if op in ("+", "-", "*"):
                return f"(the (complex double-float) ({op} {expr(d-1)} {expr(d-1)}))"
            if op == "conj":
                return f"(the (complex double-float) (conjugate {expr(d-1)}))"
            if op == "mk":
                return f"(the (complex double-float) (complex (realpart {expr(d-1)}) (imagpart {expr(d-1)})))"
            return f"(the (complex double-float) (complex (the double-float ({op == 'r' and '+' or '-'} (realpart {expr(d-1)}) (imagpart {expr(d-1)}))) 0.5d0))"
        lam = (
            f"(lambda ({' '.join(vs)}) "
            f"(declare (type (complex double-float) {' '.join(vs)}) {opt}) "
            f"(let ((a {expr(3)}) (b {expr(3)}) (c {expr(2)})) "
            f"  (declare (type (complex double-float) a b c)) "
            f"  (+ (- a b) (* c (- {expr(2)} a)))))"
        )
        return f"(funcall (compile nil '{lam}) {' '.join(vals)})"

    def gen_nonsimple_array(self, opt: str) -> str:
        # Adjustable, displaced, fill-pointer, 2D/3D non-simple arrays, bit-vectors, strings
        specs = [
            ("(unsigned-byte 64)", str(self.rng.randint(0, (1 << 64) - 1)), "0"),
            ("(signed-byte 64)", str(self.rng.randint(-(1 << 63), (1 << 63) - 1)), "0"),
            ("(unsigned-byte 32)", str(self.rng.randint(0, (1 << 32) - 1)), "0"),
            ("(signed-byte 16)", str(self.rng.randint(-32768, 32767)), "0"),
            ("(unsigned-byte 8)", str(self.rng.randint(0, 255)), "0"),
            ("double-float", self.rand_df(), "0.0d0"),
            ("single-float", self.rand_sf(), "0.0f0"),
            ("(complex double-float)", f"#C({self.rand_df()} {self.rand_df()})", "#C(0.0d0 0.0d0)"),
            ("(complex single-float)", f"#C({self.rand_sf()} {self.rand_sf()})", "#C(0.0f0 0.0f0)"),
            ("bit", str(self.rng.choice([0, 1])), "0"),
            ("base-char", f"#\\{self.rng.choice('xyz012')}", "#\\a"),
        ]
        etype, newv, init = self.rng.choice(specs)
        mode = self.rng.choice(["adj1d", "disp1d", "adj2d", "fp1d"])
        if mode == "adj1d":
            n = self.rng.randint(4, 10)
            i = self.rng.randrange(n)
            j = self.rng.randrange(n)
            lam = (
                f"(lambda (a i j v) "
                f"(declare (type (array {etype} (*)) a) (type (mod {n}) i j) (type {etype} v) {opt}) "
                f"(setf (aref a i) v) "
                f"(list (aref a i) (aref a j) (length a) (array-total-size a)))"
            )
            mk = f"(make-array {n} :element-type '{etype} :initial-element {init} :adjustable t)"
            return f"(funcall (compile nil '{lam}) {mk} {i} {j} {newv})"
        elif mode == "disp1d":
            n = self.rng.randint(6, 12)
            off = self.rng.randint(1, 3)
            dn = n - off
            i = self.rng.randrange(dn)
            lam = (
                f"(lambda (a i v) "
                f"(declare (type (array {etype} (*)) a) (type (mod {dn}) i) (type {etype} v) {opt}) "
                f"(setf (aref a i) v) "
                f"(aref a i))"
            )
            mk = f"(let ((base (make-array {n} :element-type '{etype} :initial-element {init}))) (make-array {dn} :element-type '{etype} :displaced-to base :displaced-index-offset {off}))"
            return f"(funcall (compile nil '{lam}) {mk} {i} {newv})"
        elif mode == "adj2d":
            d0, d1 = 3, 4
            i, j = self.rng.randrange(d0), self.rng.randrange(d1)
            lam = (
                f"(lambda (a i j v) "
                f"(declare (type (array {etype} (* *)) a) (type (mod {d0}) i) (type (mod {d1}) j) (type {etype} v) {opt}) "
                f"(setf (aref a i j) v) "
                f"(aref a i j))"
            )
            mk = f"(make-array '({d0} {d1}) :element-type '{etype} :initial-element {init} :adjustable t)"
            return f"(funcall (compile nil '{lam}) {mk} {i} {j} {newv})"
        else:
            n = 8
            fp = 4
            lam = (
                f"(lambda (a v) "
                f"(declare (type (vector {etype}) a) (type {etype} v) {opt}) "
                f"(vector-push v a) "
                f"(vector-push-extend v a) "
                f"(list (fill-pointer a) (aref a 4) (aref a 5) (length a)))"
            )
            mk = f"(make-array {n} :element-type '{etype} :initial-element {init} :fill-pointer {fp} :adjustable t)"
            return f"(funcall (compile nil '{lam}) {mk} {newv})"

    def gen_acode_rewrite(self, opt: str) -> str:
        # Target acode-rewrite transforms + tight types + float -0.0 / constants
        pat = self.rng.choice([
            # tight intervals + ash / logops / add / sub / mul
            lambda: (
                f"(funcall (compile nil '(lambda (x y) "
                f"(declare (type (integer -10 10) x) (type (integer 0 5) y) {opt}) "
                f"(list (1+ (+ x y)) (1- (- x y)) (+ x 0) (- x 0) (* x 1) (* x -1) (* x 0) "
                f"(ash x 0) (ash x 60) (ash x -60) (ash (the (integer 0 0) (- x x)) y) "
                f"(logand x -1) (logand x 0) (logior x 0) (logior x -1) (logxor x 0) "
                f"(logandc2 x x) (logtest x 0) (logbitp 60 x)))) "
                f"{self.rng.randint(-10, 10)} {self.rng.randint(0, 5)})"
            ),
            # float -0.0 / identity / comparison negation
            lambda: (
                f"(funcall (compile nil '(lambda (x y) "
                f"(declare (type double-float x y) {opt}) "
                f"(list (+ x 0.0d0) (+ x -0.0d0) (- x 0.0d0) (- 0.0d0 x) (* x 1.0d0) (* x -1.0d0) (* x 0.0d0) "
                f"(not (< x y)) (not (<= x y)) (not (= x y)) (not (/= x y)) "
                f"(if (< x y) :lt :ge) (if (not (> x y)) :le :gt)))) "
                f"{self.rng.choice(['0.0d0', '-0.0d0', '1.5d0', '-2.5d0'])} "
                f"{self.rng.choice(['0.0d0', '-0.0d0', '1.5d0', '-2.5d0'])})"
            ),
            # single-float -0.0 / identity / coerce from u64/s64/fixnum
            lambda: (
                f"(funcall (compile nil '(lambda (x y u s) "
                f"(declare (type single-float x y) (type (unsigned-byte 64) u) (type (signed-byte 64) s) {opt}) "
                f"(list (+ x 0.0f0) (- x) (* x -1.0f0) (float u 1.0d0) (float s 1.0d0) (float u 1.0f0) (float s 1.0f0) "
                f"(not (< x y)) (not (= x y))))) "
                f"{self.rng.choice(['0.0f0', '-0.0f0', '3.5f0'])} "
                f"{self.rng.choice(['0.0f0', '-0.0f0', '-3.5f0'])} "
                f"{self.rng.choice([0, (1<<63), (1<<64)-1, 12345678901234567])} "
                f"{self.rng.choice([0, -(1<<63), (1<<63)-1, -987654321098765])})"
            ),
            # side effects inside condition / not / eq / values / prog1
            lambda: (
                f"(funcall (compile nil '(lambda (a b) "
                f"(declare (type fixnum a b) {opt}) "
                f"(let ((c 0)) (declare (type fixnum c)) "
                f"  (list (not (progn (incf c) (< a b))) "
                f"        (if (prog1 (= a b) (incf c 10)) (incf c 100) (incf c 1000)) "
                f"        (eq (progn (incf c 2) a) (progn (incf c 3) b)) "
                f"        (prog1 c (incf c 50)) "
                f"        c)))) "
                f"{self.rng.randint(-5, 5)} {self.rng.randint(-5, 5)})"
            ),
        ])
        return pat()

    def gen_reg_pressure(self, opt: str) -> str:
        # 12 live variables (6 ints + 4 doubles + 2 complexes) across function calls and tagbody
        vs_i = [f"i{k}" for k in range(6)]
        vs_d = [f"d{k}" for k in range(4)]
        vals_i = [str(self.rng.randint(-(1 << 62), (1 << 62) - 1)) for _ in range(6)]
        vals_d = [self.rand_df() for _ in range(4)]
        lam = (
            f"(lambda ({' '.join(vs_i + vs_d)}) "
            f"(declare (type (signed-byte 64) {' '.join(vs_i)}) (type double-float {' '.join(vs_d)}) {opt}) "
            f"(labels ((mix (a b c) (declare (type (signed-byte 64) a b c)) (logxor (+ a b) (ash c -3)))) "
            f"  (declare (notinline mix)) "
            f"  (let ((acc 0) (facc 0.0d0)) "
            f"    (declare (type integer acc) (type double-float facc)) "
            f"    (dotimes (k 3) "
            f"      (setf acc (+ acc (mix i0 i1 i2) (mix i3 i4 i5))) "
            f"      (setf facc (+ facc (* (+ d0 d1) (- d2 d3)))) "
            f"      (psetf i0 i1 i1 i2 i2 i3 i3 i4 i4 i5 i5 (logxor i0 k) "
            f"             d0 (+ d1 0.5d0) d1 d2 d2 d3 d3 (+ d0 0.25d0))) "
            f"    (list acc i0 i1 i2 i3 i4 i5 facc d0 d1 d2 d3))))"
        )
        return f"(funcall (compile nil '{lam}) {' '.join(vals_i + vals_d)})"

    def gen_case_and_rest(self, opt: str) -> str:
        # Dense case jump table with negative keys, big constants, and closures + &rest/apply
        mink = self.rng.choice([-1000, -100, -10, 0, 100000])
        span = self.rng.randint(6, 12)
        clauses = " ".join(f"({k} (list :k {k} (+ x {k})))" for k in range(mink, mink + span) if self.rng.random() < 0.85)
        x_val = self.rng.choice([mink - 1, mink, mink + 2, mink + span, (1 << 40), 'sym'])
        if x_val == 'sym':
            x_val = "'foo"
        lam = (
            f"(lambda (x y) "
            f"(declare {opt}) "
            f"(let* ((fn (lambda () (incf y 10))) "
            f"       (r1 (case x {clauses} (otherwise (list :other x))))) "
            f"  (flet ((h (&rest r) (apply #'list y (funcall fn) r))) "
            f"    (declare (inline h)) "
            f"    (list r1 (h x (incf y 5)) y))))"
        )
        return f"(funcall (compile nil '{lam}) {x_val} {self.rng.randint(-50, 50)})"

    def generate_batch(self, count: int):
        cases = []
        opts = [
            "(optimize (speed 1) (safety 3))",
            "(optimize (speed 3) (safety 0))",
        ]
        gens = [
            ("for_effect", self.gen_for_effect),
            ("c_double", self.gen_complex_double),
            ("nonsimple_arr", self.gen_nonsimple_array),
            ("acode_rw", self.gen_acode_rewrite),
            ("reg_press", self.gen_reg_pressure),
            ("case_rest", self.gen_case_and_rest),
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
    p = subprocess.run(TIMEOUT_LOCAL + [SBCL_BIN, "--script", lisp_path], capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def run_arm64_ccl(lisp_path: str):
    p = subprocess.run(TIMEOUT_LOCAL + [ARM64_CCL_BIN, "--no-init", "--batch", "--load", lisp_path], capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def run_x86_ccl(lisp_src: str):
    remote_path = f"/tmp/ccl_fuzz2_{os.getpid()}.lisp"
    p = subprocess.run(
        ["ssh", X86_CCL_SSH, f"cat > {remote_path} && timeout 60s {X86_CCL_BIN} --no-init --batch --load {remote_path}; rc=$?; rm -f {remote_path}; exit $rc"],
        input=lisp_src, capture_output=True, text=True,
    )
    return p.returncode, p.stdout, p.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=100)
    ap.add_argument("--batches", type=int, default=5)
    ap.add_argument("--batch-size", type=int, default=180)
    args = ap.parse_args()

    total_cases = 0
    mismatches = []
    t0 = time.time()

    for b in range(args.batches):
        gen = Fuzz2(args.seed + b * 1000)
        cases = gen.generate_batch(args.batch_size)
        src = build_lisp_harness(cases)
        with tempfile.NamedTemporaryFile("w", suffix=".lisp", delete=False) as tf:
            tf.write(src)
            tf_path = tf.name

        try:
            rc_s, out_s, _ = run_sbcl(tf_path)
            rc_a, out_a, _ = run_arm64_ccl(tf_path)
            rc_x, out_x, _ = run_x86_ccl(src)
        finally:
            os.unlink(tf_path)

        res_s = parse_output(out_s)
        res_a = parse_output(out_a)
        res_x = parse_output(out_x)

        batch_diffs = 0
        for idx, cat, opt, expr in cases:
            total_cases += 1
            vs = res_s.get(idx, ("MISSING", ""))
            va = res_a.get(idx, ("MISSING", ""))
            vx = res_x.get(idx, ("MISSING", ""))
            if not (vs == va == vx) or vs[0] != "RES":
                batch_diffs += 1
                mismatches.append((b, idx, cat, opt, expr, vs, va, vx))

        print(
            f"[batch {b+1}/{args.batches}] cases={len(cases)} rc=(sbcl:{rc_s}, arm64:{rc_a}, x86:{rc_x}) "
            f"parsed=({len(res_s)}, {len(res_a)}, {len(res_x)}) diffs={batch_diffs}",
            flush=True,
        )

    elapsed = time.time() - t0
    print(f"\nSUMMARY: total_cases={total_cases} total_diffs={len(mismatches)} elapsed={elapsed:.1f}s")
    for i, (b, idx, cat, opt, expr, vs, va, vx) in enumerate(mismatches[:40]):
        print(f"\n--- DIFF #{i+1} batch={b} idx={idx} cat={cat} opt={opt} ---")
        print(f"EXPR: {expr}")
        print(f"SBCL:  {vs}")
        print(f"ARM64: {va}")
        print(f"X8664: {vx}")


if __name__ == "__main__":
    main()
