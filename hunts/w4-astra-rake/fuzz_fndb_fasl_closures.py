#!/usr/bin/env python3
"""w4-ar-compilers: SBCL 2.6.10 / CCL 1.14 fndb / FASL / closure / level-0 differential harness.

Run with PYTHONDONTWRITEBYTECODE=1.  Writes only to /tmp/w4-ar-comp-* (locally) and
/tmp/w4-ar-comp-remote-* (on hbox, removed by the Lisp driver itself).

Suites
  sxhash    compile-file folding of SXHASH on literal instances / hash-tables / random-states
  coalesce  compile-file similarity coalescing of literal specialized float vectors (signed zeros)
  flush     (safety 3) for-effect deletion of FLUSHABLE calls (error elision; mostly UB-domain)
  arith     Python-exact oracle for bignum / ratio / float-coercion runtime (level-0) + compiled paths
  closures  random closure / setq / non-local-exit / dynamic-extent programs, cross-policy & cross-impl

Targets: sbcl ccl sbcl-x86 ccl-x86  (comma separated, or 'all')

Every generated Lisp program is free of ANSI UB: no type-declaration lies, no literal mutation,
dynamic-extent objects never escape, all arithmetic exact.
"""
import argparse, fractions, math, os, random, subprocess, sys, tempfile, json, re

TIMEOUT = "/opt/homebrew/bin/timeout"
LOCAL = {
    "sbcl": ["/opt/homebrew/bin/sbcl", "--script"],
    "ccl": ["/Users/ember/dev/ccl/darm64cl", "-Q", "-n", "-b"],
}
REMOTE = {
    "sbcl-x86": "/home/hbox/ca-sbcl-root/dl-2.6.10/sbcl-2.6.10-x86-64-linux/run-sbcl.sh --script",
    "ccl-x86": "/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64 -Q -n -b",
}

def lisp_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

DRIVER = r'''
(setf *print-pretty* nil *print-right-margin* 100000 *read-default-float-format* 'single-float)
(defvar *w4-src* %SRC%)
(defvar *w4-dir* (format nil "/tmp/w4-ar-comp-remote-~a/" (random 1000000000 (make-random-state t))))
(ensure-directories-exist *w4-dir*)
(defun w4-cleanup ()
  (dolist (f (directory (merge-pathnames "*.*" *w4-dir*))) (ignore-errors (delete-file f)))
  #+sbcl (ignore-errors (sb-ext:delete-directory *w4-dir*))
  #+ccl (ignore-errors (ccl:delete-directory *w4-dir*)))
(unwind-protect
  (let ((p (merge-pathnames "payload.lisp" *w4-dir*)))
    (with-open-file (s p :direction :output :if-exists :supersede) (write-string *w4-src* s))
    (handler-bind ((warning #'muffle-warning))
      (let ((*error-output* (make-broadcast-stream)))
        (load (compile-file p))))
    (funcall (intern "W4-MAIN" "CL-USER")))
  (w4-cleanup))
#+ccl (ccl:quit 0)
'''

def run_lisp(target, payload, timeout=300):
    drv = DRIVER.replace("%SRC%", lisp_str(payload))
    if target in LOCAL:
        fd, path = tempfile.mkstemp(prefix="w4-ar-comp-", suffix=".lisp", dir="/tmp")
        try:
            with os.fdopen(fd, "w") as f:
                f.write(drv)
            if target == "ccl":
                cmd = [TIMEOUT, "--kill-after=10s", f"{timeout}s"] + LOCAL[target] + ["-l", path]
            else:
                cmd = [TIMEOUT, "--kill-after=10s", f"{timeout}s"] + LOCAL[target] + [path]
            r = subprocess.run(cmd, capture_output=True, text=True)
        finally:
            os.unlink(path)
    else:
        cmd = [TIMEOUT, "--kill-after=10s", f"{timeout}s", "ssh", "hbox", REMOTE[target]]
        r = subprocess.run(cmd, input=drv, capture_output=True, text=True)
    return r.stdout + ("\n" + r.stderr if r.returncode else "")

