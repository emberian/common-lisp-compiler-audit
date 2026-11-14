#!/usr/bin/env python3
"""Cross-arch differential fuzzer v3 for CCL 1.14 (x86-64 vs ARM64) vs SBCL 2.6.10.

Cleanly normalizes benign CL printing differences (D+16 vs D16) while keeping
-0.0 vs +0.0, exact integers, booleans, arrays, and lists strict.
Tests deep random combinations across all arithmetic, array, bit, complex,
bignum, multiple-value, and control-flow subsystems.
"""

import argparse
import os
import random
import re
import subprocess
import tempfile
import time

SBCL_BIN = "/opt/homebrew/bin/sbcl"
ARM64_CCL_BIN = "/Users/ember/dev/ccl/darm64cl"
X86_CCL_SSH = "hbox"
X86_CCL_BIN = "/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64"
TIMEOUT_LOCAL = ["/opt/homebrew/bin/timeout", "--kill-after=10s", "60s"]


def normalize_output(s: str) -> str:
    # Normalize exponent '+' in SBCL vs CCL float printing (e.g. 1.0D+16 -> 1.0D16)
    return re.sub(r"([DE])\+(\d)", r"\1\2", s)


def fmt_sf(x: float) -> str:
    if x == 0.0:
        return "-0.0f0" if str(x).startswith("-") else "0.0f0"
    return f"{x:.6g}f0".replace("e", "f")


def fmt_df(x: float) -> str:
    if x == 0.0:
        return "-0.0d0" if str(x).startswith("-") else "0.0d0"
    return f"{x:.12g}d0".replace("e", "d")


