#!/usr/bin/env python3
"""
Wave-4 Stage 4: Systematic CL Standard Library Boundary & Transform Differential Fuzzer
=======================================================================================

Covers 6 ANSI Common Lisp library + compiler-transform domains across all 4 targets:
  - sbcl-arm64  (/opt/homebrew/bin/sbcl)
  - sbcl-x86-64 (ssh hbox: sbcl-2.6.10-x86-64-linux/run-sbcl.sh)
  - ccl-arm64   (/Users/ember/dev/ccl/darm64cl)
  - ccl-x86-64  (ssh hbox: ccl/lx86cl64)

Optimization / inlining differential modes per target:
  - S3 : (declare (optimize (speed 3) (safety 3) (debug 1) (space 0)))
  - S1 : (declare (optimize (speed 1) (safety 1)))
  - NI : (declare (optimize (speed 1) (safety 1)) (notinline <op...>))

Domains:
  1. Set & list primitives + compiler transforms (union/nunion, intersection/nintersection,
     set-difference/nset-difference, set-exclusive-or, subsetp, adjoin, member, assoc,
     rassoc, ldiff, tailp, butlast/nbutlast, revappend/nreconc, sublis/nsublis, subst/nsubst,
     copy-list/copy-seq + remove-if + complement)
  2. Sequence, vector & array boundary primitives + transforms (mismatch, search,
     substitute/nsubstitute, remove/delete, remove-duplicates/delete-duplicates incl. >200,
     reverse/nreverse, merge, sort, stable-sort, reduce + derive-type, map, map-into,
     replace incl. self-overlap & displaced aliasing, fill, subseq, find, position, count,
     every/some/notany/notevery, concatenate, coerce, make-sequence, adjust-array,
     displaced/adjustable/fill-pointer/0D/multi-D arrays)
  3. Bit-vector & multi-D bit-array primitives + transforms (all 10 binary bit-* ops + bit-not,
     lengths 0/1/63/64/65/127/128/129, unaligned displaced bit offsets, nil/t/self-aliasing)
  4. Character & string boundary primitives + transforms (full [0, char-code-limit) Unicode
     case/ordering invariant sweep, string<..string-not-equal with :start1/:start2 mismatch
     indices, string-upcase/downcase/capitalize/nstring-capitalize, string-trim, base-string
     vs character string vs displaced string)
  5. Hash-table (eq, eql, equal, equalp) & sxhash equivalence-class invariants across numbers
     (integers, ratios, +-0.0f0/d0, complex), characters, strings, specialized arrays,
     bit-vectors, structures, and pathnames
  6. Numeric edge primitives + transforms (boole 0..15, gcd, lcm, isqrt, expt, rational,
     rationalize, signum, abs, phase, cis, atan, log, sqrt branch cuts, decode-float,
     integer-decode-float, scale-float, float-radix/digits/precision/sign, ffloor..fround,
     upgraded-complex-part-type)

Zero-UB guarantee: all mutable/destructive operations receive freshly constructed runtime
copies via FRESH-COPY; literal constants are never mutated.
"""

import argparse
import json
import os
import random
import shlex
import subprocess
import sys
import time
from typing import Dict, List, Tuple

sys.dont_write_bytecode = True

TIMEOUT_BIN = "/opt/homebrew/bin/timeout"
LOCAL_SBCL = "/opt/homebrew/bin/sbcl"
LOCAL_CCL = "/Users/ember/dev/ccl/darm64cl"
REMOTE_SBCL = "/home/hbox/ca-sbcl-root/dl-2.6.10/sbcl-2.6.10-x86-64-linux/run-sbcl.sh"
REMOTE_CCL = "/home/hbox/ca-x86-ccl/ccl-dl/extracted/ccl/lx86cl64"

KNOWN_EXCLUSION_PREFIXES = (
    "KNOWN-HC-W3-3",
    "KNOWN-HC-W3-4",
    "KNOWN-HC-W3-5",
)


LISP_PREAMBLE = r"""
(defpackage #:w4-stdlib-fuzz
  (:use #:cl))
(in-package #:w4-stdlib-fuzz)

#+sbcl
(declaim (sb-ext:muffle-conditions style-warning sb-ext:compiler-note))

(defstruct (fuzz-point (:constructor make-fuzz-point (x y)))
  x y)

(defstruct (fuzz-fbox (:constructor make-fuzz-fbox (d s)))
  (d 0.0d0 :type double-float)
  (s 0.0f0 :type single-float))

(defun fresh-copy (x)
  "Deep-copy conses and arrays (preserving element-type, fill-pointer, adjustability)
so destructive CL primitives never touch shared or literal storage."
  (cond
    ((consp x)
     (cons (fresh-copy (car x)) (fresh-copy (cdr x))))
    ((arrayp x)
     (multiple-value-bind (disp-to disp-off) (array-displacement x)
       (if disp-to
           (let ((new-backing (fresh-copy disp-to)))
             (make-array (array-dimensions x)
                         :element-type (array-element-type x)
                         :adjustable (adjustable-array-p x)
                         :fill-pointer (and (array-has-fill-pointer-p x) (fill-pointer x))
                         :displaced-to new-backing
                         :displaced-index-offset disp-off))
           (let ((out (make-array (array-dimensions x)
                                  :element-type (array-element-type x)
                                  :adjustable (adjustable-array-p x)
                                  :fill-pointer (and (array-has-fill-pointer-p x)
                                                     (fill-pointer x)))))
             (dotimes (i (array-total-size x) out)
               (setf (row-major-aref out i)
                     (fresh-copy (row-major-aref x i))))))))
    (t x)))

(defun make-det-bv (len seed)
  (let ((bv (make-array len :element-type 'bit)))
    (dotimes (i len bv)
      (setf (sbit bv i) (logand 1 (ash (logxor (* (1+ i) 1103515245) seed) -4))))))

(defun float-tag (f)
  (let* ((s (if (minusp (float-sign f)) "-" "+"))
         (ty (if (typep f 'double-float) "DF" "SF")))
    (cond
      ((/= f f) (format nil "~A:NAN" ty))
      ((zerop f) (format nil "~A:~A0" ty s))
      (t (multiple-value-bind (sig exp sign) (integer-decode-float f)
           (format nil "~A:~D*~D*2^~D" ty sign sig exp))))))

(defun canon (v &optional (depth 0))
  "Canonicalize any CL value into a deterministic string preserving float sign/precision,
array rank/dimensions/active-elements, cons structure, and condition class."
  (when (> depth 12)
    (return-from canon "..."))
  (cond
    ((null v) "NIL")
    ((eq v t) "T")
    ((integerp v) (format nil "INT:~D" v))
    ((typep v 'ratio) (format nil "RAT:~D/~D" (numerator v) (denominator v)))
    ((floatp v) (float-tag v))
    ((complexp v) (format nil "CPLX(~A,~A)" (canon (realpart v) (1+ depth))
                          (canon (imagpart v) (1+ depth))))
    ((characterp v) (format nil "CH:~D" (char-code v)))
    ((symbolp v)
     (let ((pkg (symbol-package v)))
       (if pkg
           (format nil "SYM:~A::~A" (package-name pkg) (symbol-name v))
           (format nil "UNINTERN:~A" (symbol-name v)))))
    ((consp v)
     (with-output-to-string (out)
       (write-string "(" out)
       (loop for cur = v then (cdr cur)
             for idx from 0 below 64
             do (when (> idx 0) (write-string " " out))
                (write-string (canon (car cur) (1+ depth)) out)
             when (atom (cdr cur))
               do (unless (null (cdr cur))
                    (write-string " . " out)
                    (write-string (canon (cdr cur) (1+ depth)) out))
                  (return)
             finally (write-string " ..." out))
       (write-string ")" out)))
    ((stringp v)
     (with-output-to-string (out)
       (format out "STR[~D]:" (length v))
       (loop for i from 0 below (length v)
             do (format out "~X," (char-code (char v i))))))
    ((bit-vector-p v)
     (with-output-to-string (out)
       (format out "BV[~D]:" (length v))
       (loop for i from 0 below (length v)
             do (write-char (if (zerop (bit v i)) #\0 #\1) out))))
    ((vectorp v)
     (with-output-to-string (out)
       (format out "VEC[~D]:(" (length v))
       (loop for i from 0 below (length v)
             do (when (> i 0) (write-char #\Space out))
                (write-string (canon (aref v i) (1+ depth)) out))
       (write-string ")" out)))
    ((arrayp v)
     (with-output-to-string (out)
       (format out "ARR~S:(" (array-dimensions v))
       (loop for i from 0 below (array-total-size v)
             do (when (> i 0) (write-char #\Space out))
                (write-string (canon (row-major-aref v i) (1+ depth)) out))
       (write-string ")" out)))
    (t (format nil "OBJ:~S" (type-of v)))))

(defun canon-set (v)
  "Order-independent canonicalization for CL set operations (union/intersection/set-difference/etc.),
deduplicating equivalent elements while verifying proper list output."
  (if (not (listp v))
      (canon v)
      (let* ((tags (mapcar #'canon v))
             (sorted (sort (remove-duplicates tags :test #'string=) #'string<)))
        (format nil "SET{~{~A~^,~}}" sorted))))

(defun safe-compile (lambda-form)
  (handler-case
      (let ((*error-output* (make-broadcast-stream)))
        (multiple-value-bind (fn warnings-p failure-p)
            (handler-bind ((warning #'muffle-warning))
              (compile nil lambda-form))
          (declare (ignore warnings-p failure-p))
          (if fn
              (values fn nil)
              (values nil "COMPILE-RETURNED-NIL"))))
    (serious-condition (c)
      (values nil (format nil "COMPILE-ERR:~A" (type-of c))))))

(defun safe-call (fn args canon-fn)
  (handler-case
      (let ((vals (multiple-value-list (apply fn args))))
        (format nil "OK:~{~A~^|~}" (mapcar canon-fn vals)))
    (type-error () "ERR:TYPE-ERROR")
    (arithmetic-error () "ERR:ARITH-ERROR")
    (error () "ERR:ERROR")
    (serious-condition () "ERR:SERIOUS")))

(defstruct diff-spec
  id
  arg-thunk
  params
  body-forms
  notinline-syms
  canon-fn)

(defvar *queued-specs* (make-array 0 :adjustable t :fill-pointer 0))
(defvar *results* (make-hash-table :test 'equal))
(defvar *intra-diffs* nil)
(defvar *total-cases* 0)
(defvar *total-evals* 0)

(defun run-diff-case (id arg-thunk body-form notinline-syms &key (canon-fn #'canon))
  "Queue a differential test case to be compiled in batched S3, S1, and NI compilation units."
  (vector-push-extend
   (make-diff-spec :id id
                   :arg-thunk arg-thunk
                   :params (car body-form)
                   :body-forms (cdr body-form)
                   :notinline-syms notinline-syms
                   :canon-fn canon-fn)
   *queued-specs*))

(defun record-mode-result (id mode-idx val)
  (let ((entry (or (gethash id *results*)
                   (setf (gethash id *results*) (list nil nil nil)))))
    (setf (nth mode-idx entry) val)))

(defun run-single-spec-fallback (spec opt-decl mode-idx use-notinline)
  (let* ((ni (and use-notinline (diff-spec-notinline-syms spec)))
         (lam `(lambda (,@(diff-spec-params spec))
                 (declare ,opt-decl ,@(when ni `((notinline ,@ni))))
                 ,@(diff-spec-body-forms spec))))
    (multiple-value-bind (fn cerr) (safe-compile lam)
      (let ((res (or cerr
                     (progn
                       (incf *total-evals*)
                       (safe-call fn (funcall (diff-spec-arg-thunk spec))
                                  (diff-spec-canon-fn spec))))))
        (record-mode-result (diff-spec-id spec) mode-idx res)))))

(defun execute-queued-batches (&optional (batch-size 48))
  "Compile queued test cases in batches of BATCH-SIZE escaped FLET functions per mode
(S3, S1, NI) so compilation finishes in <5s per target while preserving exact per-test
parameter/type isolation and per-case compiler-ICE fallback."
  (let ((n (length *queued-specs*)))
    (incf *total-cases* n)
    (loop for start from 0 below n by batch-size
          for end = (min n (+ start batch-size))
          for slice = (loop for i from start below end collect (aref *queued-specs* i))
          do (dolist (mode '((0 (optimize (speed 3) (safety 3) (debug 1) (space 0)) nil)
                             (1 (optimize (speed 1) (safety 1)) nil)
                             (2 (optimize (speed 1) (safety 1)) t)))
               (destructuring-bind (mode-idx opt-decl use-ni) mode
                 (let* ((fnames (loop for i from 0 below (length slice)
                                      collect (intern (format nil "%CASE-~D-~D" start i)
                                                      "W4-STDLIB-FUZZ")))
                        (flets (loop for sp in slice
                                     for fn-sym in fnames
                                     for ni = (and use-ni (diff-spec-notinline-syms sp))
                                     collect `(,fn-sym (,@(diff-spec-params sp))
                                                ,@(when ni `((declare (notinline ,@ni))))
                                                ,@(diff-spec-body-forms sp))))
                        (batch-lam
                          `(lambda (specs)
                             (declare ,opt-decl)
                             (flet (,@flets)
                               (declare (notinline ,@fnames))
                               ,@(loop for fn-sym in fnames
                                       for k from 0
                                       collect `(let ((sp (nth ,k specs)))
                                                  (incf *total-evals*)
                                                  (record-mode-result
                                                   (diff-spec-id sp) ,mode-idx
                                                   (safe-call #',fn-sym
                                                              (funcall (diff-spec-arg-thunk sp))
                                                              (diff-spec-canon-fn sp)))))))))
                   (multiple-value-bind (bfn cerr) (safe-compile batch-lam)
                     (if bfn
                         (funcall bfn slice)
                         (dolist (sp slice)
                           (run-single-spec-fallback sp opt-decl mode-idx use-ni)))))))))
  (maphash (lambda (id vals)
             (destructuring-bind (s3 s1 ni) vals
               (unless (and (string= s3 s1) (string= s1 ni))
                 (push (list id s3 s1 ni) *intra-diffs*))))
           *results*))

(defun record-check (id status &optional detail)
  "Record a direct semantic / invariant check (e.g. full Unicode sweep or equalp hash-table oracle)."
  (incf *total-cases*)
  (incf *total-evals*)
  (let ((val (if detail (format nil "~A:~A" status detail) status)))
    (setf (gethash id *results*) (list val val val))))
"""


