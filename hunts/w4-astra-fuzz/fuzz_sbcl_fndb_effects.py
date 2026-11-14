#!/usr/bin/env python3
"""fuzz_sbcl_fndb_effects.py -- SBCL fndb.lisp effect-attribute differential fuzzer.

Pipeline
  1. ENUMERATE: ask the live SBCL image which COMMON-LISP functions carry the
     `flushable` / `unsafely-flushable` / `foldable` / `movable` IR1 attributes
     (sb-c::fun-info-attributes, i.e. src/compiler/fndb.lisp `defknown`s) and
     their lambda lists.
  2. FLUSH SWEEP: for random (fn, args) tuples drawn from a pool of *fresh*
     argument constructors (dotted/circular lists, out-of-range :start/:end,
     domain errors, wrong types, ...) compile three lambdas
        DISC : (speed 3)(safety 3)            (fn a0 ..) :done      ; value discarded
        USED : (speed 3)(safety 3)            (list (fn a0 ..))     ; value used
        REF  : (speed 0)(safety 3) notinline  (list (fn a0 ..))     ; reference
     and classify  ELIDED (REF errs, DISC returns), SPURIOUS (REF ok, DISC errs),
     VALUE (USED /= REF), ERRCLASS (USED errs /= REF errs), HANG/CRASH.
     Every ELIDED / HANG / CRASH outcome is cross-referenced against an embedded
     table of CLHS "Exceptional Situations" text (scraped from the HyperSpec):
     only functions whose page says "Should signal" (CLHS 1.4.2: *must* signal
     in safe code) -- NOT "should be prepared to signal" (lazy check allowed),
     NOT "None" (1.4.4.3: consequences undefined) -- are flagged MANDATED.
  3. MUTATION SWEEP: movable/foldable reads (length, car, aref, char, fill-pointer,
     eql-on-car, position, find, ...) repeated across intervening state mutation
     (rplaca, setf aref, vector-push, (setf fill-pointer), fill, replace, nreverse,
     sort, setf char, delete) under (speed 3)(safety 3), (speed 1)(safety 1) and
     (speed 0)(safety 3)+notinline -- any disagreement is a hoisting / CSE /
     constraint-propagation bug candidate.
  4. CROSS-CHECK: the same case files run on CCL 1.14 (darm64cl), optionally on
     hbox x86-64 SBCL / CCL (--hbox), so implementation-specific elisions and
     mandated-error violations are separated from shared behaviour.

Robustness: each case prints B|idx before and R|idx|... after; if the Lisp dies
(e.g. SBCL "Heap exhausted, game over") the driver records CRASH for that case
and restarts the image from idx+1.  Per-call timeouts: sb-ext:with-timeout on
SBCL, a watchdog thread + process-kill on CCL.

All temporary files live in mktemp -d /tmp/w4-astra-host-XXXX and are removed
at exit (use --keep to retain).

Usage:  fuzz_sbcl_fndb_effects.py [--seed N] [--cases N] [--mode all|flush|mutation]
                                  [--impl sbcl|ccl|both] [--hbox] [--keep] [--json OUT]
"""
import argparse
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter, defaultdict

SBCL = "/opt/homebrew/bin/sbcl"
CCL = "/Users/ember/dev/ccl/darm64cl"
TIMEOUT = "/opt/homebrew/bin/timeout"
HBOX_SBCL = "/home/hbox/ca-sbcl-root/dl-2.6.10/sbcl-2.6.10-x86-64-linux/run-sbcl.sh"
HBOX_CCL = "/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64"