# ---------------------------------------------------------------------------
# Suite: sxhash folding (SBCL fndb.lisp:1389 `(defknown (sxhash psxhash) (t) hash-code (foldable flushable))`)
SXHASH_SRC = r'''
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defstruct w4pt a b)
  (defmethod make-load-form ((x w4pt) &optional env) (make-load-form-saving-slots x :environment env))
  (defclass w4kls () ((s :initarg :s :initform 1)))
  (defmethod make-load-form ((x w4kls) &optional env) (make-load-form-saving-slots x :environment env)))
(declaim (notinline w4-opaque))
(defun w4-opaque (x) x)
(defmacro w4-both (lit)
  `(let ((x ',lit)) (list ',(type-of lit) (sxhash x) (funcall (w4-opaque #'sxhash) (w4-opaque x)))))
(defun w4-main ()
  (dolist (r (list (w4-both #.(make-hash-table)) (w4-both #.(make-random-state nil))
                   (w4-both #.(make-w4pt :a 1)) (w4-both #.(make-instance 'w4kls))
                   (w4-both #.(list (make-w4pt) 1)) (w4-both #.(make-pathname :name "x"))
                   (w4-both #.(make-symbol "G")) (w4-both "abc") (w4-both (1 2 3))))
    (format t "RESULT sxhash ~a ~s~%" (if (eql (second r) (third r)) "ok" "BUG") r)))
'''

# Suite: FASL / IR1 similarity coalescing (SBCL dump.lisp:135-141 `=` on unboxed float vectors)
COALESCE_SRC = r'''
(declaim (notinline w4-opaque))
(defun w4-opaque (x) x)
(defmacro w4v (et &rest xs) (make-array (length xs) :element-type et :initial-contents xs))
(defun w4-signs (v)
  (map 'list (lambda (e) (if (complexp e) (list (float-sign (realpart e)) (float-sign (imagpart e))) (float-sign e))) v))
(defmacro w4-pair (name et a b)
  `(list ',name (w4-signs (w4-opaque (w4v ,et ,@a))) (w4-signs (w4-opaque (w4v ,et ,@b)))
         ',(w4-signs (coerce a 'vector)) ',(w4-signs (coerce b 'vector))))
(defun w4-main ()
  (dolist (r (list (w4-pair df1 double-float (0d0) (-0d0))
                   (w4-pair df2 double-float (1d0 0d0) (1d0 -0d0))
                   (w4-pair df3 double-float (0d0 1d0) (-0d0 1d0))
                   (w4-pair df4 double-float (-0d0 2d0 3d0) (0d0 2d0 3d0))
                   (w4-pair sf1 single-float (0.0) (-0.0))
                   (w4-pair sf2 single-float (1.0 0.0) (1.0 -0.0))
                   (w4-pair sf3 single-float (0.0 1.0) (-0.0 1.0))
                   (w4-pair cdf1 (complex double-float) (#c(1d0 0d0)) (#c(1d0 -0d0)))
                   (w4-pair cdf2 (complex double-float) (#c(0d0 1d0)) (#c(-0d0 1d0)))
                   (w4-pair csf1 (complex single-float) (#c(1.0 0.0)) (#c(1.0 -0.0)))
                   (w4-pair csf2 (complex single-float) (#c(0.0 1.0)) (#c(-0.0 1.0)))))
    (format t "RESULT coalesce ~a ~s~%"
            (if (and (equal (second r) (fourth r)) (equal (third r) (fifth r))) "ok" "BUG") r)))
'''