def build_domain1_set_list_lisp(rng: random.Random, n_rand: int) -> str:
    lines = ["\n;;; === DOMAIN 1: SET & LIST PRIMITIVES ===\n"]
    lines.append(r"""
(let ((set-pairs
        (list
         (list "empty-empty" (lambda () (list nil nil)))
         (list "empty-nonempty" (lambda () (list nil (list 1 2 3))))
         (list "nonempty-empty" (lambda () (list (list 1 2 3) nil)))
         (list "dups-int" (lambda () (list (list 1 2 2 3 1 4) (list 2 4 4 5))))
         (list "neg-fix-big" (lambda () (list (list -1 0 1 (1- (ash 1 59)) (1- (ash 1 62)) (ash 1 65))
                                              (list (ash 1 65) (- (ash 1 59)) (- (ash 1 62)) 0 2))))
         (list "nil-elems" (lambda () (list (list nil 'a 'b nil) (list 'b nil 'c)))))))
  (dolist (sp set-pairs)
    (let ((sname (first sp))
          (sthunk (second sp)))
      (dolist (op '(union nunion intersection nintersection set-difference nset-difference set-exclusive-or))
        (run-diff-case (format nil "D1-SET-~A-~A" op sname)
                       sthunk `((a b) (,op a b)) (list op) :canon-fn #'canon-set)
        (run-diff-case (format nil "D1-SET-KEY-~A-~A" op sname)
                       (lambda () (list (list -1 2 -3 4 0) (list 1 -2 5 0)))
                       `((a b) (mapcar #'abs (,op a b :key #'abs :test #'eql))) (list op) :canon-fn #'canon-set))
      (run-diff-case (format nil "D1-SUBSETP-~A" sname)
                     sthunk '((a b) (if (subsetp a b) t nil)) '(subsetp))
      (run-diff-case (format nil "D1-SUBSETP-TESTNOT-~A" sname)
                     sthunk '((a b) (if (subsetp a b :test-not #'eql) t nil)) '(subsetp)))))

;; Same-leaf (op x x) transforms on non-destructive set ops (100% zero-UB;
;; destructive nunion/nintersection/nset-difference must NOT alias list1 and list2 cons cells!)
(dolist (op '(union intersection set-difference))
  (run-diff-case (format nil "D1-SAMELEAF-~A" op)
                 (lambda () (list (list 1 2 3 2)))
                 `((x) (,op x x)) (list op) :canon-fn #'canon-set)
  (run-diff-case (format nil "D1-SAMELEAF-TESTNOT-~A" op)
                 (lambda () (list (list 1 1)))
                 `((x) (,op x x :test-not #'eql)) (list op) :canon-fn #'canon-set)
  (run-diff-case (format nil "D1-SAMELEAF-EMPTY-~A" op)
                 (lambda () (list nil))
                 `((x) (,op x x)) (list op) :canon-fn #'canon-set))
(dolist (op '(nunion nintersection nset-difference))
  (run-diff-case (format nil "D1-EQUALVAL-~A" op)
                 (lambda () (list (list 1 2 3 2) (list 1 2 3 2)))
                 `((a b) (,op a b)) (list op) :canon-fn #'canon-set))

(run-diff-case "D1-SAMELEAF-SUBSETP-TESTNOT"
               (lambda () (list (list 1 2)))
               '((x) (if (subsetp x x :test-not #'eql) t nil)) '(subsetp))

;; Adjoin (:key applies to item as well as list elements per CLHS 14.2.46!)
(run-diff-case "D1-ADJOIN-KEY-PRESENT"
               (lambda () (list -2 (list 1 2 3)))
               '((item lst) (adjoin item lst :key #'abs :test #'=)) '(adjoin))
(run-diff-case "D1-ADJOIN-KEY-ABSENT"
               (lambda () (list -5 (list 1 2 3)))
               '((item lst) (adjoin item lst :key #'abs :test #'=)) '(adjoin))
(run-diff-case "D1-ADJOIN-TESTNOT"
               (lambda () (list 1 (list 1 1 1)))
               '((item lst) (adjoin item lst :test-not #'eql)) '(adjoin))

;; Member / Assoc / Rassoc with constant lists, nil entries, 60-bit & 62-bit fixnum boundaries, perfect-hash sizes
(dolist (item (list 'a 'd 'h nil 0 -1 (1- (ash 1 59)) (- (ash 1 59)) (1- (ash 1 62)) (- (ash 1 62)) #\a (code-char 955)))
  (let ((it item))
    (run-diff-case (format nil "D1-MEMBER-CONST-SYM-~A" (canon it))
                   (lambda () (list it))
                   '((x) (member x '(a b c d e f g h nil))) '(member))
    (run-diff-case (format nil "D1-MEMBER-CONST-FIX-~A" (canon it))
                   (lambda () (list it))
                   `((x) (member x '(0 -1 1 2 42 ,(1- (ash 1 59)) ,(- (ash 1 59)) ,(1- (ash 1 62)) ,(- (ash 1 62))))) '(member))
    (run-diff-case (format nil "D1-ASSOC-CONST-NIL-~A" (canon it))
                   (lambda () (list it))
                   '((x) (cdr (assoc x '((a . 1) nil (b . 2) (c . 3) (d . 4) (nil . 99) (h . 8))))) '(assoc))
    (run-diff-case (format nil "D1-RASSOC-CONST-NIL-~A" (canon it))
                   (lambda () (list it))
                   '((x) (car (rassoc x '((1 . a) nil (2 . b) (3 . c) (99 . nil) (8 . d))))) '(rassoc))))

;; ldiff / tailp / butlast / nbutlast / revappend / nreconc / sublis / nsublis / subst / nsubst
(run-diff-case "D1-LDIFF-PROPER-TAIL"
               (lambda () (let* ((tail (list 3 4)) (full (list* 1 2 tail))) (list full tail)))
               '((l tl) (list (ldiff l tl) (if (tailp tl l) t nil))) '(ldiff tailp))
(run-diff-case "D1-LDIFF-DOTTED-ATOM"
               (lambda () (list (cons 1 (cons 2 99)) 99))
               '((l at) (list (ldiff l at) (if (tailp at l) t nil))) '(ldiff tailp))
(run-diff-case "D1-LDIFF-DOTTED-MISS"
               (lambda () (list (cons 1 (cons 2 99)) 77))
               '((l at) (list (ldiff l at) (if (tailp at l) t nil))) '(ldiff tailp))
(dolist (n '(0 1 2 5))
  (let ((nn n))
    (run-diff-case (format nil "D1-BUTLAST-~D" nn)
                   (lambda () (list (list 10 20 30) nn))
                   '((l k) (butlast l k)) '(butlast))
    (run-diff-case (format nil "D1-NBUTLAST-~D" nn)
                   (lambda () (list (list 10 20 30) nn))
                   '((l k) (nbutlast l k)) '(nbutlast))
    (run-diff-case (format nil "D1-BUTLAST-DOTTED-~D" nn)
                   (lambda () (list (list* 10 20 30 99) nn))
                   '((l k) (butlast l k)) '(butlast))
    (run-diff-case (format nil "D1-NBUTLAST-DOTTED-~D" nn)
                   (lambda () (list (list* 10 20 30 99) nn))
                   '((l k) (nbutlast l k)) '(nbutlast))))

(run-diff-case "D1-REVAPPEND-ATOM"
               (lambda () (list (list 1 2 3) 'tail-atom))
               '((x y) (revappend x y)) '(revappend))
(run-diff-case "D1-NRECONC-ATOM"
               (lambda () (list (list 1 2 3) 'tail-atom))
               '((x y) (nreconc x y)) '(nreconc))
(run-diff-case "D1-SUBLIS-NSUBLIS"
               (lambda () (list (list (cons 1 'one) (cons 2 'two))
                                (cons (list 1 2) (cons 3 1))))
               '((al tr) (list (sublis al (fresh-copy tr))
                               (nsublis al (fresh-copy tr))))
               '(sublis nsublis))
(run-diff-case "D1-SUBST-NSUBST-KEY"
               (lambda () (list 'neg (list 1 (list -2 3) -4)))
               '((nw tr) (list (subst-if nw (lambda (v) (and (numberp v) (minusp v))) (fresh-copy tr))
                               (nsubst-if nw (lambda (v) (and (numberp v) (minusp v))) (fresh-copy tr))))
               '(subst-if nsubst-if))
(run-diff-case "D1-COPY-REMOVE-IF-COMPLEMENT"
               (lambda () (list (list 1 2 3 4 5 6)))
               '((x) (declare (type list x))
                 (list (copy-list (remove-if (complement #'oddp) x))
                       (copy-seq (remove-if-not (complement #'oddp) x))))
               '(copy-list copy-seq remove-if remove-if-not complement))
""")
    ops = ["union", "nunion", "intersection", "nintersection", "set-difference", "nset-difference", "set-exclusive-or"]
    for i in range(n_rand):
        op = rng.choice(ops)
        l1 = [rng.randint(-6, 6) for _ in range(rng.randint(0, 8))]
        l2 = [rng.randint(-6, 6) for _ in range(rng.randint(0, 8))]
        use_key = rng.choice([False, True])
        l1_expr = f"(list {' '.join(map(str, l1))})" if l1 else "nil"
        l2_expr = f"(list {' '.join(map(str, l2))})" if l2 else "nil"
        key_args = " :key #'abs :test #'=" if use_key else ""
        body_expr = f"(mapcar #'abs ({op} a b{key_args}))" if use_key else f"({op} a b)"
        lines.append(
            f'(run-diff-case "D1-RAND-{i:03d}-{op}" '
            f"(lambda () (list {l1_expr} {l2_expr})) "
            f"'((a b) {body_expr}) '({op}) :canon-fn #'canon-set)"
        )
    return "\n".join(lines)