# ---------------------------------------------------------------------------
# CLHS mandate table (scraped from https://www.lispworks.com/documentation/HyperSpec
# "Exceptional Situations" of every function page, 2026-11-14).  Only *strict*
# "Should signal" clauses (CLHS 1.4.2) are listed; "should be prepared to signal"
# entries are deliberately excluded (lazy checking permitted).
#   kind 'improper' : must signal type-error when the sequence/list arg is not
#                     proper (dotted / circular), resp. per-function wording
#   kind 'type'     : must signal type-error when an argument is of the wrong type
#   kind 'index'    : must signal type-error on an invalid sequence index
# ---------------------------------------------------------------------------
MANDATE_IMPROPER = {
    # fn: (which inputs count as violations, CLHS wording)
    "butlast": ("circular", "Should signal an error of type type-error if list is not a proper list or a dotted list."),
    "nbutlast": ("circular", "Should signal an error of type type-error if list is not a proper list or a dotted list."),
    "remove-duplicates": ("dotted|circular", "Should signal an error of type type-error if sequence is not a proper sequence."),
    "delete-duplicates": ("dotted|circular", "Should signal an error of type type-error if sequence is not a proper sequence."),
    "every": ("dotted|circular", "Should signal type-error if ... any subsequent argument is not a proper sequence."),
    "some": ("dotted|circular", "Should signal type-error if ... any subsequent argument is not a proper sequence."),
    "notany": ("dotted|circular", "Should signal type-error if ... any subsequent argument is not a proper sequence."),
    "notevery": ("dotted|circular", "Should signal type-error if ... any subsequent argument is not a proper sequence."),
    "list-length": ("dotted", "Should signal an error of type type-error if list is not a proper list or a circular list."),
    "values-list": ("dotted|circular", "Should signal type-error if its argument is not a proper list."),
}
MANDATE_INDEX = {"elt": "Should signal an error of type type-error if index is not a valid sequence index for sequence."}
MANDATE_TYPE = set("""acos acosh adjustable-array-p alpha-char-p alphanumericp array-dimensions array-element-type
array-has-fill-pointer-p array-rank array-total-size ash asin asinh atan atanh boole both-case-p boundp butlast car cdr
char-code char-downcase char-name char-upcase copy-symbol cos cosh endp evenp gcd get graphic-char-p
hash-table-rehash-size hash-table-rehash-threshold hash-table-size hash-table-test imagpart integer-length isqrt last
lcm logand logandc1 logandc2 logbitp logcount logeqv logior lognand lognor lognot logorc1 logorc2 logtest logxor
lower-case-p make-list make-random-state make-symbol make-synonym-stream max min minusp name-char oddp pathname-device
pathname-directory pathname-host pathname-name pathname-type pathname-version phase plusp rationalize realpart sin sinh
special-operator-p sqrt standard-char-p symbol-name symbol-package symbol-plist tan tanh upper-case-p zerop""".split())

# Functions never sampled (side effects on the environment, non-determinism, or
# allocation sized by an argument that could exhaust the heap for reasons that
# are resource limits rather than semantics).
SKIP = set("""apropos-list list-all-packages user-homedir-pathname machine-instance machine-type machine-version
software-type software-version lisp-implementation-type lisp-implementation-version long-site-name short-site-name
get-internal-real-time get-internal-run-time get-universal-time get-decoded-time listen make-synonym-stream
find-all-symbols random make-random-state maphash file-string-length make-string-input-stream
make-string-output-stream stream-external-format sxhash class-of type-of""".split())
SMALL_INT_ONLY = set("make-list make-array make-string make-sequence ash expt make-hash-table isqrt "
                     "lcm gcd * scale-float dpb deposit-field byte ldb mask-field ldb-test boole".split())

# ---------------------------------------------------------------------------
# value pool: (lisp-constructor-expression, tags).  Every expression constructs
# a FRESH object at call time, so destructive functions never touch literals.
# ---------------------------------------------------------------------------
POOL = [
    ("0", "int small"), ("1", "int small"), ("2", "int small"), ("3", "int small"), ("5", "int small"),
    ("10", "int small"), ("-1", "int small neg"), ("-5", "int small neg"), ("100", "int small"),
    ("most-positive-fixnum", "int big"), ("(1+ most-positive-fixnum)", "int big"), ("(- (expt 2 70))", "int big"),
    ("0.0d0", "float"), ("-0.0d0", "float"), ("1.5", "float"), ("-2.5d0", "float"), ("1d300", "float"),
    ("1/3", "ratio"), ("#c(1 2)", "complex"), ("#c(0.0d0 1.0d0)", "complex"),
    ("#\\a", "char"), ("#\\Z", "char"), ("#\\7", "char"), ("(code-char 955)", "char"), ("#\\Space", "char"),
    ("(copy-seq \"abc\")", "string"), ("(make-string 0)", "string"), ("(copy-seq \"Hello World\")", "string"),
    ("(make-array 3 :element-type 'character :fill-pointer 2 :initial-element #\\q)", "string fp"),
    ("(vector 1 2 3)", "vector"), ("(vector)", "vector"), ("(vector 3 1 2 1)", "vector"),
    ("(make-array 4 :fill-pointer 2 :initial-element 7)", "vector fp"),
    ("(make-array 5 :element-type 'bit :initial-element 1)", "bitvector"),
    ("(make-array '(2 3) :initial-element 0)", "array2d"),
    ("nil", "list sym"), ("(list 1 2 3)", "list"), ("(list 1 1 2 2)", "list"), ("(list 3 1 2)", "list"),
    ("(list* 1 2 3)", "dotted"), ("(list* 1 1 2)", "dotted"), ("(cons 1 2)", "dotted"),
    ("(w4-circ)", "circular"),
    ("(list (cons 'a 1) (cons 'b 2))", "list alist"), ("(list (cons 'a 1) 3)", "list badalist"),
    ("(list :a 1 :b)", "list oddplist"), ("(list :a 1 :b 2)", "list plist"),
    ("(list (list 1 2) (list 3 (list 4)))", "list tree"),
    ("'foo", "sym"), ("t", "sym"), (":start", "sym kw"), ("(make-symbol \"G\")", "sym"),
    ("#'+", "fn"), ("#'car", "fn"), ("#'identity", "fn"), ("#'eql", "fn"), ("#'<", "fn"), ("'car", "fn sym"),
    ("(make-hash-table)", "hash"), ("(byte 3 1)", "bytespec"), ("(pathname \"/tmp/w4x.lisp\")", "pathname"),
    ("*package*", "package"), ("\"CL-USER\"", "string pkgname"),
]
INDEX_POOL = ["0", "1", "2", "5", "10", "-1", "nil", "1.5", "most-positive-fixnum"]
KEY_FN_POOL = ["#'identity", "#'eql", "#'equal", "#'<", "#'car", "nil", "'evenp"]