# Suite: (safety 3) flushing of FLUSHABLE calls that signal on in-type args (contract check; UB-domain)
FLUSH_CASES = [
    ("(subseq s 0 e)", '"abc" 10'), ("(length s)", "'(1 2 . 3)"), ("(nth 5 s)", "'(1 . 2)"),
    ("(getf s e)", "'(1 2 3) 5"), ("(assoc e s)", "'(1 2) 5"), ("(member e s)", "'(1 . 2) 5"),
    ("(array-dimension s e)", "(vector 1) 5"), ("(array-row-major-index s e)", "(vector 1) 5"),
    ("(expt s e)", "0 -1"), ("(find-symbol s e)", '"X" "W4-NO-SUCH-PKG"'),
    ("(make-hash-table :test s)", "'w4-no-such-test"), ("(float s)", "(expt 10 400)"),
    ("(ash s e)", "1 (expt 2 70)"), ("(make-string 3 :element-type s)", "'fixnum"),
]
def flush_src():
    lines = ["(defun w4-main ()"]
    for form, args in FLUSH_CASES:
        params = "(s e)" if " e" in form or "e)" in form else "(s)"
        nargs = len(params.split()) 
        lines.append(f'''  (let ((f (compile nil '(lambda {params} (declare (optimize (safety 3)) (ignorable s{' e' if nargs==2 else ''})) {form} :ok)))
        (g (compile nil '(lambda {params} (declare (optimize (safety 3)) (ignorable s{' e' if nargs==2 else ''})) (list {form})))))
    (let ((a (handler-case (funcall f {args}) (error (c) (type-of c))))
          (b (handler-case (funcall g {args}) (error (c) (type-of c)))))
      (format t "RESULT flush ~a ~s ~s ~s~%" (if (and (eq a :ok) (symbolp b)) "ELIDED" "ok") {lisp_str(form)} a b)))''')
    lines.append(")")
    return "\n".join(lines)

# ---------------------------------------------------------------------------
# Suite: arithmetic with exact Python oracle
def round_to_float(q, p, emin, emax):
    """Round rational q to binary float with p-bit significand (round-half-even).
    Returns ('inf', sign) on overflow, else Fraction value."""
    q = fractions.Fraction(q)
    if q == 0:
        return fractions.Fraction(0)
    sign = -1 if q < 0 else 1
    a = abs(q)
    e = a.numerator.bit_length() - a.denominator.bit_length()
    # normalize: 2^e <= a < 2^(e+1)
    if fractions.Fraction(2) ** e > a:
        e -= 1
    if fractions.Fraction(2) ** (e + 1) <= a:
        e += 1
    e = max(e, emin)  # subnormal handling
    scale = fractions.Fraction(2) ** (e - p + 1)
    m = a / scale
    n = m.numerator // m.denominator
    rem = m - n
    if rem > fractions.Fraction(1, 2) or (rem == fractions.Fraction(1, 2) and n % 2 == 1):
        n += 1
    v = n * scale
    if v >= fractions.Fraction(2) ** (emax + 1):
        return ("inf", sign)
    return sign * v

def dfl(q): return round_to_float(q, 53, -1022, 1023)
def sfl(q): return round_to_float(q, 24, -126, 127)

def fmt_float(v):
    if isinstance(v, tuple):
        return "OVERFLOW"
    v = fractions.Fraction(v)
    return f"F{v.numerator}/{v.denominator}"

def fmt(x):
    if isinstance(x, bool):
        return "T" if x else "NIL"
    if isinstance(x, int):
        return str(x)
    if isinstance(x, fractions.Fraction):
        return str(x.numerator) if x.denominator == 1 else f"{x.numerator}/{x.denominator}"
    if isinstance(x, (list, tuple)):
        return "(" + " ".join(fmt(y) for y in x) + ")"
    return str(x)

def cl_floor(a, b):
    q = fractions.Fraction(a) / fractions.Fraction(b)
    n = q.numerator // q.denominator
    return [n, fractions.Fraction(a) - n * fractions.Fraction(b)]