def build_domain2_sequences_arrays_lisp(rng: random.Random, n_rand: int) -> str:
    lines = ["\n;;; === DOMAIN 2: SEQUENCE, VECTOR & ARRAY BOUNDARIES ===\n"]
    lines.append(r"""
;; 2A. mismatch & search across empty, bounds, :from-end, constant patterns, displaced vectors
(dolist (from-end '(nil t))
  (dolist (pair (list
                 (list "empty-both" (lambda () (list "" "")))
                 (list "empty-pat" (lambda () (list "" "abc")))
                 (list "overlap-str" (lambda () (list "aaab" "aaaaab")))
                 (list "vec-ub8" (lambda () (list (make-array 3 :element-type '(unsigned-byte 8) :initial-contents '(1 2 1))
                                                  (make-array 7 :element-type '(unsigned-byte 8) :initial-contents '(1 2 1 2 1 2 1)))))
                 (list "disp-str" (lambda ()
                                    (let ((b (copy-seq "xxabcyyabczz")))
                                      (list (make-array 3 :element-type 'character :displaced-to b :displaced-index-offset 2)
                                            (make-array 8 :element-type 'character :displaced-to b :displaced-index-offset 2)))))
                 (list "fp-vec" (lambda ()
                                  (list (make-array 5 :fill-pointer 2 :initial-contents '(10 20 99 99 99))
                                        (make-array 6 :fill-pointer 4 :initial-contents '(0 10 20 30 10 20)))))))
    (let ((fe from-end)
          (nm (first pair))
          (th (second pair)))
      (run-diff-case (format nil "D2-SEARCH-~A-FE~A" nm fe)
                     th `((s1 s2) (search s1 s2 :from-end ',fe)) '(search))
      (run-diff-case (format nil "D2-MISMATCH-~A-FE~A" nm fe)
                     th `((s1 s2) (mismatch s1 s2 :from-end ',fe)) '(mismatch)))))

(run-diff-case "D2-SEARCH-SUBRANGE-FE-T"
               (lambda () (list (copy-seq "xxabyy") (copy-seq "zzabqqabww")))
               '((p s) (search p s :start1 2 :end1 4 :start2 1 :end2 9 :from-end t))
               '(search))
(run-diff-case "D2-SEARCH-CONST-PAT-FE-T"
               (lambda () (list (copy-seq "abaabaab")))
               '((s) (declare (type simple-string s)) (search "aab" s :start2 1 :end2 7 :from-end t))
               '(search))
(run-diff-case "D2-MISMATCH-SUBRANGE-FE-T"
               (lambda () (list (list 9 1 2 3 8) (vector 7 1 2 4 6)))
               '((s1 s2) (mismatch s1 s2 :start1 1 :end1 4 :start2 1 :end2 4 :from-end t))
               '(mismatch))

;; 2B. substitute / nsubstitute / remove / delete / remove-duplicates / delete-duplicates / reverse / nreverse
(dolist (cnt '(nil 0 -1 1 2))
  (dolist (fe '(nil t))
    (let ((c cnt) (f fe))
      (run-diff-case (format nil "D2-SUBST-VEC-C~A-FE~A" c f)
                     (lambda () (list 99 2 (vector 1 2 3 2 4 2 5)))
                     `((nw old s) (list (substitute nw old (fresh-copy s) :count ',c :from-end ',f :start 1 :end 6)
                                        (nsubstitute nw old (fresh-copy s) :count ',c :from-end ',f :start 1 :end 6)))
                     '(substitute nsubstitute))
      (run-diff-case (format nil "D2-REMOVE-LIST-C~A-FE~A" c f)
                     (lambda () (list 2 (list 2 1 2 3 2 4 2)))
                     `((item s) (list (remove item (fresh-copy s) :count ',c :from-end ',f :start 1 :end 6)
                                      (delete item (fresh-copy s) :count ',c :from-end ',f :start 1 :end 6)))
                     '(remove delete)))))

(dolist (fe '(nil t))
  (let ((f fe))
    (run-diff-case (format nil "D2-REMDUP-LARGE250-FE~A" f)
                   (lambda ()
                     (list (loop for i from 0 below 250 collect (- (mod i 37) 18))))
                   `((s) (list (remove-duplicates (fresh-copy s) :from-end ',f :start 10 :end 240 :key #'abs :test #'=)
                               (delete-duplicates (fresh-copy s) :from-end ',f :start 10 :end 240 :key #'abs :test #'=)))
                   '(remove-duplicates delete-duplicates))))

(dolist (len '(0 1 63 64 65 129))
  (let ((n len))
    (run-diff-case (format nil "D2-REVERSE-NREVERSE-BV-L~D" n)
                   (lambda () (list (make-det-bv n 41)))
                   '((bv) (list (reverse bv) (nreverse (fresh-copy bv))))
                   '(reverse nreverse))))
(run-diff-case "D2-REVERSE-NREVERSE-DISP-FP"
               (lambda ()
                 (let ((fp (make-array 6 :fill-pointer 4 :initial-contents '(1 2 3 4 99 99)))
                       (dp (make-array 4 :element-type 'character :displaced-to (copy-seq "xxabcdyy") :displaced-index-offset 2)))
                   (list fp dp)))
               '((fp dp) (list (reverse fp) (nreverse (fresh-copy fp)) (reverse dp) (nreverse (fresh-copy dp))))
               '(reverse nreverse))

;; 2C. merge / sort / stable-sort (stability + specialized vectors + return-type postconditions)
(run-diff-case "D2-STABLE-SORT-LIST-VEC"
               (lambda ()
                 (let ((items (list (cons 2 'a) (cons 1 'b) (cons 2 'c) (cons 1 'd) (cons 3 'e) (cons 2 'f))))
                   (list (fresh-copy items) (coerce (fresh-copy items) 'vector))))
               '((lst vec)
                 (list (stable-sort lst #'< :key #'car)
                       (stable-sort vec #'< :key #'car)))
               '(stable-sort))
(run-diff-case "D2-MERGE-STABILITY"
               (lambda ()
                 (list (list (cons 1 'a1) (cons 2 'a2) (cons 4 'a4))
                       (vector (cons 1 'b1) (cons 2 'b2) (cons 3 'b3))))
               '((s1 s2) (merge 'list s1 s2 #'< :key #'car))
               '(merge))
(run-diff-case "D2-MERGE-NONEMPTY-TO-NULL"
               (lambda () (list (list 1) (list 2)))
               '((s1 s2) (merge 'null s1 s2 #'<)) '(merge))
(run-diff-case "D2-MERGE-EMPTY-TO-CONS"
               (lambda () (list nil nil))
               '((s1 s2) (merge 'cons s1 s2 #'<)) '(merge))
(run-diff-case "D2-MERGE-VEC-LEN-MISMATCH"
               (lambda () (list (list 1 3) (list 2 4)))
               '((s1 s2) (merge '(vector t 2) s1 s2 #'<)) '(merge))

;; 2D. reduce & derive-type checks (excluding known HC-W3-5 reduce #'logior)
(dolist (fe '(nil t))
  (let ((f fe))
    (run-diff-case (format nil "D2-REDUCE-APPEND-EMPTY-FE~A" f)
                   (lambda () (list nil))
                   `((s) (reduce #'append s :from-end ',f)) '(reduce))
    (run-diff-case (format nil "D2-REDUCE-APPEND-SINGLE-ATOM-FE~A" f)
                   (lambda () (list (vector 42)))
                   `((s) (reduce #'append s :from-end ',f)) '(reduce))
    (run-diff-case (format nil "D2-REDUCE-APPEND-DOTTED-TAIL-FE~A" f)
                   (lambda () (list (list (list 1 2) (list 3) 'atom-end)))
                   `((s) (reduce #'append s :from-end ',f)) '(reduce))
    (run-diff-case (format nil "D2-REDUCE-APPEND-IV-FE~A" f)
                   (lambda () (list (list (list 1 2) (list 3))))
                   `((s) (reduce #'append s :from-end ',f :initial-value (list 9))) '(reduce))))

(run-diff-case "D2-REDUCE-PLUS-EMPTY-SFLOAT-TYPEP"
               (lambda () (list (make-array 0 :element-type 'single-float)))
               '((v) (declare (type (simple-array single-float (*)) v))
                 (let ((r (reduce #'+ v)))
                   (list r (typep r 'integer) (typep r 'single-float))))
               '(reduce))
(run-diff-case "D2-REDUCE-PLUS-UB8-NEG-IV"
               (lambda () (list (make-array 2 :element-type '(unsigned-byte 8) :initial-element 1)))
               '((v) (declare (type (simple-array (unsigned-byte 8) (2)) v))
                 (let ((r (reduce #'+ v :initial-value -5)))
                   (list r (< r 0) (typep r '(integer * -1)))))
               '(reduce))
(run-diff-case "D2-REDUCE-MUL-EMPTY-FIXVEC"
               (lambda () (list (make-array 0 :element-type '(integer 10 20) :initial-element 10)))
               '((v) (let ((r (reduce #'* v))) (list r (= r 1))))
               '(reduce))
(run-diff-case "D2-REDUCE-LOGAND-EMPTY"
               (lambda () (list (make-array 0 :element-type '(unsigned-byte 8))))
               '((v) (let ((r (reduce #'logand v))) (list r (< r 0))))
               '(reduce))

;; 2E. replace (overlapping same-sequence forward/backward across specialized types + displaced aliasing!)
(dolist (shifts '((0 4 2 6) (2 6 0 4) (1 5 1 5) (2 2 0 0)))
  (destructuring-bind (s1 e1 s2 e2) shifts
    (let ((s1 s1) (e1 e1) (s2 s2) (e2 e2))
      (run-diff-case (format nil "D2-REPLACE-SELF-LIST-~D-~D-~D-~D" s1 e1 s2 e2)
                     (lambda () (list (list 10 20 30 40 50 60 70 80)))
                     `((x) (replace x x :start1 ,s1 :end1 ,e1 :start2 ,s2 :end2 ,e2)) '(replace))
      (run-diff-case (format nil "D2-REPLACE-SELF-BV-~D-~D-~D-~D" s1 e1 s2 e2)
                     (lambda () (list (make-array 8 :element-type 'bit :initial-contents '(1 0 1 1 0 0 1 0))))
                     `((x) (replace x x :start1 ,s1 :end1 ,e1 :start2 ,s2 :end2 ,e2)) '(replace))
      (run-diff-case (format nil "D2-REPLACE-SELF-STR-~D-~D-~D-~D" s1 e1 s2 e2)
                     (lambda () (list (copy-seq "abcdefgh")))
                     `((x) (replace x x :start1 ,s1 :end1 ,e1 :start2 ,s2 :end2 ,e2)) '(replace))
      (run-diff-case (format nil "D2-REPLACE-SELF-UB8-~D-~D-~D-~D" s1 e1 s2 e2)
                     (lambda () (list (make-array 8 :element-type '(unsigned-byte 8) :initial-contents '(1 2 3 4 5 6 7 8))))
                     `((x) (replace x x :start1 ,s1 :end1 ,e1 :start2 ,s2 :end2 ,e2)) '(replace)))))

;; 2F. map / map-into / concatenate / coerce / make-sequence boundary types!
(run-diff-case "D2-MAP-INTO-FILLPTR-SHRINK"
               (lambda ()
                 (list (make-array 6 :fill-pointer 5 :initial-contents '(10 20 30 40 50 60))
                       (list 1 2)))
               '((dst src) (map-into dst #'1+ src) (list (fill-pointer dst) dst))
               '(map-into))
(run-diff-case "D2-MAP-INTO-FILLPTR-GROW"
               (lambda ()
                 (list (make-array 6 :fill-pointer 1 :initial-contents '(10 20 30 40 50 60))
                       (list 1 2 3 4)))
               '((dst src) (map-into dst #'1+ src) (list (fill-pointer dst) dst))
               '(map-into))
(run-diff-case "D2-MAP-INTO-ZERO-SEQS-FP"
               (lambda () (list (make-array 4 :fill-pointer 1 :initial-element 0)))
               '((dst) (let ((k 0)) (map-into dst (lambda () (incf k)))) (list (fill-pointer dst) dst))
               '(map-into))

(run-diff-case "D2-COERCE-EMPTY-TO-NULL"
               (lambda () (list #()))
               '((x) (coerce x 'null)) '(coerce))
(run-diff-case "D2-COERCE-NONEMPTY-TO-NULL"
               (lambda () (list #(1 2 3)))
               '((x) (coerce x 'null)) '(coerce))
(run-diff-case "D2-COERCE-EMPTY-TO-CONS"
               (lambda () (list #()))
               '((x) (coerce x 'cons)) '(coerce))
(run-diff-case "D2-MAP-NONEMPTY-TO-NULL"
               (lambda () (list (list 1 2 3)))
               '((x) (map 'null #'identity x)) '(map))
(run-diff-case "D2-MAP-EMPTY-TO-CONS"
               (lambda () (list nil))
               '((x) (map 'cons #'identity x)) '(map))
(run-diff-case "D2-MAP-STR-LEN-MISMATCH"
               (lambda () (list "abcd"))
               '((x) (map '(string 2) #'identity x)) '(map))
(run-diff-case "D2-CONCAT-STR-LEN-MISMATCH"
               (lambda () (list "abc" "def"))
               '((a b) (concatenate '(string 2) a b)) '(concatenate))
(run-diff-case "D2-CONCAT-SIMPLESTR-LEN-MISMATCH"
               (lambda () (list "abc" "def"))
               '((a b) (concatenate '(simple-string 2) a b)) '(concatenate))
(run-diff-case "D2-CONCAT-NONEMPTY-TO-NULL"
               (lambda () (list "a" "b"))
               '((a b) (concatenate 'null a b)) '(concatenate))
(run-diff-case "D2-CONCAT-EMPTY-TO-CONS"
               (lambda () (list "" ""))
               '((a b) (concatenate 'cons a b)) '(concatenate))
(run-diff-case "D2-CONCAT-NIL-TYPE"
               (lambda () (list "a" "b"))
               '((a b) (concatenate nil a b)) '(concatenate))
(run-diff-case "D2-MAKE-SEQUENCE-NIL-TYPE"
               (lambda () (list 3))
               '((n) (make-sequence nil n)) '(make-sequence))
(run-diff-case "D2-COERCE-INT-TO-NIL-TYPE"
               (lambda () (list 5))
               '((x) (coerce x nil)) '(coerce))
(run-diff-case "D2-COERCE-CHAR-TO-NIL-TYPE"
               (lambda () (list #\a))
               '((x) (coerce x nil)) '(coerce))
(run-diff-case "D2-COERCE-FLOAT-RANGE-VIOLATION"
               (lambda () (list 5))
               '((x) (coerce x '(double-float 10.0d0 20.0d0))) '(coerce))
(run-diff-case "D2-COERCE-NON-STANDARD-CHAR"
               (lambda () (list (string (code-char 233))))
               '((x) (coerce x 'standard-char)) '(coerce))
(run-diff-case "D2-COERCE-VEC-LEN-MISMATCH"
               (lambda () (list (list 1 2 3)))
               '((x) (coerce x '(vector t 2))) '(coerce))
(run-diff-case "D2-COERCE-VEC-LEN-HANDLER-CASE"
               (lambda () (list (list 1 2 3)))
               '((x) (handler-case (coerce x '(vector t 2)) (type-error () :caught-type-error))) '(coerce))
(run-diff-case "D2-COERCE-CPLX-RATIONAL-ONE"
               (lambda () (list 5))
               '((x) (coerce x '(complex rational))) '(coerce))

;; 2G. find / position / count SIMD & float signed-zero boundaries
(dolist (len '(0 1 15 16 17 31 32 33 64 65))
  (dolist (fe '(nil t))
    (let ((n len) (f fe))
      (run-diff-case (format nil "D2-POS-UB8-L~D-FE~A" n f)
                     (lambda ()
                       (let ((v (make-array n :element-type '(unsigned-byte 8) :initial-element 3)))
                         (when (> n 0) (setf (aref v 0) 99) (setf (aref v (1- n)) 99))
                         (list 99 v)))
                     `((it v) (declare (type (simple-array (unsigned-byte 8) (*)) v))
                       (list (position it v :from-end ',f) (find it v :from-end ',f)))
                     '(position find))
      (run-diff-case (format nil "D2-POS-SB32-L~D-FE~A" n f)
                     (lambda ()
                       (let ((v (make-array n :element-type '(signed-byte 32) :initial-element -7)))
                         (when (> n 0) (setf (aref v (floor n 2)) -123456))
                         (list -123456 v)))
                     `((it v) (declare (type (simple-array (signed-byte 32) (*)) v))
                       (position it v :from-end ',f))
                     '(position)))))

(dolist (tst '(eql = equal equalp))
  (let ((ts tst))
    (run-diff-case (format nil "D2-FIND-NEGZERO-DF-~A" ts)
                   (lambda ()
                     (let ((v (make-array 3 :element-type 'double-float
                                          :initial-contents (list 1.0d0 0.0d0 2.0d0))))
                       (list -0.0d0 v)))
                   `((it v) (declare (type (simple-array double-float (*)) v))
                     (list (position it v :test #',ts) (count it v :test #',ts)))
                   '(position count))))

(run-diff-case "D2-QUANTIFIERS-MULTI-SHORTCIRCUIT"
               (lambda () (list (list 1 2 :boom) (vector 10 20)))
               '((s1 s2)
                 (list (if (every #'< s1 s2) t nil)
                       (if (some #'> s1 s2) t nil)
                       (if (notany #'> s1 s2) t nil)
                       (if (notevery #'< s1 s2) t nil)))
               '(every some notany notevery))

;; 2H. adjust-array: 0D, 1D, 2D, and displacing adjustable arrays to adjustable/header arrays!
(run-diff-case "D2-ADJUST-ARRAY-DISP-TO-ADJUSTABLE"
               (lambda ()
                 (let ((target (make-array 4 :adjustable t :initial-contents (list 10 20 30 40)))
                       (arr (make-array 3 :adjustable t :initial-contents (list 1 2 3))))
                   (list arr target)))
               '((arr target)
                 (let ((res (adjust-array arr 3 :displaced-to target :displaced-index-offset 0)))
                   (declare (type (vector t) res))
                   (list (aref res 0) (aref res 1) (aref res 2))))
               '(adjust-array aref))

(run-diff-case "D2-ADJUST-ARRAY-DISP-TO-2D-HEADER"
               (lambda ()
                 (let ((target (make-array '(2 3) :initial-contents (list (list 10 20 30) (list 40 50 60))))
                       (arr (make-array 3 :adjustable t :initial-contents (list 1 2 3))))
                   (list arr target)))
               '((arr target)
                 (let ((res (adjust-array arr 3 :displaced-to target :displaced-index-offset 0)))
                   (declare (type (vector t) res))
                   (list (aref res 0) (aref res 1) (aref res 2))))
               '(adjust-array aref))

(run-diff-case "D2-ADJUST-ARRAY-0D-INIT-CONTENTS"
               (lambda () (list (make-array nil :adjustable t :initial-element 'old)))
               '((a0)
                 (let ((r (adjust-array a0 nil :initial-contents 'new)))
                   (aref r)))
               '(adjust-array aref))

(run-diff-case "D2-ADJUST-ARRAY-0D-NONADJ-INIT-CONTENTS"
               (lambda () (list (make-array nil :initial-element 'old)))
               '((a0)
                 (let ((r (adjust-array a0 nil :initial-contents 'new)))
                   (aref r)))
               '(adjust-array aref))

(run-diff-case "D2-ADJUST-ARRAY-2D-GROW-INIT-ELT"
               (lambda () (list (make-array '(2 2) :adjustable t :initial-contents '((1 2) (3 4)))))
               '((a2) (adjust-array a2 '(3 3) :initial-element 0))
               '(adjust-array))
""")
    for i in range(n_rand):
        kind = rng.choice(["subseq-fill", "remove-if", "substitute", "search", "count"])
        ln = rng.randint(0, 12)
        elems = [rng.randint(-5, 5) for _ in range(ln)]
        s = rng.randint(0, ln)
        e = rng.randint(s, ln)
        fe = "t" if rng.choice([False, True]) else "nil"
        vec_expr = f"(vector {' '.join(map(str, elems))})" if elems else "(vector)"
        if kind == "subseq-fill":
            lines.append(
                f'(run-diff-case "D2-RAND-{i:03d}-SUBFILL" (lambda () (list {vec_expr})) '
                f"'((v) (let ((sub (subseq v {s} {e}))) (fill v 99 :start {s} :end {e}) (list sub v))) '(subseq fill))"
            )
        elif kind == "remove-if":
            cnt = rng.choice(["nil", "0", "1", "2"])
            lines.append(
                f'(run-diff-case "D2-RAND-{i:03d}-REMIF" (lambda () (list {vec_expr})) '
                f"'((v) (list (remove-if #'evenp (fresh-copy v) :start {s} :end {e} :from-end '{fe} :count '{cnt}) "
                f"(delete-if #'evenp (fresh-copy v) :start {s} :end {e} :from-end '{fe} :count '{cnt}))) '(remove-if delete-if))"
            )
        elif kind == "substitute":
            item = rng.randint(-5, 5)
            cnt = rng.choice(["nil", "0", "-1", "1", "2"])
            lines.append(
                f'(run-diff-case "D2-RAND-{i:03d}-SUBST" (lambda () (list {vec_expr})) '
                f"'((v) (list (substitute 77 {item} (fresh-copy v) :start {s} :end {e} :from-end '{fe} :count '{cnt}) "
                f"(nsubstitute 77 {item} (fresh-copy v) :start {s} :end {e} :from-end '{fe} :count '{cnt}))) '(substitute nsubstitute))"
            )
        elif kind == "search":
            pat = [rng.randint(-5, 5) for _ in range(rng.randint(0, 3))]
            pat_expr = f"(vector {' '.join(map(str, pat))})" if pat else "(vector)"
            lines.append(
                f'(run-diff-case "D2-RAND-{i:03d}-SEARCH" (lambda () (list {pat_expr} {vec_expr})) '
                f"'((p v) (search p v :start2 {s} :end2 {e} :from-end '{fe})) '(search))"
            )
        else:
            item = rng.randint(-5, 5)
            lines.append(
                f'(run-diff-case "D2-RAND-{i:03d}-COUNT" (lambda () (list {vec_expr})) '
                f"'((v) (list (count {item} v :start {s} :end {e} :from-end '{fe}) "
                f"(position {item} v :start {s} :end {e} :from-end '{fe}))) '(count position))"
            )
    return "\n".join(lines)