LISP_PRELUDE = r"""
(in-package :cl-user)
#+sbcl (declaim (sb-ext:muffle-conditions sb-ext:compiler-note style-warning warning))
(defvar *w4-out* *standard-output*)
(defvar *w4-start* (let ((s #+sbcl (sb-ext:posix-getenv "W4_START") #+ccl (ccl:getenv "W4_START")))
                     (if (and s (plusp (length s))) (parse-integer s) 0)))
(defun w4-circ () (let ((l (list 1 2 3))) (setf (cdr (last l)) l) l))
(defun w4-scrub (s)
  ;; strip addresses / identities from unreadable printed reps
  (let ((out (make-string-output-stream)) (i 0) (n (length s)))
    (loop while (< i n)
          do (let ((c (char s i)))
               (cond ((and (char= c #\{) (find #\} s :start i))
                      (setf i (1+ (position #\} s :start i))) (write-string "{}" out))
                     ((member c '(#\Newline #\Return #\|)) (write-char #\Space out) (incf i))
                     (t (write-char c out) (incf i)))))
    (get-output-stream-string out)))
(defun w4-canon (x)
  (let ((*print-circle* t) (*print-readably* nil) (*print-pretty* nil) (*print-length* 40) (*print-level* 8)
        (*package* (find-package :cl-user)))
    (w4-scrub (typecase x
                ((or hash-table function package stream random-state) (format nil "#<~a>" (type-of x)))
                (t (prin1-to-string x))))))
(defun w4-cond-name (c) (format nil "ERR:~a~a" (if (typep c 'type-error) "TE:" "")
                                (let ((*package* (find-package :keyword))) (prin1-to-string (type-of c)))))
(defun w4-eval-thunk (thunk)
  (handler-case (let ((vals (multiple-value-list (funcall thunk))))
                  (format nil "OK:~{~a~^ ~}" (mapcar #'w4-canon vals)))
    (error (c) (w4-cond-name c))
    (storage-condition (c) (format nil "STORAGE:~a" (type-of c)))))
#+sbcl
(defun w4-timed (thunk &optional (secs 2))
  (handler-case (sb-ext:with-timeout secs (w4-eval-thunk thunk))
    (sb-ext:timeout () "TIMEOUT")))
#+ccl
(defun w4-timed (thunk &optional (secs 2))
  (let* ((result "TIMEOUT") (done nil)
         (p (ccl:process-run-function "w4" (lambda () (setf result (w4-eval-thunk thunk)) (setf done t)))))
    (ccl:process-wait-with-timeout "w4" (* secs ccl:*ticks-per-second*) (lambda () done))
    (unless done (ignore-errors (ccl:process-kill p)) (sleep 0.05))
    result))
(defun w4-compile (form)
  (handler-case
      (let ((*error-output* (make-broadcast-stream)))
        (handler-bind ((warning #'muffle-warning))
          (multiple-value-bind (f) (compile nil form) f)))
    (error (c) (format nil "COMPILE-ERR:~a" (type-of c)))))
(defmacro w4-case (idx kind &rest lambdas-and-argsfn)
  ;; LAMBDAS: quoted lambda forms; last element = arg-constructor lambda form
  `(when (>= ,idx *w4-start*)
     (format *w4-out* "B|~d~%" ,idx) (finish-output *w4-out*)
     (let* ((forms ',(butlast lambdas-and-argsfn))
            (argsfn ,(car (last lambdas-and-argsfn)))
            (res (mapcar (lambda (form)
                           (let ((f (w4-compile form)))
                             (if (functionp f)
                                 (w4-timed (lambda () (apply f (funcall argsfn))))
                                 f)))
                         forms)))
       (format *w4-out* "R|~d|~a|~{~a~^|~}~%" ,idx ,kind res)
       (finish-output *w4-out*))))
"""