def cl_ceiling(a, b):
    q = fractions.Fraction(a) / fractions.Fraction(b)
    n = -((-q.numerator) // q.denominator)
    return [n, fractions.Fraction(a) - n * fractions.Fraction(b)]
def cl_truncate(a, b):
    q = fractions.Fraction(a) / fractions.Fraction(b)
    n = q.numerator // q.denominator if q >= 0 else -((-q.numerator) // q.denominator)
    return [n, fractions.Fraction(a) - n * fractions.Fraction(b)]
def cl_round(a, b):
    q = fractions.Fraction(a) / fractions.Fraction(b)
    n = q.numerator // q.denominator
    r = q - n
    if r > fractions.Fraction(1, 2) or (r == fractions.Fraction(1, 2) and n % 2 == 1):
        n += 1
    return [n, fractions.Fraction(a) - n * fractions.Fraction(b)]
def ldb(s, p, n): return (n >> p) & ((1 << s) - 1)
def dpb(v, s, p, n):
    m = ((1 << s) - 1) << p
    return (n & ~m) | ((v << p) & m)
def logcount(n): return bin(n if n >= 0 else ~n).count("1")
def isqrt(n): return math.isqrt(n)
def lcm(a, b): return 0 if a == 0 or b == 0 else abs(a * b) // math.gcd(a, b)

def integer_pool(rng):
    ks = [0, 1, 2, 3, 7, 8, 15, 16, 29, 30, 31, 32, 33, 52, 53, 54, 59, 60, 61, 62, 63, 64, 65,
          66, 95, 96, 97, 127, 128, 129, 191, 192, 193, 255, 256, 257, 320, 511, 512, 1000]
    pool = set()
    for k in ks:
        for d in (-2, -1, 0, 1, 2):
            v = (1 << k) + d
            pool.add(v); pool.add(-v)
    for _ in range(60):
        b = rng.choice([40, 64, 100, 128, 200, 300, 600])
        v = rng.getrandbits(b)
        pool.add(v); pool.add(-v)
    # limb patterns
    for k in (64, 128, 192, 256):
        pool.add((1 << k) - (1 << (k - 1)))
        pool.add(((1 << k) - 1) << 64)
        pool.add(-(((1 << k) - 1) << 64))
        pool.add((1 << (k + 63)) | 1)
    return sorted(pool)

ARITH_OPS = {
    # name: (arity, lisp expression with a b c, python fn or None, domain filter)
    "add": (2, "(+ a b)", lambda a, b: a + b, None),
    "sub": (2, "(- a b)", lambda a, b: a - b, None),
    "mul": (2, "(* a b)", lambda a, b: a * b, None),
    "div": (2, "(/ a b)", lambda a, b: fractions.Fraction(a, b), lambda a, b: b != 0),
    "truncate": (2, "(multiple-value-list (truncate a b))", cl_truncate, lambda a, b: b != 0),
    "floor": (2, "(multiple-value-list (floor a b))", cl_floor, lambda a, b: b != 0),
    "ceiling": (2, "(multiple-value-list (ceiling a b))", cl_ceiling, lambda a, b: b != 0),
    "round": (2, "(multiple-value-list (round a b))", cl_round, lambda a, b: b != 0),
    "mod": (2, "(mod a b)", lambda a, b: cl_floor(a, b)[1], lambda a, b: b != 0),
    "rem": (2, "(rem a b)", lambda a, b: cl_truncate(a, b)[1], lambda a, b: b != 0),
    "gcd": (2, "(gcd a b)", lambda a, b: math.gcd(a, b), None),
    "lcm": (2, "(lcm a b)", lcm, None),
    "logand": (2, "(logand a b)", lambda a, b: a & b, None),
    "logior": (2, "(logior a b)", lambda a, b: a | b, None),
    "logxor": (2, "(logxor a b)", lambda a, b: a ^ b, None),
    "logeqv": (2, "(logeqv a b)", lambda a, b: ~(a ^ b), None),
    "logandc2": (2, "(logandc2 a b)", lambda a, b: a & ~b, None),
    "lognand": (2, "(lognand a b)", lambda a, b: ~(a & b), None),
    "logtest": (2, "(logtest a b)", lambda a, b: (a & b) != 0, None),
    "lt": (2, "(< a b)", lambda a, b: a < b, None),
    "eqn": (2, "(= a b)", lambda a, b: a == b, None),
    "max": (2, "(max a b)", lambda a, b: max(a, b), None),
    "ash": (2, "(ash a b)", lambda a, b: a << b if b >= 0 else a >> (-b), lambda a, b: -2000 < b < 2000),
    "logbitp": (2, "(logbitp b a)", lambda a, b: ((a >> b) & 1) == 1, lambda a, b: 0 <= b < 3000),
    "ldb": (3, "(ldb (byte b c) a)", lambda a, b, c: ldb(b, c, a), lambda a, b, c: 0 <= b < 700 and 0 <= c < 700),
    "dpb": (3, "(dpb a (byte b c) a)", lambda a, b, c: dpb(a, b, c, a), lambda a, b, c: 0 <= b < 700 and 0 <= c < 700),
    "mask-field": (3, "(mask-field (byte b c) a)", lambda a, b, c: a & (((1 << b) - 1) << c), lambda a, b, c: 0 <= b < 700 and 0 <= c < 700),
    "logcount": (1, "(logcount a)", logcount, None),
    "integer-length": (1, "(integer-length a)", lambda a: (a if a >= 0 else ~a).bit_length(), None),
    "isqrt": (1, "(isqrt a)", isqrt, lambda a: a >= 0),
    "lognot": (1, "(lognot a)", lambda a: ~a, None),
    "abs": (1, "(abs a)", abs, None),
    "neg": (1, "(- a)", lambda a: -a, None),
    "evenp": (1, "(evenp a)", lambda a: a % 2 == 0, None),
    "sqr": (1, "(expt a 2)", lambda a: a * a, None),
    "cube": (1, "(expt a 3)", lambda a: a ** 3, None),
    "expt-neg": (1, "(expt a -2)", lambda a: fractions.Fraction(1, a * a), lambda a: a != 0),
    "dfloat": (1, "(w4-ff (float a 1d0))", lambda a: fmt_float(dfl(a)), None),
    "sfloat": (1, "(w4-ff (float a 1f0))", lambda a: fmt_float(sfl(a)), None),
    # ratio / float mixed (exact oracle)
    "rdfloat": (2, "(w4-ff (float (/ a b) 1d0))", lambda a, b: fmt_float(dfl(fractions.Fraction(a, b))), lambda a, b: b != 0),
    "rsfloat": (2, "(w4-ff (float (/ a b) 1f0))", lambda a, b: fmt_float(sfl(fractions.Fraction(a, b))), lambda a, b: b != 0),
    "r+r": (3, "(+ (/ a b) (/ b c))", lambda a, b, c: fractions.Fraction(a, b) + fractions.Fraction(b, c), lambda a, b, c: b != 0 and c != 0),
    "r*r": (3, "(* (/ a b) (/ c b))", lambda a, b, c: fractions.Fraction(a, b) * fractions.Fraction(c, b), lambda a, b, c: b != 0),
    "rfloor": (3, "(multiple-value-list (floor (/ a b) (/ c 7)))", lambda a, b, c: cl_floor(fractions.Fraction(a, b), fractions.Fraction(c, 7)), lambda a, b, c: b != 0 and c != 0),
    "rround": (2, "(multiple-value-list (round (/ a b)))", lambda a, b: cl_round(fractions.Fraction(a, b), 1), lambda a, b: b != 0),
    "rlt": (3, "(< (/ a b) (/ c 3))", lambda a, b, c: fractions.Fraction(a, b) < fractions.Fraction(c, 3), lambda a, b, c: b != 0),
    # exact rational/float comparisons (CLHS 12.1.4.1.1: rational of the float, exact compare)
    "cmp-df": (2, "(let ((d (float b 1d0))) (list (= a d) (< a d) (> a d)))",
               lambda a, b: [a == dfl(b), a < dfl(b), a > dfl(b)],
               lambda a, b: not isinstance(dfl(b), tuple)),
    "rational-df": (1, "(rational (float a 1d0))", lambda a: dfl(a), lambda a: not isinstance(dfl(a), tuple)),
    "decode-df": (1, "(multiple-value-list (integer-decode-float (float a 1d0)))", None, None),
}

def arith_cases(rng, n):
    pool = integer_pool(rng)
    small = [x for x in pool if abs(x) < 2000]
    cases = []
    names = [k for k, v in ARITH_OPS.items() if v[2] is not None]
    while len(cases) < n:
        name = rng.choice(names)
        ar, expr, fn, dom = ARITH_OPS[name]
        if name in ("ash", "logbitp"):
            args = [rng.choice(pool), rng.choice(small + list(range(-130, 260)))]
        elif name in ("ldb", "dpb", "mask-field"):
            args = [rng.choice(pool), rng.randrange(0, 260), rng.randrange(0, 260)]
        else:
            args = [rng.choice(pool) for _ in range(ar)]
        if dom and not dom(*args):
            continue
        try:
            exp = fn(*args)
        except (ZeroDivisionError, ValueError, OverflowError):
            continue
        cases.append((name, args, fmt(exp) if not isinstance(exp, str) else exp))
    return cases

ARITH_PRELUDE = r'''
(defun w4-ff (x) (if (and (floatp x) (or (> (abs x) most-positive-double-float))) "OVERFLOW"
                   (let ((r (rational x))) (format nil "F~a/~a" (numerator r) (denominator r)))))
(defun w4-fmt (x)
  (cond ((eq x t) "T") ((null x) "NIL") ((stringp x) x)
        ((integerp x) (format nil "~d" x))
        ((rationalp x) (format nil "~d/~d" (numerator x) (denominator x)))
        ((consp x) (format nil "(~{~a~^ ~})" (mapcar #'w4-fmt x)))
        (t (format nil "?~s" x))))
'''

def arith_src(cases):
    out = [ARITH_PRELUDE]
    ops_used = sorted(set(c[0] for c in cases))
    for name in ops_used:
        ar, expr, fn, dom = ARITH_OPS[name]
        params = ["a", "b", "c"][:ar]
        decl = f"(declare (ignorable {' '.join(params)}))"
        pname = re.sub(r'[^a-z0-9]', '-', name)
        # generic (interpreted-like via notinline full calls inside a safety 3 lambda) and typed-compiled
        out.append(f"(defun w4-op-{pname} ({' '.join(params)}) (declare (optimize (safety 3) (speed 0) (debug 3))) {decl} {expr})")
        out.append(f"(defun w4-opt-{pname} ({' '.join(params)}) (declare (optimize (safety 3) (speed 3)) (type integer {' '.join(params)})) {decl} {expr})")
    out.append("(defparameter *w4-cases* '(")
    for i, (name, args, exp) in enumerate(cases):
        pname = re.sub(r'[^a-z0-9]', '-', name)
        out.append(f"  ({i} w4-op-{pname} w4-opt-{pname} ({' '.join(str(a) for a in args)}) {lisp_str(exp)})")
    out.append("))")
    out.append(r'''
(defun w4-main ()
  (let ((n 0) (bad 0))
    (dolist (c *w4-cases*)
      (destructuring-bind (i f g args exp) c
        (dolist (fn (list f g))
          (incf n)
          (let ((got (handler-case (w4-fmt (apply fn args))
                       (floating-point-overflow () "OVERFLOW")
                       (error (e) (format nil "ERR:~a" (type-of e))))))
            (unless (string= got exp)
              (incf bad)
              (format t "RESULT arith BUG ~a ~a ~a got=~a exp=~a~%" i fn args got exp))))))
    (format t "RESULT arith-summary checks=~a mismatches=~a~%" n bad)))
''')
    return "\n".join(out)

# ---------------------------------------------------------------------------
# Suite: random closure / non-local exit / dynamic-extent programs
class Gen:
    def __init__(self, rng):
        self.rng = rng
        self.n = 0
    def fresh(self, p):
        self.n += 1
        return f"{p}{self.n}"
    def expr(self, env, fenv, blocks, tags, depth):
        r = self.rng
        if depth <= 0 or r.random() < 0.15:
            if env and r.random() < 0.7:
                return r.choice(env)
            return str(r.randint(-5, 9))
        k = r.randrange(22)
        e = lambda d=depth - 1: self.expr(env, fenv, blocks, tags, d)
        if k == 0:
            return f"(+ {e()} {e()})"
        if k == 1:
            return f"(- {e()} {e()})"
        if k == 2 and env:
            v = r.choice(env)
            return f"(setq {v} {e()})"
        if k == 3 and env:
            v = r.choice(env)
            return f"(incf {v} {e()})"
        if k == 4:
            v = self.fresh("v")
            return f"(let (({v} {e()})) {self.expr(env + [v], fenv, blocks, tags, depth - 1)})"
        if k == 5:
            f = self.fresh("f"); p = self.fresh("p")
            body = self.expr(env + [p], fenv, blocks, tags, depth - 1)
            dx = f"(declare (dynamic-extent #'{f}))" if r.random() < 0.4 else ""
            inl = f"(declare (notinline {f}))" if r.random() < 0.3 else ""
            rest = self.expr(env, fenv + [f], blocks, tags, depth - 1)
            return f"(flet (({f} ({p}) {body})) {dx} {inl} {rest})"
        if k == 6:
            f = self.fresh("g"); p = self.fresh("p")
            # bounded recursion via counter argument
            body = f"(if (<= {p} 0) {self.expr(env + [p], fenv, blocks, tags, depth - 1)} (+ {p} ({f} (- {p} 1))))"
            rest = self.expr(env, fenv + [f], blocks, tags, depth - 1)
            return f"(labels (({f} ({p}) (if (> {p} 3) ({f} 3) {body}))) {rest})"
        if k == 7 and fenv:
            f = r.choice(fenv)
            return f"({f} {e()})"
        if k == 8:
            b = self.fresh("b")
            return f"(block {b} {self.expr(env, fenv, blocks + [b], tags, depth - 1)})"
        if k == 9 and blocks:
            b = r.choice(blocks)
            return f"(return-from {b} {e()})"
        if k == 10:
            return f"(if (> {e()} {e()}) {e()} {e()})"
        if k == 11:
            return f"(unwind-protect {e()} (w4-log {e()}))"
        if k == 12:
            t = self.fresh(":t")
            return f"(catch '{t} {self.expr(env, fenv, blocks, tags + [t], depth - 1)})"
        if k == 13 and tags:
            t = r.choice(tags)
            return f"(throw '{t} {e()})"
        if k == 14:
            return f"(multiple-value-prog1 {e()} {e()})"
        if k == 15:
            v = self.fresh("c")
            return f"(let (({v} {e()})) (funcall (lambda () (setq {v} (+ {v} {e()})) {v})) {v})"
        if k == 16:
            # closure stored then called after mutation
            v = self.fresh("m"); f = self.fresh("h")
            dx = f"(declare (dynamic-extent {f}))" if r.random() < 0.4 else ""
            return (f"(let* (({v} {e()}) ({f} (lambda (q) (setq {v} (+ {v} q)) {v}))) {dx} "
                     f"(w4-log (funcall {f} {e()})) (setq {v} (* 2 {v})) (funcall {f} 1))")
        if k == 17:
            v = self.fresh("i"); acc = self.fresh("a")
            return f"(let (({acc} 0)) (dotimes ({v} 3 {acc}) (setq {acc} (+ {acc} {v} {self.expr(env + [acc], fenv, blocks, tags, depth - 1)}))))"
        if k == 18:
            # tagbody/go loop with closures capturing loop var
            v = self.fresh("j"); acc = self.fresh("s"); fs = self.fresh("fs")
            return (f"(let (({v} 0) ({acc} 0) ({fs} nil)) (tagbody top (when (< {v} 3) "
                     f"(push (lambda () (+ {v} {acc})) {fs}) (incf {acc} {self.expr(env + [v], fenv, blocks, tags, depth - 1)}) (incf {v}) (go top))) "
                     f"(reduce #'+ (mapcar #'funcall {fs})))")
        if k == 19:
            # &rest dynamic-extent list consumed locally
            f = self.fresh("r"); rr = self.fresh("rs")
            return f"(flet (({f} (&rest {rr}) (declare (dynamic-extent {rr})) (reduce #'+ {rr}))) ({f} {e()} {e()} {e()}))"
        if k == 20:
            # optional/key with initforms referencing mutated closed-over variables
            v = self.fresh("o"); f = self.fresh("k")
            return (f"(let (({v} {e()})) (flet (({f} (&optional (x (incf {v})) &key (y (* 2 {v}))) (+ x y {v}))) "
                     f"(+ ({f}) ({f} {e()}) ({f} 1 :y {e()}))))")
        if k == 21:
            return f"(multiple-value-bind (q r) (floor {e()} 3) (+ q r))"
        return f"(* {e()} 1)"

POLICIES = [
    "(optimize (speed 0) (safety 3) (debug 3))",
    "(optimize (speed 1) (safety 1) (debug 1))",
    "(optimize (speed 3) (safety 3) (debug 0))",
    "(optimize (speed 3) (safety 0) (debug 0) (space 0))",
    "(optimize (speed 2) (safety 2) (debug 0) (space 0))",
]

def closures_src(rng, n, depth):
    g = Gen(rng)
    forms = []
    for i in range(n):
        x = g.fresh("x")
        body = g.expr([x], [], [], [], depth)
        forms.append((x, body))
    out = [r'''
(defvar *w4-log* nil)
(defun w4-log (x) (push x *w4-log*) x)
(defun w4-run (fn arg)
  (setf *w4-log* nil)
  (let ((r (handler-case (multiple-value-list (funcall fn arg))
             (error (e) (list :error (type-of e))))))
    (list r (reverse *w4-log*))))
(defparameter *w4-forms* '(''']
    for x, body in forms:
        out.append(f"  (({x}) {body})")
    out.append("))")
    out.append("(defparameter *w4-policies* '(" + " ".join(POLICIES) + "))")
    out.append(r'''
(defun w4-main ()
  (let ((n 0) (bad 0) (i 0))
    (dolist (f *w4-forms*)
      (let* ((ll (first f)) (body (second f))
             (ref #+sbcl (let ((sb-ext:*evaluator-mode* :interpret))
                           (handler-case (w4-run (eval `(lambda ,ll ,body)) 3) (error (e) (list :ierr (type-of e)))))
                  #-sbcl nil)
             (results (mapcar (lambda (pol)
                                (handler-case
                                    (let ((fn (let ((*error-output* (make-broadcast-stream)))
                                                (handler-bind ((warning #'muffle-warning))
                                                  (compile nil `(lambda ,ll (declare ,pol) ,body))))))
                                      (w4-run fn 3))
                                  (error (e) (list :compile-error (type-of e)))))
                              *w4-policies*)))
        (incf n (length results))
        (let ((base (or ref (first results))))
          (unless (every (lambda (r) (equal r base)) results)
            (incf bad)
            (format t "RESULT closures BUG ~a ref=~s got=~s form=~s~%" i base results f)))
        (format t "RESULT closures-val ~a ~s~%" i (or ref (first results))))
      (incf i))
    (format t "RESULT closures-summary forms=~a runs=~a mismatching-forms=~a~%" (length *w4-forms*) n bad)))
''')
    return "\n".join(out)

# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", default="all")
    ap.add_argument("--target", default="sbcl,ccl")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--cases", type=int, default=4000)
    ap.add_argument("--depth", type=int, default=5)
    ap.add_argument("--show", action="store_true", help="print all RESULT lines")
    a = ap.parse_args()
    targets = ["sbcl", "ccl", "sbcl-x86", "ccl-x86"] if a.target == "all" else a.target.split(",")
    suites = ["sxhash", "coalesce", "flush", "arith", "closures"] if a.suite == "all" else a.suite.split(",")
    stats = {}
    closure_vals = {}
    for suite in suites:
        rng = random.Random(a.seed)
        if suite == "sxhash":
            src = SXHASH_SRC
        elif suite == "coalesce":
            src = COALESCE_SRC
        elif suite == "flush":
            src = flush_src()
        elif suite == "arith":
            src = arith_src(arith_cases(rng, a.cases))
        elif suite == "closures":
            src = closures_src(rng, a.cases, a.depth)
        for t in targets:
            if suite == "flush" and t.startswith("ccl") and False:
                continue
            out = run_lisp(t, src, timeout=600)
            lines = [l for l in out.splitlines() if l.startswith("RESULT")]
            bugs = [l for l in lines if " BUG " in l or " ELIDED " in l]
            summ = [l for l in lines if "summary" in l]
            stats[(suite, t)] = (len(lines), len(bugs))
            if suite == "closures":
                closure_vals[t] = {l.split()[2]: l.split(None, 3)[3] for l in lines if l.startswith("RESULT closures-val")}
            print(f"== {suite} @ {t}: {len(lines)} result lines, {len(bugs)} flagged")
            for l in (lines if a.show else bugs + summ):
                if not l.startswith("RESULT closures-val"):
                    print("  " + l[:600])
            if not lines:
                print("  (no output) " + out[-1500:])
    if len(closure_vals) > 1:
        ts = list(closure_vals)
        base = closure_vals[ts[0]]
        diff = 0
        for t in ts[1:]:
            for k, v in base.items():
                if closure_vals[t].get(k) != v:
                    diff += 1
                    print(f"  CROSS-IMPL closures form {k}: {ts[0]}={v[:200]} {t}={closure_vals[t].get(k, '')[:200]}")
        print(f"== closures cross-impl diffs: {diff}")
    print("STATS", json.dumps({f"{k[0]}@{k[1]}": v for k, v in stats.items()}))

if __name__ == "__main__":
    main()