def build_domain3_bitvectors_lisp(rng: random.Random, n_rand: int) -> str:
    lines = ["\n;;; === DOMAIN 3: BIT-VECTOR & MULTI-D BIT-ARRAY BOUNDARIES ===\n"]
    lines.append(r"""
(dolist (op '(bit-and bit-ior bit-xor bit-eqv bit-nand bit-nor bit-andc1 bit-andc2 bit-orc1 bit-orc2))
  (dolist (len '(0 1 63 64 65 127 128 129))
    (let ((o op) (n len))
      (run-diff-case (format nil "D3-BV-~A-L~D" o n)
                     (lambda () (list (make-det-bv n 17) (make-det-bv n 53)))
                     `((b1 b2)
                       (let ((c1 (fresh-copy b1))
                             (c2 (fresh-copy b2)))
                         (list (,o b1 b2)
                               (,o c1 b2 t)
                               (,o b1 c2 c2))))
                     (list o))))
  (let ((o op))
    (run-diff-case (format nil "D3-BV-DISP-~A" o)
                   (lambda ()
                     (let* ((backing (make-det-bv 220 91))
                            (b1 (make-array 65 :element-type 'bit :displaced-to backing :displaced-index-offset 7))
                            (b2 (make-array 65 :element-type 'bit :displaced-to backing :displaced-index-offset 31))
                            (dst (make-array 65 :element-type 'bit :displaced-to (fresh-copy backing) :displaced-index-offset 19)))
                       (list b1 b2 dst)))
                   `((b1 b2 dst) (list (,o b1 b2 nil) (,o b1 b2 dst)))
                   (list o))
    (run-diff-case (format nil "D3-BIT2D-~A" o)
                   (lambda ()
                     (let ((a1 (make-array '(9 9) :element-type 'bit))
                           (a2 (make-array '(9 9) :element-type 'bit)))
                       (dotimes (i 81)
                         (setf (row-major-aref a1 i) (mod i 2)
                               (row-major-aref a2 i) (mod (floor i 2) 2)))
                       (list a1 a2)))
                   `((a1 a2) (list (,o a1 a2) (,o (fresh-copy a1) a2 t)))
                   (list o))))

(run-diff-case "D3-BV-BIT-ORC2-ZEROS-192"
               (lambda () (list (make-array 192 :element-type 'bit :initial-element 0)
                                (make-array 192 :element-type 'bit :initial-element 0)))
               '((z1 z2)
                 (let ((r (bit-orc2 z1 z2)))
                   (list (count 1 r) (sbit r 127) (sbit r 128) (sbit r 191))))
               '(bit-orc2))

(dolist (len '(0 1 63 64 65 127 128 129))
  (let ((n len))
    (run-diff-case (format nil "D3-BIT-NOT-L~D" n)
                   (lambda ()
                     (let* ((backing (make-det-bv (+ n 20) 37))
                            (disp (make-array n :element-type 'bit :displaced-to backing :displaced-index-offset 11)))
                       (list (make-det-bv n 23) disp)))
                   '((b disp) (list (bit-not b) (bit-not (fresh-copy b) t) (bit-not disp)))
                   '(bit-not))))
""")
    bit_ops = ["bit-and", "bit-ior", "bit-xor", "bit-eqv", "bit-nand", "bit-nor", "bit-andc1", "bit-andc2", "bit-orc1", "bit-orc2"]
    for i in range(n_rand):
        op = rng.choice(bit_ops)
        ln = rng.choice([0, 1, 31, 32, 33, 63, 64, 65, 127, 128, 129])
        s1 = rng.randint(1, 10000)
        s2 = rng.randint(1, 10000)
        lines.append(
            f'(run-diff-case "D3-RAND-{i:03d}-{op}-L{ln}" '
            f"(lambda () (list (make-det-bv {ln} {s1}) (make-det-bv {ln} {s2}))) "
            f"'((a b) ({op} a b)) '({op}))"
        )
    return "\n".join(lines)