ENUM_LISP = r"""
(in-package :cl-user)
(let ((rows nil))
  (do-external-symbols (s :cl)
    (when (and (fboundp s) (not (macro-function s)) (not (special-operator-p s)))
      (let ((info (sb-int:info :function :info s)))
        (when info
          (let ((attrs (sb-c::decode-ir1-attributes (sb-c::fun-info-attributes info))))
            (push (list (string-downcase (symbol-name s))
                        (mapcar (lambda (a) (string-downcase (symbol-name a))) attrs)
                        (let ((*package* (find-package :keyword)))
                          (prin1-to-string (sb-kernel:%fun-lambda-list (fdefinition s)))))
                  rows))))))
  (dolist (r (sort rows #'string< :key #'first))
    (format t "FN|~a|~{~a~^,~}|~a~%" (first r) (second r) (substitute #\Space #\Newline (third r)))))
;;; Per-position type compatibility of the value pool against the SBCL ftype
;;; (so the sampler can pass the ftype cast and reach the function's own checks).
(defun w4-circ () (let ((l (list 1 2 3))) (setf (cdr (last l)) l) l))
(let ((pool (mapcar (lambda (s) (ignore-errors (eval (read-from-string s)))) *w4-pool-exprs*)))
  (do-external-symbols (s :cl)
    (when (and (fboundp s) (not (macro-function s)) (not (special-operator-p s)) (sb-int:info :function :info s))
      (let ((ty (ignore-errors (sb-int:info :function :type s))))
        (when (typep ty 'sb-kernel:fun-type)
          (flet ((ok-idx (ctype)
                   (loop for v in pool for i from 0
                         when (ignore-errors (multiple-value-bind (y c) (sb-kernel:ctypep v ctype) (and y c)))
                           collect i)))
            (format t "TY|~a|~{~{~a~^,~}~^;~}|~{~{~a~^,~}~^;~}|~a~%"
                    (string-downcase (symbol-name s))
                    (mapcar #'ok-idx (sb-kernel:fun-type-required ty))
                    (mapcar #'ok-idx (sb-kernel:fun-type-optional ty))
                    (let ((r (sb-kernel:fun-type-rest ty))) (if r (format nil "~{~a~^,~}" (ok-idx r)) "-")))))))))
"""


def run_cmd(argv, timeout, env=None, cwd=None):
    full = [TIMEOUT, "--kill-after=5s", str(timeout)] + argv
    try:
        p = subprocess.run(full, capture_output=True, text=True, errors="replace", env=env, cwd=cwd)
        return p.returncode, p.stdout, p.stderr
    except Exception as e:  # pragma: no cover
        return 255, "", str(e)


def lisp_argv(impl, path):
    if impl == "sbcl":
        return [SBCL, "--dynamic-space-size", "512MB", "--control-stack-size", "4MB", "--noinform",
                "--non-interactive", "--no-userinit", "--load", path]
    if impl == "ccl":
        return [CCL, "-n", "-b", "-Q", "-l", path, "-e", "(ccl:quit 0)"]
    raise ValueError(impl)


def enumerate_fns(tmp):
    path = os.path.join(tmp, "enum.lisp")
    with open(path, "w") as f:
        f.write("(defparameter cl-user::*w4-pool-exprs* '(" +
                " ".join('"' + e.replace("\\", "\\\\").replace('"', '\\"') + '"' for e, _ in POOL) + "))\n")
        f.write(ENUM_LISP)
    rc, out, err = run_cmd(lisp_argv("sbcl", path), 120)
    fns = {}

    def idxs(s):
        return [int(x) for x in s.split(",") if x.strip().isdigit()]
    for line in out.splitlines():
        line = line.rstrip("\r")
        if line.startswith("FN|"):
            _, name, attrs, ll = line.split("|", 3)
            fns[name] = {"attrs": set(a for a in attrs.split(",") if a), "ll": ll}
        elif line.startswith("TY|"):
            _, name, req, opt, rest = line.split("|", 4)
            if name in fns:
                fns[name]["req_ok"] = [idxs(p) for p in req.split(";")] if req else []
                fns[name]["opt_ok"] = [idxs(p) for p in opt.split(";")] if opt else []
                fns[name]["rest_ok"] = None if rest == "-" else idxs(rest)
    return fns


