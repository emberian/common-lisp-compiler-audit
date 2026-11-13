;;; Wave 1: broad differential across unreached arm64 paths.
(in-package :cl-user)

(defparameter *fails* 0)
(defparameter *tests* 0)

(defun same-val-p (x y)
  (cond ((and (typep x 'condition) (typep y 'condition))
         (eq (class-name (class-of x)) (class-name (class-of y))))
        ((or (typep x 'condition) (typep y 'condition)) nil)
        (t (equal x y))))

(defun eql-values-p (a b)
  (and (listp a) (listp b) (= (length a) (length b))
       (loop for x in a for y in b always (same-val-p x y))))

(defun run-test (name fast-lambda ref-lambda arglists)
  (let ((fast (if (and (symbolp fast-lambda) (fboundp fast-lambda))
                  (symbol-function fast-lambda)
                  (compile nil fast-lambda)))
        (ref (compile nil ref-lambda)))
    (dolist (args arglists)
      (incf *tests*)
      (let ((f (multiple-value-list (ignore-errors (apply fast args))))
            (r (multiple-value-list (ignore-errors (apply ref args)))))
        (unless (eql-values-p f r)
          (incf *fails*)
          (format t "~&DIFF ~a args=~s~%  fast=~s~%  ref =~s~%" name args f r))))))

(defparameter *u64-boundaries*
  (list 0 1 2 (1- (expt 2 32)) (expt 2 32) (1- (expt 2 60)) (expt 2 60)
        (1- (expt 2 61)) (expt 2 61) (1- (expt 2 63)) (expt 2 63)
        (1- (expt 2 64)) (- (expt 2 64) 2)))

(defparameter *u64-pairs*
  (loop for x in (list 0 (1- (expt 2 64)) (expt 2 63) 5 (1- (expt 2 60)) (expt 2 60))
        append (loop for y in (list 0 1 (expt 2 63) (1- (expt 2 64)) (expt 2 60))
                     collect (list x y))))

(run-test "u64-+"
  '(lambda (x y) (declare (type (unsigned-byte 64) x y) (optimize (speed 3) (safety 0))) (+ x y))
  '(lambda (x y) (funcall (symbol-function '+) x y))
  *u64-pairs*)

(run-test "u64--"
  '(lambda (x y) (declare (type (unsigned-byte 64) x y) (optimize (speed 3) (safety 0))) (- x y))
  '(lambda (x y) (funcall (symbol-function '-) x y))
  *u64-pairs*)

(run-test "u64-logand"
  '(lambda (x y) (declare (type (unsigned-byte 64) x y) (optimize (speed 3) (safety 0))) (logand x y))
  '(lambda (x y) (funcall (symbol-function 'logand) x y))
  *u64-pairs*)

(run-test "u64-logior"
  '(lambda (x y) (declare (type (unsigned-byte 64) x y) (optimize (speed 3) (safety 0))) (logior x y))
  '(lambda (x y) (funcall (symbol-function 'logior) x y))
  *u64-pairs*)

(run-test "u64-logxor"
  '(lambda (x y) (declare (type (unsigned-byte 64) x y) (optimize (speed 3) (safety 0))) (logxor x y))
  '(lambda (x y) (funcall (symbol-function 'logxor) x y))
  *u64-pairs*)

;;; ash on u64 with constant amounts
(let ((amounts '(-63 -32 -5 -1 0 1 5 32 62 63)))
  (run-test "u64-ash-const"
    `(lambda (x) (declare (type (unsigned-byte 64) x) (optimize (speed 3) (safety 0)))
       (list ,@(loop for a in amounts collect `(ash x ,a))))
    `(lambda (x)
       (list ,@(loop for a in amounts
                     collect `(funcall (symbol-function 'ash) x ,a))))
    (loop for x in *u64-boundaries* collect (list x))))

(run-test "u64-ash-var"
  '(lambda (x n) (declare (type (unsigned-byte 64) x) (type (integer -63 63) n) (optimize (speed 3) (safety 0))) (ash x n))
  '(lambda (x n) (funcall (symbol-function 'ash) x n))
  (loop for x in (list (1- (expt 2 64)) (expt 2 63) 1 0 #x8000000000000001)
        append (loop for n in (list -63 -61 -60 -32 -3 -1 0 1 3 32 60 61 62 63)
                     collect (list x n))))

(run-test "u64-the-identity"
  '(lambda (x) (declare (type (unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (the (unsigned-byte 64) x))
  '(lambda (x) x)
  (loop for x in *u64-boundaries* collect (list x)))

(run-test "u64-the-+-identity"
  '(lambda (x y) (declare (type (unsigned-byte 64) x y) (optimize (speed 3) (safety 0)))
     (the (unsigned-byte 64) (+ x y)))
  '(lambda (x y) (funcall (symbol-function '+) x y))
  (list (list 0 0)
        (list 0 (1- (expt 2 64)))
        (list (1- (expt 2 64)) 0)
        (list (expt 2 63) (1- (expt 2 63)))))