def build_domain4_chars_strings_lisp() -> str:
    return r"""
;;; === DOMAIN 4: CHARACTER & STRING BOUNDARY PRIMITIVES ===

(defun titlecase-w3-code-p (code)
  (or (<= 452 code 460) (<= 497 code 499)))

(let ((case-chars nil)
      (both-case-violations nil)
      (order-violations nil)
      (buckets (make-hash-table :test 'eql)))
  (dotimes (i char-code-limit)
    (let ((c (code-char i)))
      (when c
        (let ((u (char-upcase c))
              (d (char-downcase c)))
          (when (and (or (not (eql c u)) (not (eql c d)))
                     (not (both-case-p c)))
            (when (< (length both-case-violations) 10)
              (push (list i (char-code u) (char-code d)) both-case-violations)))
          (when (or (not (eql c u)) (not (eql c d)) (both-case-p c) (upper-case-p c) (lower-case-p c))
            (push c case-chars)
            (let ((k (min i (char-code u) (char-code d)
                          (char-code (char-downcase u))
                          (char-code (char-upcase d)))))
              (push c (gethash k buckets))))))))
  (maphash
   (lambda (k cs)
     (declare (ignore k))
     (dolist (a cs)
       (dolist (b cs)
         (unless (or (titlecase-w3-code-p (char-code a))
                     (titlecase-w3-code-p (char-code b)))
           (let ((ce1 (char-equal a b))
                 (ce2 (char-equal b a))
                 (cne (char-not-equal a b))
                 (cl (char-lessp a b))
                 (cg (char-greaterp a b))
                 (cng (char-not-greaterp a b))
                 (cnl (char-not-lessp a b)))
             (when (or (not (eq ce1 ce2))
                       (not (eq cne (not ce1)))
                       (and ce1 (or cl cg))
                       (and cng cnl (not ce1)))
               (when (< (length order-violations) 10)
                 (push (list (char-code a) (char-code b) ce1 ce2 cl cg cng cnl) order-violations))))))))
   buckets)
  (record-check "D4-UNICODE-BOTH-CASE-INVARIANT"
                (if both-case-violations "FAIL" "OK")
                (when both-case-violations (prin1-to-string (nreverse both-case-violations))))
  (record-check "D4-UNICODE-ORDER-EQUIV-INVARIANT"
                (if order-violations "FAIL" "OK")
                (when order-violations (prin1-to-string (nreverse order-violations)))))

(dolist (code '(0 65 97 127 128 181 223 255 256 383 931 962 963 65535))
  (let ((ch (code-char code)))
    (when ch
      (dolist (op '(char< char<= char> char>= char/= char-lessp char-greaterp char-not-greaterp char-not-lessp))
        (run-diff-case (format nil "D4-CHAR-CONST-~A-~D" op code)
                       (lambda () (list (list (code-char 0) #\A #\a #\z (code-char 200) ch)))
                       `((xs) (mapcar (lambda (x) (declare (type character x)) (if (,op x ,ch) t nil)) xs))
                       (list op))))))

(dolist (args '((0 10) (9 10) (10 10) (15 16) (35 36) (36 36) (#x10000000000000000 10)))
  (let ((w (first args)) (r (second args)))
    (run-diff-case (format nil "D4-DIGIT-CHAR-~D-~D" w r)
                   (lambda () (list w r))
                   '((weight radix) (digit-char weight radix))
                   '(digit-char))))

(let ((make-s-pairs
        (list
         (list "base-base"
               (lambda () (list (coerce "xxAbCdef" 'simple-base-string)
                                (coerce "yyabczzz" 'simple-base-string))))
         (list "base-ucs4"
               (lambda () (list (coerce "xxAbCdef" 'simple-base-string)
                                (make-array 8 :element-type 'character
                                            :initial-contents (list #\y #\y #\a #\b #\c (code-char 955) #\z #\z)))))
         (list "ucs4-base"
               (lambda () (list (make-array 8 :element-type 'character
                                            :initial-contents (list #\x #\x #\A #\b #\C (code-char 955) #\e #\f))
                                (coerce "yyabczzz" 'simple-base-string))))
         (list "disp-disp"
               (lambda ()
                 (let ((b1 (copy-seq "00xxAbCdef00"))
                       (b2 (copy-seq "11yyabczzz11")))
                   (list (make-array 8 :element-type 'character :displaced-to b1 :displaced-index-offset 2)
                         (make-array 8 :element-type 'character :displaced-to b2 :displaced-index-offset 2))))))))
  (dolist (sp make-s-pairs)
    (let ((nm (first sp))
          (th (second sp)))
      (dolist (op '(string= string/= string< string<= string> string>=
                    string-equal string-not-equal string-lessp string-greaterp
                    string-not-greaterp string-not-lessp))
        (run-diff-case (format nil "D4-STRCMP-~A-~A" op nm)
                       th
                       `((s1 s2)
                         (list (,op s1 s2 :start1 2 :end1 6 :start2 2 :end2 6)
                               (,op s1 s2 :start1 2 :end1 5 :start2 2 :end2 5)
                               (,op s1 s2 :start1 2 :end1 2 :start2 4 :end2 4)))
                       (list op))))))

(run-diff-case "D4-STRING-CAPITALIZE-START-MIDWORD"
               (lambda () (list (copy-seq "helloWORLD") (copy-seq "helloWORLD")))
               '((s1 s2)
                 (list (string-capitalize s1 :start 5 :end 10)
                       (nstring-capitalize s2 :start 5 :end 10)))
               '(string-capitalize nstring-capitalize))

(run-diff-case "D4-STRING-UPDOWN-SUBRANGE"
               (lambda () (list (copy-seq "aBcDeFg")))
               '((s)
                 (list (string-upcase (fresh-copy s) :start 2 :end 5)
                       (nstring-upcase (fresh-copy s) :start 2 :end 5)
                       (string-downcase (fresh-copy s) :start 1 :end 6)
                       (nstring-downcase (fresh-copy s) :start 1 :end 6)))
               '(string-upcase nstring-upcase string-downcase nstring-downcase))

(run-diff-case "D4-STRING-TRIM-MIXED-CHARBAG"
               (lambda ()
                 (let ((bag (list #\Space (code-char 955) #\x))
                       (str (concatenate 'string (string (code-char 955)) "x hello x" (string (code-char 955)))))
                   (list bag str)))
               '((bag str)
                 (list (string-trim bag str)
                       (string-left-trim bag str)
                       (string-right-trim bag str)))
               '(string-trim string-left-trim string-right-trim))
"""