def parse_ll(ll):
    """Very small lambda-list parser for printed SBCL lambda lists."""
    toks = re.findall(r"\(|\)|[^\s()]+", ll)
    depth, section = 0, "req"
    req = opt = 0
    keys, rest = [], False
    i = 0
    while i < len(toks):
        t = toks[i]
        if t == "(":
            if depth == 1:
                # (var default) inside &optional/&key: take first symbol
                j = i + 1
                name = toks[j] if j < len(toks) else ""
                if name == "(":  # ((:kw var) default)
                    name = toks[j + 1]
                if section == "opt":
                    opt += 1
                elif section == "key":
                    keys.append(name.lstrip(":").lower())
                d2 = 1
                i += 1
                while i < len(toks) and d2 > 0:
                    if toks[i] == "(":
                        d2 += 1
                    elif toks[i] == ")":
                        d2 -= 1
                    i += 1
                continue
            depth += 1
        elif t == ")":
            depth -= 1
        elif t.upper() == "&OPTIONAL":
            section = "opt"
        elif t.upper() in ("&REST", "&BODY"):
            section = "rest"
            rest = True
        elif t.upper() == "&KEY":
            section = "key"
        elif t.upper() in ("&AUX", "&ALLOW-OTHER-KEYS", "&ENVIRONMENT", "&WHOLE"):
            section = "skip"
        elif depth == 1:
            if section == "req":
                req += 1
            elif section == "opt":
                opt += 1
            elif section == "key":
                keys.append(t.lstrip(":").lower())
            elif section == "rest":
                pass
        i += 1
    return req, opt, rest, keys


def pick_value(rng, fn):
    while True:
        expr, tags = rng.choice(POOL)
        if fn in SMALL_INT_ONLY and ("big" in tags or "float" in tags and "1d300" in expr):
            continue
        return expr, tags


def gen_flush_cases(rng, fns, n):
    cands = sorted(name for name, d in fns.items()
                   if "flushable" in d["attrs"] and name not in SKIP)
    # bias half the budget towards the mandate table so it is always exercised
    mandated = sorted(set(MANDATE_IMPROPER) | set(MANDATE_INDEX))
    cases = []
    for k in range(n):
        fn = rng.choice(mandated) if (k % 4 == 0) else rng.choice(cands)
        info = fns.get(fn)
        req, opt, rest, keys = parse_ll(info["ll"]) if info else (1, 0, False, [])
        nargs = req + rng.randint(0, opt) + (rng.randint(0, 2) if rest else 0)
        if fn in ("every", "some", "notany", "notevery") and nargs < 2:
            nargs = 2
        args, tags = [], []
        for j in range(nargs):
            if fn in ("every", "some", "notany", "notevery") and j == 0:
                e, t = rng.choice([("#'numberp", "fn"), ("#'null", "fn"), ("#'identity", "fn")])
            else:
                e, t = pick_value(rng, fn)
            args.append(e)
            tags.append(t)
        kwparts = []
        for kw in keys:
            if rng.random() < 0.35:
                if kw in ("start", "end", "start1", "end1", "start2", "end2", "count"):
                    v = rng.choice(INDEX_POOL)
                elif kw in ("key", "test", "test-not"):
                    v = rng.choice(KEY_FN_POOL)
                elif kw == "from-end":
                    v = rng.choice(["t", "nil"])
                else:
                    v, _ = pick_value(rng, fn)
                kwparts.append((kw, v))
        cases.append({"fn": fn, "args": args, "tags": tags, "kw": kwparts})
    return cases


def flush_case_lisp(idx, c):
    params = [f"a{i}" for i in range(len(c["args"]))] + [f"k{i}" for i in range(len(c["kw"]))]
    call = "(" + c["fn"] + " " + " ".join(f"a{i}" for i in range(len(c["args"])))
    call += " " + " ".join(f":{kw} k{i}" for i, (kw, _) in enumerate(c["kw"])) + ")"
    pl = "(" + " ".join(params) + ")"
    disc = f"(lambda {pl} (declare (optimize (speed 3) (safety 3) (debug 0))) {call} :done)"
    used = f"(lambda {pl} (declare (optimize (speed 3) (safety 3) (debug 0))) (list {call}))"
    ref = f"(lambda {pl} (declare (optimize (speed 0) (safety 3) (debug 3)) (notinline {c['fn']})) (list {call}))"
    argsfn = "(lambda () (list " + " ".join(c["args"] + [v for _, v in c["kw"]]) + "))"
    return f"(w4-case {idx} \"flush\" {disc} {used} {ref} {argsfn})\n"