(run-test "u64-require-then-logand"
  '(lambda (x y) (declare (type (unsigned-byte 64) x y) (optimize (speed 3) (safety 0)))
     (logand (the (unsigned-byte 64) (+ x 0)) y))
  '(lambda (x y) (funcall (symbol-function 'logand)
                          (funcall (symbol-function '+) x 0) y))
  (list (list (1- (expt 2 64)) (1- (expt 2 64)))
        (list (expt 2 63) (expt 2 62))
        (list (1- (expt 2 60)) (1- (expt 2 61)))))

;;; signed 64 round-trip
(defparameter *s64-boundaries*
  (list 0 -1 1 (1- (expt 2 62)) (- (expt 2 62)) (1- (expt 2 63)) (- (expt 2 63))
        (1- (expt 2 60)) (- (expt 2 60)) (expt 2 60) (- (expt 2 60) 1)))

(run-test "s64-the-identity"
  '(lambda (x) (declare (type (signed-byte 64) x) (optimize (speed 3) (safety 0))) (the (signed-byte 64) x))
  '(lambda (x) x)
  (loop for x in *s64-boundaries* collect (list x)))

(run-test "s64-logand-self"
  '(lambda (x) (declare (type (signed-byte 64) x) (optimize (speed 3) (safety 0))) (logand x x))
  '(lambda (x) (funcall (symbol-function 'logand) x x))
  (loop for x in *s64-boundaries* collect (list x)))

;;; char-code / code-char
(run-test "char-code"
  '(lambda (c) (declare (type character c) (optimize (speed 3) (safety 0))) (char-code c))
  '(lambda (c) (funcall (symbol-function 'char-code) c))
  (loop for cc in (list 0 1 10 65 #xD7FF #xE000 #xFFFD #x10FFFF #x1F600)
        collect (list (code-char cc))))

(run-test "code-char"
  '(lambda (n) (declare (type (integer 0 #x10FFFF) n) (optimize (speed 3) (safety 0))) (code-char n))
  '(lambda (n) (funcall (symbol-function 'code-char) n))
  (loop for n in (list 0 1 10 65 #xD7FF #xD800 #xD801 #xDFFF #xE000 #xFFFD #x10FFFF)
        collect (list n)))

(run-test "code-char-fixnum-decl"
  '(lambda (n) (declare (type fixnum n) (optimize (speed 3) (safety 0))) (code-char n))
  '(lambda (n) (funcall (symbol-function 'code-char) n))
  '((0) (#xD800) (#x10FFFF) (#.most-positive-fixnum)))

;;; consp / endp / null / atom
(run-test "consp-endp"
  '(lambda (x) (declare (optimize (speed 3) (safety 0))) (list (consp x) (endp x) (null x) (atom x)))
  '(lambda (x) (list (funcall (symbol-function 'consp) x)
                     (funcall (symbol-function 'endp) x)
                     (funcall (symbol-function 'null) x)
                     (funcall (symbol-function 'atom) x)))
  '((nil) ((1 2)) (5) (#\a) (()) ((nil . nil))))

;;; multiple values
(run-test "mv-values-truncate"
  '(lambda (a b c) (declare (optimize (speed 3) (safety 0)))
     (list (multiple-value-list (values a b c))
           (nth-value 0 (values a b c))
           (nth-value 1 (values a b c))
           (nth-value 2 (values a b c))
           (nth-value 3 (values a b c))))
  '(lambda (a b c)
     (list (multiple-value-list (values a b c))
           (nth-value 0 (values a b c))
           (nth-value 1 (values a b c))
           (nth-value 2 (values a b c))
           (nth-value 3 (values a b c))))
  '((1 2 3)))

(run-test "mv-floor-mvb"
  '(lambda (x y) (declare (type fixnum x y) (optimize (speed 3) (safety 0)))
     (multiple-value-bind (q r) (floor x y) (list q r)))
  '(lambda (x y)
     (multiple-value-bind (q r) (funcall (symbol-function 'floor) x y) (list q r)))
  '((7 2) (-7 2) (7 -2) (-7 -2) (0 5) (100 10)))

(run-test "mv-values-with-exprs"
  '(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0)))
     (multiple-value-list (values x (+ x 1) (- x 1))))
  '(lambda (x)
     (multiple-value-list
      (values x (funcall (symbol-function '+) x 1) (funcall (symbol-function '-) x 1))))
  '(#.(list 0) #.(list 1) #.(list -1) #.(list most-positive-fixnum) #.(list most-negative-fixnum)))
(defun sc5 (n a b c d e)
  (declare (type fixnum n a b c d e) (optimize (speed 3) (safety 0)))
  (if (zerop n) (+ a (+ b (+ c (+ d e))))
      (sc5 (- n 1) a b c d e)))

(run-test "self-call-5-args"
  'sc5
  '(lambda (n a b c d e)
     (funcall (symbol-function '+) a (funcall (symbol-function '+) b
            (funcall (symbol-function '+) c (funcall (symbol-function '+) d e)))))
  '((0 1 2 3 4 5) (1 1 2 3 4 5) (3 1 2 3 4 5) (5 1 2 3 4 5) (10 1 2 3 4 5)))

(defun sc4mv (n a b c d)
  (declare (type fixnum n a b c d) (optimize (speed 3) (safety 0)))
  (if (zerop n) (values a b c d)
      (sc4mv (- n 1) a b c d)))

(run-test "self-call-mv-4-args"
  'sc4mv
  '(lambda (n a b c d) (values a b c d))
  '((0 1 2 3 4) (1 1 2 3 4) (4 1 2 3 4) (20 1 2 3 4)))

(format t "~&wave1 done: ~d tests, ~d diffs~%" *tests* *fails*)
(quit)