def build_domain5_hashtables_lisp() -> str:
    return r"""
;;; === DOMAIN 5: HASH-TABLE (EQ, EQL, EQUAL, EQUALP) & SXHASH INVARIANTS ===

(defun check-ht-equiv-pair (test-sym k1 k2 &key check-sxhash)
  (let ((eqv (funcall test-sym k1 k2)))
    (when eqv
      (let ((ht (make-hash-table :test test-sym)))
        (setf (gethash k1 ht) :first)
        (multiple-value-bind (val foundp) (gethash k2 ht)
          (setf (gethash k2 ht) :second)
          (let ((cnt (hash-table-count ht))
                (sx-ok (or (not check-sxhash) (= (sxhash k1) (sxhash k2)))))
            (unless (and foundp (eq val :first) (= cnt 1) sx-ok)
              (return-from check-ht-equiv-pair
                (format nil "MISMATCH(found=~S,cnt=~D,sx=~S)" foundp cnt sx-ok))))))
      #+ccl
      (let ((ht-priv (make-hash-table :test test-sym :shared nil)))
        (setf (gethash k1 ht-priv) :first)
        (multiple-value-bind (val foundp) (gethash k2 ht-priv)
          (setf (gethash k2 ht-priv) :second)
          (unless (and foundp (eq val :first) (= (hash-table-count ht-priv) 1))
            (return-from check-ht-equiv-pair
              (format nil "PRIV-MISMATCH(found=~S,cnt=~D)" foundp (hash-table-count ht-priv)))))))
    nil))

(let ((num-groups
        (list
         (list "zeros"
               0 0.0f0 -0.0f0 0.0d0 -0.0d0
               (complex 0.0f0 0.0f0) (complex -0.0f0 0.0f0) (complex 0.0f0 -0.0f0)
               (complex 0.0d0 0.0d0) (complex -0.0d0 -0.0d0))
         (list "ones"
               1 1.0f0 1.0d0 (complex 1.0f0 0.0f0) (complex 1.0d0 -0.0d0))
         (list "dyadic-ratios-float"
               1/2 0.5f0 0.5d0 (complex 1/2 0) (complex 0.5f0 0.0f0) (complex 0.5d0 -0.0d0))
         (list "neg-dyadic-ratios"
               -3/4 -0.75f0 -0.75d0 (complex -3/4 0) (complex -0.75d0 0.0d0))
         (list "complex-ratio-float"
               (complex 1/2 -1/4) (complex 0.5f0 -0.25f0) (complex 0.5d0 -0.25d0))
         (list "exact-pow2-fix-big"
               (ash 1 53) (float (ash 1 53) 1.0d0)
               (ash 1 60) (float (ash 1 60) 1.0d0)
               (ash 1 100) (float (ash 1 100) 1.0d0)))))
  (dolist (grp num-groups)
    (let ((gname (first grp))
          (items (rest grp))
          (bad nil))
      (dolist (x items)
        (dolist (y items)
          (when (equalp x y)
            (let ((err (check-ht-equiv-pair 'equalp x y)))
              (when (and err (null bad))
                (setf bad (format nil "~A vs ~A -> ~A" (canon x) (canon y) err)))))))
      (record-check (format nil "D5-EQUALP-HT-NUM-~A" gname)
                    (if bad "FAIL" "OK") bad))))

(let ((comp-groups
        (list
         (list "str-vec-disp"
               (coerce "AbCd" 'simple-base-string)
               (coerce "aBcD" '(simple-array character (*)))
               (vector #\a #\B #\c #\D)
               (make-array 4 :element-type 'character
                           :displaced-to (copy-seq "xxaBcDyy") :displaced-index-offset 2)
               (make-array 6 :element-type 'base-char :fill-pointer 4
                           :initial-contents '(#\A #\b #\C #\d #\z #\z)))
         (list "bv-numvec"
               #*1010
               (vector 1 0 1 0)
               (make-array 4 :element-type '(unsigned-byte 8) :initial-contents '(1 0 1 0))
               (make-array 4 :element-type 'double-float :initial-contents '(1.0d0 -0.0d0 1.0d0 0.0d0))
               (make-array 6 :fill-pointer 4 :initial-contents '(1 0 1 0 9 9)))
         (list "2d-arrays"
               (make-array '(2 2) :initial-contents '((1 2) (3 4)))
               (make-array '(2 2) :element-type 'double-float :initial-contents '((1.0d0 2.0d0) (3.0d0 4.0d0)))
               (make-array '(2 2) :displaced-to (vector 0 1 2 3 4 9) :displaced-index-offset 1))
         (list "0d-arrays"
               (make-array nil :initial-element 5)
               (make-array nil :initial-element 5.0d0))
         (list "structs-float-zeros"
               (make-fuzz-fbox 0.0d0 -0.0f0)
               (make-fuzz-fbox -0.0d0 0.0f0))
         (list "structs-ratio-float"
               (make-fuzz-point 1/2 "Abc")
               (make-fuzz-point 0.5d0 (vector #\a #\B #\c))))))
  (dolist (grp comp-groups)
    (let ((gname (first grp))
          (items (rest grp))
          (bad nil))
      (dolist (x items)
        (dolist (y items)
          (when (equalp x y)
            (let ((err (check-ht-equiv-pair 'equalp x y)))
              (when (and err (null bad))
                (setf bad (format nil "~A vs ~A -> ~A" (canon x) (canon y) err)))))))
      (record-check (format nil "D5-EQUALP-HT-COMP-~A" gname)
                    (if bad "FAIL" "OK") bad))))

(let ((eq-groups
        (list
         (list "strings"
               (coerce "hello" 'simple-base-string)
               (coerce "hello" '(simple-array character (*)))
               (make-array 5 :element-type 'character :displaced-to (copy-seq "xxhelloyy") :displaced-index-offset 2)
               (make-array 8 :element-type 'character :fill-pointer 5 :initial-contents '(#\h #\e #\l #\l #\o #\x #\y #\z)))
         (list "bitvectors"
               #*1101001
               (make-array 7 :element-type 'bit :displaced-to #*00110100111 :displaced-index-offset 2)
               (make-array 10 :element-type 'bit :fill-pointer 7 :initial-contents '(1 1 0 1 0 0 1 1 1 1)))
         (list "pathnames"
               (make-pathname :directory '(:relative "dir") :name "file" :type "lisp")
               (parse-namestring "dir/file.lisp")))))
  (dolist (grp eq-groups)
    (let ((gname (first grp))
          (items (rest grp))
          (bad nil))
      (dolist (x items)
        (dolist (y items)
          (when (equal x y)
            (let ((err (check-ht-equiv-pair 'equal x y :check-sxhash t)))
              (when (and err (null bad))
                (setf bad (format nil "~A vs ~A -> ~A" (canon x) (canon y) err)))))))
      (record-check (format nil "D5-EQUAL-SXHASH-~A" gname)
                    (if bad "FAIL" "OK") bad))))

(run-diff-case "D5-EQL-HT-SIGNED-ZEROS"
               (lambda () nil)
               '(()
                 (let ((ht1 (make-hash-table :test 'eql))
                       (ht2 (make-hash-table :test 'equal)))
                   (setf (gethash 0.0f0 ht1) :pos-sf (gethash -0.0f0 ht1) :neg-sf
                         (gethash 0.0d0 ht1) :pos-df (gethash -0.0d0 ht1) :neg-df)
                   (setf (gethash 0.0f0 ht2) :pos-sf (gethash -0.0f0 ht2) :neg-sf
                         (gethash 0.0d0 ht2) :pos-df (gethash -0.0d0 ht2) :neg-df)
                   (list (hash-table-count ht1) (gethash 0.0f0 ht1) (gethash -0.0f0 ht1)
                         (gethash 0.0d0 ht1) (gethash -0.0d0 ht1)
                         (hash-table-count ht2) (gethash 0.0f0 ht2) (gethash -0.0f0 ht2))))
               '(make-hash-table gethash))
"""