# ---------------------------------------------------------------------------
# mutation templates: read R, mutate M, read R again -> list of both reads
# ---------------------------------------------------------------------------
MUT_TEMPLATES = [
    # (init-binding, read-expr, mutation-expr)
    ("(make-array 6 :fill-pointer 6 :initial-contents (list {a} {b} {c} {a} {b} {c}))", "(length v)", "(setf (fill-pointer v) {fp})"),
    ("(make-array 6 :fill-pointer 3 :adjustable t :initial-contents (list {a} {b} {c} 0 0 0))", "(length v)", "(vector-push-extend {a} v)"),
    ("(make-array 6 :fill-pointer 6 :initial-contents (list {a} {b} {c} {a} {b} {c}))", "(position {b} v)", "(setf (fill-pointer v) {fp})"),
    ("(make-array 6 :fill-pointer 6 :initial-contents (list {a} {b} {c} {a} {b} {c}))", "(find {c} v)", "(setf (aref v 2) {d} (aref v 5) {d})"),
    ("(list {a} {b} {c})", "(car v)", "(rplaca v {d})"),
    ("(list {a} {b} {c})", "(eql (car v) {a})", "(rplaca v {d})"),
    ("(list {a} {b} {c})", "(length v)", "(rplacd (cdr v) nil)"),
    ("(list {a} {b} {c})", "(member {c} v)", "(setf (third v) {d})"),
    ("(vector {a} {b} {c})", "(aref v 0)", "(setf (aref v 0) {d})"),
    ("(vector {a} {b} {c})", "(< (aref v 0) (aref v 1))", "(rotatef (aref v 0) (aref v 1))"),
    ("(vector {a} {b} {c})", "(reduce #'+ v)", "(fill v {d})"),
    ("(vector {a} {b} {c})", "(count {a} v)", "(replace v (vector {d} {d}))"),
    ("(vector {a} {b} {c})", "(aref v 0)", "(setf v (nreverse v))"),
    ("(vector {a} {b} {c})", "(aref v 0)", "(setf v (sort v #'<))"),
    ("(make-string 3 :initial-element #\\a)", "(char v 1)", "(setf (char v 1) #\\b)"),
    ("(make-string 3 :initial-element #\\a)", "(string= v \"aaa\")", "(setf (char v 1) #\\b)"),
    ("(make-array 8 :element-type 'bit :initial-element 0)", "(sbit v {i})", "(setf (sbit v {i}) 1)"),
    ("(make-array 8 :element-type 'bit :initial-element 0)", "(count 1 v)", "(bit-not v v)"),
    ("(make-array 4 :element-type '(unsigned-byte 8) :initial-element {u})", "(logand (aref v 1) 255)", "(incf (aref v 1))"),
    ("(make-array 4 :element-type 'double-float :initial-element 1.5d0)", "(aref v 1)", "(setf (aref v 1) -0.0d0)"),
    ("(list {a} {b} {c} {a})", "(length v)", "(setf v (delete {a} v))"),
    ("(make-hash-table)", "(gethash {a} v)", "(setf (gethash {a} v) {d})"),
    ("(list (cons {a} {b}))", "(cdr (assoc {a} v))", "(setf (cdr (first v)) {d})"),
    ("(cons {a} {b})", "(car v)", "(setf (car v) (cdr v))"),
    ("(make-array '(2 2) :initial-element {a})", "(array-total-size v)", "(setf (aref v 1 1) {d})"),
    ("(make-array 3 :adjustable t :initial-element {a})", "(length v)", "(setf v (adjust-array v {fp} :initial-element {d}))"),
]


def gen_mut_cases(rng, n):
    cases = []
    for _ in range(n):
        init, rd, mut = rng.choice(MUT_TEMPLATES)
        vals = {"a": rng.choice(["1", "2", "3", "7"]), "b": rng.choice(["1", "4", "5"]),
                "c": rng.choice(["2", "6", "9"]), "d": rng.choice(["0", "8", "11"]),
                "fp": str(rng.randint(0, 6)), "i": str(rng.randint(0, 7)), "u": str(rng.choice([0, 7, 254, 255]))}
        init, rd, mut = (s.format(**vals) for s in (init, rd, mut))
        wrap = rng.choice(["plain", "let", "flet", "loop"])
        if wrap == "plain":
            body = f"(let* ((v {init}) (r1 {rd})) {mut} (list r1 {rd}))"
        elif wrap == "let":
            body = f"(let* ((v {init}) (r1 {rd}) (r2 (progn {mut} {rd}))) (list r1 r2 {rd}))"
        elif wrap == "flet":
            body = f"(let ((v {init})) (flet ((rd () {rd}) (mu () {mut})) (declare (notinline mu)) (let ((r1 (rd))) (mu) (list r1 (rd)))))"
        else:
            body = f"(let ((v {init}) (acc nil)) (dotimes (i 2) (push {rd} acc) (when (= i 0) {mut})) (nreverse acc))"
        cases.append({"body": body})
    return cases


def mut_case_lisp(idx, c):
    b = c["body"]
    s3 = f"(lambda () (declare (optimize (speed 3) (safety 3) (debug 0))) {b})"
    s1 = f"(lambda () (declare (optimize (speed 1) (safety 1))) {b})"
    s0 = f"(lambda () (declare (optimize (speed 0) (safety 3) (debug 3)) (notinline length car aref char position find member count reduce gethash assoc sbit string= eql)) {b})"
    return f"(w4-case {idx} \"mut\" {s3} {s1} {s0} (lambda () nil))\n"