class Fuzz3:
    def __init__(self, seed: int):
        self.rng = random.Random(seed)

    def rand_sf(self) -> str:
        v = self.rng.choice([0.0, -0.0, 1.0, -1.0, 2.0, -2.0, 0.5, -0.5, 3.25, -7.5, self.rng.uniform(-40.0, 40.0)])
        if v == 0.0 and self.rng.random() < 0.5:
            return "-0.0f0"
        return fmt_sf(v)

    def rand_df(self) -> str:
        v = self.rng.choice([0.0, -0.0, 1.0, -1.0, 2.0, -2.0, 0.5, -0.5, 0.125, -19.25, self.rng.uniform(-80.0, 80.0)])
        if v == 0.0 and self.rng.random() < 0.5:
            return "-0.0d0"
        return fmt_df(v)

    def gen_int_tree(self, opt: str) -> str:
        # Random expression tree over (signed-byte 64), (unsigned-byte 64), (signed-byte 32), fixnum, tight intervals
        width = self.rng.choice(["u64", "s64", "u32", "s32", "fix", "u8", "s8"])
        bounds = {
            "u64": (0, (1 << 64) - 1, "(unsigned-byte 64)"),
            "s64": (-(1 << 63), (1 << 63) - 1, "(signed-byte 64)"),
            "u32": (0, (1 << 32) - 1, "(unsigned-byte 32)"),
            "s32": (-(1 << 31), (1 << 31) - 1, "(signed-byte 32)"),
            "fix": (-(1 << 59), (1 << 59) - 1, "fixnum"),
            "u8": (0, 255, "(unsigned-byte 8)"),
            "s8": (-128, 127, "(signed-byte 8)"),
        }
        lo, hi, decl = bounds[width]
        nvars = 5
        vs = [f"x{i}" for i in range(nvars)]
        vals = [str(self.rng.choice([lo, hi, 0, 1, -1, self.rng.randint(lo, hi)])) for _ in range(nvars)]
        # Make sure negatives aren't chosen for u64/u32/u8
        vals = [str(max(lo, min(hi, int(v)))) for v in vals]

        def expr(d):
            if d <= 0 or (d < 3 and self.rng.random() < 0.3):
                return self.rng.choice(vs)
            kind = self.rng.choice(["+", "-", "*", "ash", "logand", "logior", "logxor", "ldb", "dpb", "if", "div", "logtest"])
            if kind in ("+", "-", "*", "logand", "logior", "logxor"):
                return f"({kind} {expr(d-1)} {expr(d-1)})"
            if kind == "ash":
                sh = self.rng.randint(-64, 64)
                return f"(ash {expr(d-1)} {sh})"
            if kind == "ldb":
                return f"(ldb (byte {self.rng.randint(0, 64)} {self.rng.randint(0, 65)}) {expr(d-1)})"
            if kind == "dpb":
                return f"(dpb {expr(d-1)} (byte {self.rng.randint(1, 32)} {self.rng.randint(0, 32)}) {expr(d-1)})"
            if kind == "div":
                op = self.rng.choice(["truncate", "floor", "ceiling", "rem", "mod"])
                return f"(let ((d {expr(d-1)})) ({op} {expr(d-1)} (if (zerop d) 1 d)))"
            if kind == "logtest":
                return f"(if (logtest {expr(d-1)} {expr(d-1)}) 111 -222)"
            cmp = self.rng.choice(["<", "<=", "=", "/=", ">", ">="])
            return f"(if ({cmp} {expr(d-1)} {expr(d-1)}) {expr(d-1)} {expr(d-1)})"

        lam = (
            f"(lambda ({' '.join(vs)}) "
            f"(declare (type {decl} {' '.join(vs)}) {opt}) "
            f"(list {expr(3)} {expr(3)}))"
        )
        return f"(funcall (compile nil '{lam}) {' '.join(vals)})"

    def gen_float_mix(self, opt: str) -> str:
        # Mixed float, integer->float, complex double-float, realpart/imagpart, floor/truncate
        d0, d1 = self.rand_df(), self.rand_df()
        s0, s1 = self.rand_sf(), self.rand_sf()
        u0 = self.rng.choice([0, 1, (1 << 32) - 1, (1 << 53), (1 << 63) - 1, (1 << 64) - 1])
        i0 = self.rng.choice([0, -1, -(1 << 59), (1 << 59) - 1, -(1 << 63), (1 << 63) - 1])
        lam = (
            f"(lambda (d0 d1 s0 s1 u0 i0) "
            f"(declare (type double-float d0 d1) (type single-float s0 s1) "
            f"(type (unsigned-byte 64) u0) (type (signed-byte 64) i0) {opt}) "
            f"(let* ((cd (the (complex double-float) (complex d0 d1))) "
            f"       (cs (the (complex single-float) (complex s0 s1))) "
            f"       (cd2 (the (complex double-float) (* cd (conjugate cd)))) "
            f"       (cs2 (the (complex single-float) (* cs (+ cs #C(1.0f0 -0.5f0)))))) "
            f"  (list (+ (float u0 1.0d0) d0) "
            f"        (- (float i0 1.0d0) d1) "
            f"        (+ (float u0 1.0f0) s0) "
            f"        (- (float i0 1.0f0) s1) "
            f"        (multiple-value-list (truncate (+ d0 d1))) "
            f"        (multiple-value-list (floor (- s0 s1))) "
            f"        (multiple-value-list (ceiling (* d0 0.5d0))) "
            f"        (multiple-value-list (round (* s0 1.5f0))) "
            f"        cd2 cs2 "
            f"        (realpart cd2) (imagpart cd2) (realpart cs2) (imagpart cs2) "
            f"        (eql d0 -0.0d0) (= d0 0.0d0) (eql s0 -0.0f0) (= s0 0.0f0))))"
        )
        return f"(funcall (compile nil '{lam}) {d0} {d1} {s0} {s1} {u0} {i0})"

    def gen_array_mix(self, opt: str) -> str:
        # 1D, 2D, 3D arrays with both constant and variable indices, known & unknown bounds, and side-effecting expressions
        specs = [
            ("(unsigned-byte 64)", str(self.rng.randint(0, (1 << 64) - 1)), "0"),
            ("(signed-byte 64)", str(self.rng.randint(-(1 << 63), (1 << 63) - 1)), "0"),
            ("(unsigned-byte 32)", str(self.rng.randint(0, (1 << 32) - 1)), "0"),
            ("(signed-byte 32)", str(self.rng.randint(-(1 << 31), (1 << 31) - 1)), "0"),
            ("(unsigned-byte 16)", str(self.rng.randint(0, 65535)), "0"),
            ("(signed-byte 16)", str(self.rng.randint(-32768, 32767)), "0"),
            ("(unsigned-byte 8)", str(self.rng.randint(0, 255)), "0"),
            ("(signed-byte 8)", str(self.rng.randint(-128, 127)), "0"),
            ("double-float", self.rand_df(), "0.0d0"),
            ("single-float", self.rand_sf(), "0.0f0"),
            ("(complex double-float)", f"#C({self.rand_df()} {self.rand_df()})", "#C(0.0d0 0.0d0)"),
            ("(complex single-float)", f"#C({self.rand_sf()} {self.rand_sf()})", "#C(0.0f0 0.0f0)"),
            ("bit", str(self.rng.choice([0, 1])), "0"),
        ]
        etype, v0, init = self.rng.choice(specs)
        _, v1, _ = self.rng.choice([s for s in specs if s[0] == etype])
        d0, d1, d2 = 3, 4, 5
        i, j, k = self.rng.randrange(d0), self.rng.randrange(d1), self.rng.randrange(d2)
        lam = (
            f"(lambda (a1 a2 a3 i j k v0 v1) "
            f"(declare (type (simple-array {etype} ({d2})) a1) "
            f"         (type (simple-array {etype} ({d0} {d1})) a2) "
            f"         (type (simple-array {etype} (* * *)) a3) "
            f"         (type (mod {d0}) i) (type (mod {d1}) j) (type (mod {d2}) k) "
            f"         (type {etype} v0 v1) {opt}) "
            f"(let ((c 0)) "
            f"  (setf (aref a1 (progn (incf c) k)) (progn (incf c 2) v0)) "
            f"  (setf (aref a2 (progn (incf c 3) i) (progn (incf c 4) j)) v1) "
            f"  (setf (aref a3 i j k) (aref a1 k)) "
            f"  (setf (aref a2 1 2) v0) "
            f"  (setf (aref a3 2 1 3) v1) "
            f"  (list c (aref a1 k) (aref a2 i j) (aref a2 1 2) (aref a3 i j k) (aref a3 2 1 3))))"
        )
        return (
            f"(funcall (compile nil '{lam}) "
            f"(make-array {d2} :element-type '{etype} :initial-element {init}) "
            f"(make-array '({d0} {d1}) :element-type '{etype} :initial-element {init}) "
            f"(make-array '({d0} {d1} {d2}) :element-type '{etype} :initial-element {init}) "
            f"{i} {j} {k} {v0} {v1})"
        )

    def gen_mv_ctrl(self, opt: str) -> str:
        # Deep multiple values + non-local exits + tagbody/go + case
        n = self.rng.randint(-20, 20)
        lam = (
            f"(lambda (n) (declare (type fixnum n) {opt}) "
            f"(let ((trace nil)) "
            f"  (tagbody "
            f"     (when (< n 0) (push :neg trace) (go step2)) "
            f"     (push :nonneg trace) "
            f"   step2 "
            f"     (multiple-value-bind (q r) (truncate (+ n 37) 7) "
            f"       (push (list q r) trace) "
            f"       (when (zerop r) (go done))) "
            f"     (push (block blk "
            f"             (catch 'k "
            f"               (unwind-protect "
            f"                    (if (evenp n) (throw 'k (+ n 10)) (return-from blk (+ n 20))) "
            f"                 (push :cleanup trace)))) "
            f"           trace) "
            f"   done) "
            f"  (list (multiple-value-list (values n (+ n 1) (+ n 2) (+ n 3) (+ n 4))) "
            f"        (multiple-value-call #'list (values n) (values) (values 99 (+ n 5))) "
            f"        trace)))"
        )
        return f"(funcall (compile nil '{lam}) {n})"

    def generate_batch(self, count: int):
        cases = []
        opts = [
            "(optimize (speed 1) (safety 3))",
            "(optimize (speed 1) (safety 1))",
            "(optimize (speed 3) (safety 0))",
        ]
        gens = [
            ("int_tree", self.gen_int_tree),
            ("float_mix", self.gen_float_mix),
            ("array_mix", self.gen_array_mix),
            ("mv_ctrl", self.gen_mv_ctrl),
        ]
        for idx in range(count):
            cat, fn = gens[idx % len(gens)]
            opt = opts[(idx // len(gens)) % len(opts)]
            cases.append((idx, cat, opt, fn(opt)))
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
                out[int(parts[1])] = (parts[0], normalize_output(parts[2]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=500)
    ap.add_argument("--batches", type=int, default=10)
    ap.add_argument("--batch-size", type=int, default=180)
    args = ap.parse_args()

    total_cases = 0
    mismatches = []
    t0 = time.time()

    for b in range(args.batches):
        gen = Fuzz3(args.seed + b * 1000)
        cases = gen.generate_batch(args.batch_size)
        src = build_lisp_harness(cases)
        with tempfile.NamedTemporaryFile("w", suffix=".lisp", delete=False) as tf:
            tf.write(src)
            tf_path = tf.name
        try:
            ps = subprocess.run(TIMEOUT_LOCAL + [SBCL_BIN, "--script", tf_path], capture_output=True, text=True)
            pa = subprocess.run(TIMEOUT_LOCAL + [ARM64_CCL_BIN, "--no-init", "--batch", "--load", tf_path], capture_output=True, text=True)
            remote = f"/tmp/ccl_fuzz3_{os.getpid()}.lisp"
            px = subprocess.run(
                ["ssh", X86_CCL_SSH, f"cat > {remote} && timeout 60s {X86_CCL_BIN} --no-init --batch --load {remote}; rc=$?; rm -f {remote}; exit $rc"],
                input=src, capture_output=True, text=True,
            )
        finally:
            os.unlink(tf_path)

        rs = parse_output(ps.stdout)
        ra = parse_output(pa.stdout)
        rx = parse_output(px.stdout)

        bdiffs = 0
        for idx, cat, opt, expr in cases:
            total_cases += 1
            vs = rs.get(idx, ("MISSING", ""))
            va = ra.get(idx, ("MISSING", ""))
            vx = rx.get(idx, ("MISSING", ""))
            if not (vs == va == vx) or vs[0] != "RES":
                bdiffs += 1
                mismatches.append((b, idx, cat, opt, expr, vs, va, vx))

        print(
            f"[batch {b+1}/{args.batches}] cases={len(cases)} rc=(sbcl:{ps.returncode}, arm64:{pa.returncode}, x86:{px.returncode}) "
            f"parsed=({len(rs)}, {len(ra)}, {len(rx)}) diffs={bdiffs}",
            flush=True,
        )

    elapsed = time.time() - t0
    print(f"\nSUMMARY: total_cases={total_cases} total_diffs={len(mismatches)} elapsed={elapsed:.1f}s")
    for i, (b, idx, cat, opt, expr, vs, va, vx) in enumerate(mismatches[:30]):
        print(f"\n--- DIFF #{i+1} batch={b} idx={idx} cat={cat} opt={opt} ---")
        print(f"EXPR: {expr}")
        print(f"SBCL:  {vs}")
        print(f"ARM64: {va}")
        print(f"X8664: {vx}")


if __name__ == "__main__":
    main()