def build_domain6_numerics_lisp(rng: random.Random, n_rand: int) -> str:
    lines = ["\n;;; === DOMAIN 6: NUMERIC EDGE PRIMITIVES & TRANSFORMS ===\n"]
    lines.append(r"""
(let ((bvals (list 0 -1 1 -2 (1- (ash 1 59)) (- (ash 1 59)) (1- (ash 1 62)) (- (ash 1 62))
                   (ash 1 63) (- (ash 1 63)) (ash 1 64) (- (ash 1 64))
                   #x55555555555555555555 (- #x33333333333333333333)))
      (bops (list boole-clr boole-set boole-1 boole-2 boole-c1 boole-c2
                  boole-and boole-ior boole-xor boole-eqv boole-nand boole-nor
                  boole-andc1 boole-andc2 boole-orc1 boole-orc2)))
  (loop for op in bops
        for idx from 0
        do (let ((o op) (k idx))
             (run-diff-case (format nil "D6-BOOLE-OP~D" k)
                            (lambda () (list o bvals))
                            `((op-var xs)
                              (list
                               (loop for a in xs append (loop for b in xs collect (boole ,o a b)))
                               (loop for a in xs append (loop for b in xs collect (boole op-var a b)))))
                            '(boole)))))

(run-diff-case "D6-GCD-ZERO-ARG"
               (lambda () nil)
               '(() (gcd))
               '(gcd))

(run-diff-case "D6-GCD-LCM-VARIADIC"
               (lambda () (list 0 -1 (- (ash 1 59)) (- (ash 1 62)) (ash -1 63) (ash -1 64) (* 12 (ash 1 70)) (* 18 (ash 1 70))))
               '((z m1 mn59 mn62 w63 w64 b1 b2)
                 (list (lcm)
                       (gcd m1) (gcd mn59) (gcd mn62) (gcd w63) (gcd w64)
                       (lcm m1) (lcm mn59) (lcm mn62) (lcm z b1) (lcm b1 z)
                       (gcd b1 b2) (lcm b1 b2)
                       (gcd 48 -18 30) (lcm 12 -18 20)))
               '(gcd lcm))

(let ((isqrt-inputs
        (loop for k in '(0 1 2 3 4 7 8 9 15 16 24 25 31 32 60 62 63 64 65 127 128)
              for p = (ash 1 k)
              for sq = (* p p)
              append (if (> sq 0) (list (max 0 (1- p)) p (1+ p) (1- sq) sq (1+ sq)) (list 0)))))
  (run-diff-case "D6-ISQRT-BOUNDARIES"
                 (lambda () (list isqrt-inputs))
                 '((ns)
                   (mapcar (lambda (n)
                             (let ((r (isqrt n)))
                               (list r (<= (* r r) n) (< n (* (1+ r) (1+ r))))))
                           ns))
                 '(isqrt)))

(run-diff-case "D6-EXPT-ZERO-POWERS"
               (lambda () (list 0 0.0f0 -0.0f0 0.0d0 -0.0d0 (complex 0 0) (complex 0.0d0 0.0d0) 1/2 -2))
               '((z zsf nzsf zdf nzdf zc zcdf half m2)
                 (list (expt z 0) (expt zsf 0) (expt nzsf 0) (expt zdf 0) (expt nzdf 0)
                       (expt zc 0) (expt zcdf 0)
                       (expt zsf 0.0f0) (expt zdf 0.0d0)
                       (expt half -4) (expt m2 63)))
               '(expt))

(let ((floats (list 0.0f0 -0.0f0 least-positive-single-float least-negative-single-float
                    least-positive-normalized-single-float most-positive-single-float most-negative-single-float
                    0.0d0 -0.0d0 least-positive-double-float least-negative-double-float
                    least-positive-normalized-double-float most-positive-double-float most-negative-double-float
                    0.1f0 0.1d0 0.3d0 (float pi 1.0d0) (- (float pi 1.0f0))
                    (scale-float 1.0d0 -1074) (scale-float 3.0d0 -1074) (scale-float 1.5d0 -1022))))
  (run-diff-case "D6-RATIONAL-ROUNDTRIP"
                 (lambda () (list floats))
                 '((fs)
                   (mapcar (lambda (f)
                             (let ((r1 (rational f))
                                   (r2 (rationalize f)))
                               (list (= f (float r1 f))
                                     (= f (float r2 f))
                                     r1)))
                           fs))
                 '(rational rationalize float)))

(run-diff-case "D6-SIGNUM-SIGNED-ZEROS"
               (lambda () (list 0 5 -5 0.0f0 -0.0f0 0.0d0 -0.0d0
                                (complex 0.0d0 -0.0d0) (complex -0.0d0 0.0d0) (complex 3 4)))
               '((z p5 m5 zsf nzsf zdf nzdf cz1 cz2 c34)
                 (list (signum z) (signum p5) (signum m5)
                       (signum zsf) (signum nzsf) (signum zdf) (signum nzdf)
                       (signum cz1) (signum cz2) (signum c34)))
               '(signum))

(run-diff-case "D6-FLOAT-DECODE-SCALE"
               (lambda () (list 0.0f0 -0.0f0 0.0d0 -0.0d0 -1.5d0
                                least-positive-double-float least-negative-single-float))
               '((zsf nzsf zdf nzdf m15 lpdf lnsf)
                 (flet ((info (f)
                          (multiple-value-bind (d de ds) (decode-float f)
                            (multiple-value-bind (id ide ids) (integer-decode-float f)
                              (list d de ds id ide ids
                                    (float-radix f) (float-digits f) (float-precision f)
                                    (float-sign f) (float-sign f 2.0f0)
                                    (scale-float d de))))))
                   (mapcar #'info (list zsf nzsf zdf nzdf m15 lpdf lnsf))))
               '(decode-float integer-decode-float float-radix float-digits float-precision float-sign scale-float))

(run-diff-case "D6-FFLOOR-FCEILING-FTRUNCATE-FROUND"
               (lambda () (list -0.5d0 0.5d0 -2.5f0 2.5f0 -7 3))
               '((nd pd nsf psf i1 i2)
                 (flet ((all4 (x)
                          (list (multiple-value-list (ffloor x))
                                (multiple-value-list (fceiling x))
                                (multiple-value-list (ftruncate x))
                                (multiple-value-list (fround x)))))
                   (list (all4 nd) (all4 pd) (all4 nsf) (all4 psf)
                         (multiple-value-list (ffloor i1 i2))
                         (multiple-value-list (fceiling i1 i2)))))
               '(ffloor fceiling ftruncate fround))

(run-diff-case "D6-BRANCH-CUTS-SIGNED-ZERO-SIGNS"
               (lambda ()
                 (list -0.0d0 0.0d0 -1.0d0 1.0d0
                       (complex -1.0d0 0.0d0) (complex -1.0d0 -0.0d0)
                       (complex -4.0d0 0.0d0) (complex -4.0d0 -0.0d0)))
               '((nz pz m1 p1 cm0 cmn c4p c4n)
                 (declare (ignore p1))
                 (list (< (atan nz m1) 0)
                       (> (atan pz m1) 0)
                       (> (phase cm0) 0)
                       (< (phase cmn) 0)
                       (> (imagpart (log cm0)) 0)
                       (< (imagpart (log cmn)) 0)
                       (>= (imagpart (sqrt c4p)) 0)
                       (<= (imagpart (sqrt c4n)) 0)
                       (float-sign (imagpart (sqrt c4p)))
                       (float-sign (imagpart (sqrt c4n)))))
               '(atan phase log sqrt imagpart float-sign))

(run-diff-case "D6-UPGRADED-COMPLEX-PART-TYPE"
               (lambda () (list 'fixnum 'integer 'rational 'single-float 'double-float 'real))
               '((ts)
                 (mapcar (lambda (ty)
                           (let ((ut (upgraded-complex-part-type ty)))
                             (subtypep ty ut)))
                         ts))
               '(upgraded-complex-part-type))
""")
    for i in range(n_rand):
        a = rng.choice([0, 1, -1, 2, -2, 7, -15, (1 << 61) - 1, -(1 << 61), (1 << 65) + 13, -((1 << 65) + 29)])
        b = rng.choice([0, 1, -1, 3, -3, 12, -18, (1 << 60) + 5, -((1 << 64) + 7)])
        bop = rng.randint(0, 15)
        lines.append(
            f'(run-diff-case "D6-RAND-{i:03d}" (lambda () (list {a} {b})) '
            f"'((a b) (list (boole {bop} a b) (gcd a b) (isqrt (abs a)))) '(boole gcd isqrt))"
        )
    return "\n".join(lines)