def run_case_file(impl, tmp, body, ncases, per_case_budget=4, host=None):
    """Run a case file, restarting after crashes. Returns {idx: [results...]}"""
    path = os.path.join(tmp, f"cases-{impl}{'-' + host if host else ''}.lisp")
    with open(path, "w") as f:
        f.write(LISP_PRELUDE)
        f.write(body)
    results, crashes = {}, {}
    start = 0
    rounds = 0
    while start < ncases and rounds < 200:
        rounds += 1
        env = dict(os.environ, W4_START=str(start))
        budget = max(60, per_case_budget * (ncases - start) + 30)
        if host:
            rc, out, err = run_remote(impl, path, start, min(budget, 600))
        else:
            rc, out, err = run_cmd(lisp_argv(impl, path), budget, env=env, cwd=tmp)
        last_begin = None
        for line in out.splitlines():
            if line.startswith("B|"):
                last_begin = int(line[2:].strip())
            elif line.startswith("R|"):
                parts = line.rstrip("\r").split("|")
                results[int(parts[1])] = parts[3:]
                last_begin = None
        if last_begin is not None and last_begin not in results:
            tail = (err or out)[-400:].replace("\n", " ")
            kind = "CRASH:HEAP-EXHAUSTED" if "Heap exhausted" in (out + err) else (
                "CRASH:KILLED" if rc in (124, 137) else f"CRASH:rc={rc}")
            crashes[last_begin] = (kind, tail)
            start = last_begin + 1
        else:
            done = max(results) + 1 if results else ncases
            if done <= start:
                break
            start = done
    return results, crashes


def run_remote(impl, path, start, budget):
    rpath = f"/tmp/w4-astra-host-{os.getpid()}-{os.path.basename(path)}"
    with open(path) as f:
        data = f.read()
    put = subprocess.run([TIMEOUT, "--kill-after=5s", "60", "ssh", "hbox", f"cat > {rpath}"], input=data,
                         text=True, capture_output=True)
    if impl == "sbcl":
        cmd = f"W4_START={start} swarm-build timeout {budget}s {HBOX_SBCL} --dynamic-space-size 512MB --noinform --non-interactive --no-userinit --load {rpath}; rm -f {rpath}"
    else:
        cmd = f"W4_START={start} swarm-build timeout {budget}s {HBOX_CCL} -n -b -Q -l {rpath} -e '(ccl:quit 0)'; rm -f {rpath}"
    return run_cmd(["ssh", "hbox", cmd], budget + 30)


def classify_flush(c, r):
    """r = [disc, used, ref]"""
    disc, used, ref = (r + ["?", "?", "?"])[:3]
    out = []
    ref_err = ref.startswith("ERR") or ref.startswith("STORAGE") or ref in ("TIMEOUT",) or ref.startswith("CRASH")
    if ref.startswith("ERR") and disc.startswith("OK"):
        out.append("ELIDED")
    if ref.startswith("OK") and (disc.startswith("ERR") or disc == "TIMEOUT"):
        out.append("SPURIOUS")
    if used.startswith("OK") and ref.startswith("OK") and used != ref:
        out.append("VALUE")
    if used.startswith("ERR") != ref.startswith("ERR") and "TIMEOUT" not in (used, ref):
        out.append("ERRCLASS")
    if used == "TIMEOUT" or ref == "TIMEOUT":
        out.append("HANG")
    if any(x.startswith("CRASH") for x in r):
        out.append("CRASH")
    # mandate cross-reference
    mand = None
    fn = c["fn"]
    if fn in MANDATE_IMPROPER:
        bad = MANDATE_IMPROPER[fn][0].split("|")
        argtags = " ".join(c["tags"])
        if any(b in argtags for b in bad):
            # every/some/...: first arg is the predicate, only sequence args matter
            ok_types = ("ERR:TE:",)
            for which, v in (("disc", disc), ("used", used), ("ref", ref)):
                if not v.startswith(ok_types):
                    mand = f"MANDATED-{fn}-{which}={v[:60]}"
                    break
    if fn in MANDATE_INDEX and ref.startswith("ERR") and disc.startswith("OK"):
        mand = f"MANDATED-index-{fn}"
    if fn in MANDATE_TYPE and ref.startswith("ERR:TE:") and disc.startswith("OK"):
        mand = f"MANDATE-TYPE-CANDIDATE-{fn}"
    return out, mand, ref_err


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--seed", type=int, default=20261114)
    ap.add_argument("--cases", type=int, default=400, help="flush cases (mutation cases = cases/2)")
    ap.add_argument("--mode", choices=["all", "flush", "mutation"], default="all")
    ap.add_argument("--impl", choices=["sbcl", "ccl", "both"], default="both")
    ap.add_argument("--hbox", action="store_true", help="also replay on hbox x86-64 SBCL+CCL")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--json", default=None, help="write full results JSON here")
    ap.add_argument("--verbose", "-v", action="store_true")
    a = ap.parse_args()
    rng = random.Random(a.seed)
    tmp = tempfile.mkdtemp(prefix="w4-astra-host-", dir="/tmp")
    report = {"seed": a.seed, "cases": a.cases}
    try:
        fns = enumerate_fns(tmp)
        attr_counts = Counter(at for d in fns.values() for at in d["attrs"]
                              if at in ("flushable", "unsafely-flushable", "foldable", "movable"))
        print(f"[enum] SBCL CL functions with fun-info: {len(fns)}  attrs={dict(attr_counts)}")
        report["attr_counts"] = dict(attr_counts)
        impls = ["sbcl", "ccl"] if a.impl == "both" else [a.impl]
        targets = [(i, None) for i in impls] + ([(i, "hbox") for i in impls] if a.hbox else [])

        if a.mode in ("all", "flush"):
            fcases = gen_flush_cases(rng, fns, a.cases)
            body = "".join(flush_case_lisp(i, c) for i, c in enumerate(fcases))
            per = {}
            for impl, host in targets:
                res, crashes = run_case_file(impl, tmp, body, len(fcases), host=host)
                for idx, (kind, tail) in crashes.items():
                    res[idx] = [kind, kind, kind]
                per[(impl, host)] = res
                tally, mand, examples = Counter(), Counter(), defaultdict(list)
                for i, c in enumerate(fcases):
                    r = res.get(i)
                    if r is None:
                        tally["MISSING"] += 1
                        continue
                    cls, m, _ = classify_flush(c, r)
                    for k in cls:
                        tally[k] += 1
                        if len(examples[k]) < 6:
                            examples[k].append((c["fn"], c["args"], c["kw"], r))
                    if m:
                        mand[m.split("=")[0]] += 1
                        if len(examples["M:" + m.split("=")[0]]) < 2:
                            examples["M:" + m.split("=")[0]].append((c["fn"], c["args"], c["kw"], r))
                tag = impl + ("@" + host if host else "")
                elided_fns = Counter(c["fn"] for i, c in enumerate(fcases)
                                     if i in res and "ELIDED" in classify_flush(c, res[i])[0])
                print(f"[flush:{tag}] cases={len(fcases)} done={len(res)} crashes={len(crashes)} tally={dict(tally)}")
                print(f"[flush:{tag}] elided-by-fn: {dict(elided_fns.most_common(25))}")
                for k, v in sorted(mand.items()):
                    print(f"[flush:{tag}] MANDATE {k}: {v}")
                for k, ex in examples.items():
                    if k.startswith("M:") or k in ("SPURIOUS", "VALUE", "ERRCLASS", "CRASH") or a.verbose:
                        for fn, args, kw, r in ex[:3]:
                            print(f"    {k:<28} ({fn} {' '.join(args)} {' '.join(':%s %s' % p for p in kw)}) -> {r}")
                report[f"flush_{tag}"] = {"tally": dict(tally), "mandate": dict(mand), "elided_fns": dict(elided_fns),
                                          "crashes": {str(k): v for k, v in crashes.items()}}
            # cross-implementation: mandated ok on one, violated on the other
            if len(per) >= 2:
                keys = list(per)
                diff = Counter()
                for i, c in enumerate(fcases):
                    states = {}
                    for k in keys:
                        r = per[k].get(i)
                        if r:
                            states[k] = classify_flush(c, r)[1]
                    if len(set(bool(v) for v in states.values())) > 1:
                        diff[c["fn"]] += 1
                        if diff[c["fn"]] <= 1:
                            print(f"  [xdiff] ({c['fn']} {' '.join(c['args'])}) " +
                                  "; ".join(f"{k[0]}{'@' + k[1] if k[1] else ''}={per[k].get(i)}" for k in keys))
                print(f"[flush:cross] mandate-status differs across impls for: {dict(diff)}")
                report["flush_cross"] = dict(diff)

        if a.mode in ("all", "mutation"):
            mcases = gen_mut_cases(rng, max(1, a.cases // 2))
            body = "".join(mut_case_lisp(i, c) for i, c in enumerate(mcases))
            for impl, host in targets:
                res, crashes = run_case_file(impl, tmp, body, len(mcases), host=host)
                bad = []
                for i, c in enumerate(mcases):
                    r = res.get(i)
                    if r and len(set(r)) > 1:
                        bad.append((c["body"], r))
                tag = impl + ("@" + host if host else "")
                print(f"[mutation:{tag}] cases={len(mcases)} done={len(res)} crashes={len(crashes)} mismatches={len(bad)}")
                for b, r in bad[:8]:
                    print(f"    MISMATCH {b}\n      s3/s1/ni = {r}")
                report[f"mutation_{tag}"] = {"done": len(res), "mismatches": [(b, r) for b, r in bad]}
        if a.json:
            with open(a.json, "w") as f:
                json.dump(report, f, indent=1, default=str)
    finally:
        if a.keep:
            print(f"[keep] {tmp}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