LISP_EPILOGUE = r"""
(execute-queued-batches 48)

;;; === EMIT TAB-SEPARATED REPORT ===
(format t "~&===W4-META total_cases=~D total_evals=~D intra_diffs=~D===~%"
        *total-cases* *total-evals* (length *intra-diffs*))
(let ((keys nil))
  (maphash (lambda (k v) (declare (ignore v)) (push k keys)) *results*)
  (setf keys (sort keys #'string<))
  (dolist (k keys)
    (destructuring-bind (s3 s1 ni) (gethash k *results*)
      (format t "===W4-RES~C~A~C~A~C~A~C~A~%" #\Tab k #\Tab s3 #\Tab s1 #\Tab ni))))
(finish-output)
"""


def generate_lisp_suite(seed: int, random_cases_per_domain: int) -> str:
    rng = random.Random(seed)
    parts = [
        LISP_PREAMBLE,
        build_domain1_set_list_lisp(rng, random_cases_per_domain),
        build_domain2_sequences_arrays_lisp(rng, random_cases_per_domain),
        build_domain3_bitvectors_lisp(rng, random_cases_per_domain),
        build_domain4_chars_strings_lisp(),
        build_domain5_hashtables_lisp(),
        build_domain6_numerics_lisp(rng, random_cases_per_domain),
        LISP_EPILOGUE,
    ]
    return "\n".join(parts)


def parse_target_output(raw: str) -> Tuple[Dict[str, int], Dict[str, Tuple[str, str, str]]]:
    meta = {"total_cases": 0, "total_evals": 0, "intra_diffs": 0}
    results: Dict[str, Tuple[str, str, str]] = {}
    for line in raw.splitlines():
        if line.startswith("===W4-META "):
            body = line[len("===W4-META "):].rstrip("=").strip()
            for tok in body.split():
                if "=" in tok:
                    k, v = tok.split("=", 1)
                    meta[k] = int(v)
        elif line.startswith("===W4-RES\t"):
            parts = line.split("\t")
            if len(parts) == 5:
                _, cid, s3, s1, ni = parts
                results[cid] = (s3, s1, ni)
    return meta, results


def run_local_target(name: str, lisp_code: str, timeout_s: int = 60) -> Tuple[Dict[str, int], Dict[str, Tuple[str, str, str]], float]:
    tmp_path = f"/tmp/w4_stdlib_fuzz_{os.getpid()}_{name}.lisp"
    t0 = time.time()
    try:
        with open(tmp_path, "w", encoding="utf-8") as f:
            f.write(lisp_code)
        if name == "sbcl-arm64":
            cmd = [
                TIMEOUT_BIN, "--kill-after=5s", f"{timeout_s}s",
                LOCAL_SBCL, "--noinform", "--non-interactive",
                "--load", tmp_path,
            ]
        elif name == "ccl-arm64":
            cmd = [
                TIMEOUT_BIN, "--kill-after=5s", f"{timeout_s}s",
                LOCAL_CCL, "-n", "-Q", "-b",
                "-l", tmp_path, "-e", "(ccl:quit 0)",
            ]
        else:
            raise ValueError(f"Unknown local target: {name}")
        proc = subprocess.run(cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            raise RuntimeError(
                f"{name} exited with {proc.returncode}:\nSTDOUT:\n{proc.stdout[:1500]}\nSTDERR:\n{proc.stderr[:1500]}"
            )
        meta, res = parse_target_output(proc.stdout)
        return meta, res, time.time() - t0
    finally:
        try:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
        except OSError:
            pass


def run_remote_target(name: str, lisp_code: str, timeout_s: int = 90) -> Tuple[Dict[str, int], Dict[str, Tuple[str, str, str]], float]:
    remote_tmp = f"/tmp/w4_stdlib_fuzz_{os.getpid()}_{name}.lisp"
    t0 = time.time()
    try:
        upload = subprocess.run(
            [TIMEOUT_BIN, "--kill-after=5s", "30s", "ssh", "hbox", f"cat > {shlex.quote(remote_tmp)}"],
            input=lisp_code,
            capture_output=True,
            text=True,
        )
        if upload.returncode != 0:
            raise RuntimeError(f"Failed uploading suite to hbox for {name}: {upload.stderr}")

        if name == "sbcl-x86-64":
            inner = f"swarm-build timeout {timeout_s}s {REMOTE_SBCL} --noinform --non-interactive --load {shlex.quote(remote_tmp)}"
        elif name == "ccl-x86-64":
            inner = f"swarm-build timeout {timeout_s}s {REMOTE_CCL} -n -Q -b -l {shlex.quote(remote_tmp)} -e '(ccl:quit 0)'"
        else:
            raise ValueError(f"Unknown remote target: {name}")

        proc = subprocess.run(
            [TIMEOUT_BIN, "--kill-after=5s", f"{timeout_s + 30}s", "ssh", "hbox", inner],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            raise RuntimeError(
                f"{name} exited with {proc.returncode}:\nSTDOUT:\n{proc.stdout[:1500]}\nSTDERR:\n{proc.stderr[:1500]}"
            )
        meta, res = parse_target_output(proc.stdout)
        return meta, res, time.time() - t0
    finally:
        subprocess.run(
            [TIMEOUT_BIN, "--kill-after=5s", "15s", "ssh", "hbox", f"rm -f {shlex.quote(remote_tmp)}"],
            capture_output=True,
            text=True,
        )


def analyze_results(
    all_results: Dict[str, Dict[str, Tuple[str, str, str]]],
) -> Dict[str, List[dict]]:
    findings = {
        "intra_target_diffs": [],
        "invariant_failures": [],
        "cross_arch_same_impl": [],
        "cross_impl_diffs": [],
    }
    targets = list(all_results.keys())
    all_ids = sorted({cid for r in all_results.values() for cid in r.keys()})

    for cid in all_ids:
        if any(cid.startswith(pfx) for pfx in KNOWN_EXCLUSION_PREFIXES):
            continue
        per_t = {t: all_results[t].get(cid) for t in targets if cid in all_results[t]}

        # 1. Direct invariant failures (record-check FAIL:...)
        inv_fails = {t: vals[0] for t, vals in per_t.items() if vals and vals[0].startswith("FAIL")}
        if inv_fails:
            findings["invariant_failures"].append({"case": cid, "failures": inv_fails})
            continue

        # 2. Intra-target optimization/notinline differential (S3 vs S1 vs NI)
        for t, vals in per_t.items():
            if vals and len(set(vals)) > 1:
                findings["intra_target_diffs"].append(
                    {"case": cid, "target": t, "S3": vals[0], "S1": vals[1], "NI": vals[2]}
                )

        # 3. Same-compiler cross-architecture differential (arm64 vs x86-64)
        if "sbcl-arm64" in per_t and "sbcl-x86-64" in per_t:
            if per_t["sbcl-arm64"] != per_t["sbcl-x86-64"]:
                findings["cross_arch_same_impl"].append(
                    {"case": cid, "compiler": "SBCL-2.6.10", "arm64": per_t["sbcl-arm64"], "x86-64": per_t["sbcl-x86-64"]}
                )
        if "ccl-arm64" in per_t and "ccl-x86-64" in per_t:
            if per_t["ccl-arm64"] != per_t["ccl-x86-64"]:
                findings["cross_arch_same_impl"].append(
                    {"case": cid, "compiler": "CCL-1.14", "arm64": per_t["ccl-arm64"], "x86-64": per_t["ccl-x86-64"]}
                )

        # 4. Cross-implementation differential (SBCL NI vs CCL NI)
        ni_vals = {t: vals[2] for t, vals in per_t.items() if vals}
        if len(set(ni_vals.values())) > 1:
            findings["cross_impl_diffs"].append({"case": cid, "by_target_NI": ni_vals, "full": per_t})

    return findings


def main() -> int:
    ap = argparse.ArgumentParser(description="Wave-4 CL stdlib boundary & transform differential fuzzer")
    ap.add_argument("--seed", type=int, default=20260403, help="Deterministic RNG seed")
    ap.add_argument("--random-cases", type=int, default=150, help="Random generated cases per randomized domain")
    ap.add_argument(
        "--targets",
        nargs="+",
        default=["sbcl-arm64", "sbcl-x86-64", "ccl-arm64", "ccl-x86-64"],
        choices=["sbcl-arm64", "sbcl-x86-64", "ccl-arm64", "ccl-x86-64"],
    )
    ap.add_argument("--json", action="store_true", help="Emit structured JSON summary")
    args = ap.parse_args()

    lisp_code = generate_lisp_suite(args.seed, args.random_cases)
    all_meta: Dict[str, Dict[str, int]] = {}
    all_results: Dict[str, Dict[str, Tuple[str, str, str]]] = {}
    timings: Dict[str, float] = {}

    for t in args.targets:
        if t in ("sbcl-arm64", "ccl-arm64"):
            meta, res, dt = run_local_target(t, lisp_code)
        else:
            meta, res, dt = run_remote_target(t, lisp_code)
        all_meta[t] = meta
        all_results[t] = res
        timings[t] = round(dt, 2)

    findings = analyze_results(all_results)

    if args.json:
        print(json.dumps({"meta": all_meta, "timings_sec": timings, "findings": findings}, indent=2))
    else:
        print("=== Wave-4 Stage 4: CL Stdlib Boundary & Transform Fuzzer Summary ===")
        total_evals_all = sum(m.get("total_evals", 0) for m in all_meta.values())
        for t in args.targets:
            m = all_meta[t]
            print(
                f"  [{t:11s}] cases={m.get('total_cases', 0):4d}  "
                f"evals={m.get('total_evals', 0):5d}  "
                f"intra_diffs={m.get('intra_diffs', 0):2d}  "
                f"time={timings[t]:.2f}s"
            )
        print(f"  Total evaluations across {len(args.targets)} targets: {total_evals_all}")
        print()
        for category, items in findings.items():
            print(f"--- {category} ({len(items)}) ---")
            for item in items:
                print(" ", json.dumps(item))

    return 0


if __name__ == "__main__":
    sys.exit(main())
