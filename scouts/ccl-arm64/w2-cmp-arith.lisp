;;; Wave 2: comparisons, fixnum-ash, %ilsl, %i*, negate, fixnum overflow.
(in-package :cl-user)

(defparameter *fails* 0)
(defparameter *tests* 0)

(defun same-val-p (x y)
  (cond ((and (typep x 'condition) (typep y 'condition))
         (eq (class-name (class-of x)) (class-name (class-of y))))
        ((or (typep x 'condition) (typep y 'condition)) nil)
        (t (equal x y))))

(defun run-test (name fast-lambda ref-lambda arglists)
  (let ((fast (if (and (symbolp fast-lambda) (fboundp fast-lambda))
                  (symbol-function fast-lambda)
                  (compile nil fast-lambda)))
        (ref (compile nil ref-lambda)))
    (dolist (args arglists)
      (incf *tests*)
      (let ((f (multiple-value-list (ignore-errors (apply fast args))))
            (r (multiple-value-list (ignore-errors (apply ref args)))))
        (unless (and (= (length f) (length r))
                     (loop for x in f for y in r always (same-val-p x y)))
          (incf *fails*)
          (format t "~&DIFF ~a args=~s~%  fast=~s~%  ref =~s~%" name args f r))))))

(defparameter *fx-boundaries*
  (list 0 1 -1 2 -2 511 -511 512 -512 4095 -4095 4096
        most-positive-fixnum most-negative-fixnum
        (1- most-positive-fixnum) (1+ most-negative-fixnum)
        (- most-positive-fixnum 511) (+ most-negative-fixnum 511)))

;;; --- comparisons on declared fixnums (both var) ---
(run-test "fx-cmp-var-var"
  '(lambda (x y) (declare (type fixnum x y) (optimize (speed 3) (safety 0)))
     (list (= x y) (/= x y) (< x y) (<= x y) (> x y) (>= x y)))
  '(lambda (x y)
     (list (funcall (symbol-function '=) x y) (funcall (symbol-function '/=) x y)
           (funcall (symbol-function '<) x y) (funcall (symbol-function '<=) x y)
           (funcall (symbol-function '>) x y) (funcall (symbol-function '>=) x y)))
  (loop for x in *fx-boundaries*
        append (loop for y in (list 0 1 -1 511 512 4095 -4095 most-positive-fixnum most-negative-fixnum)
                     collect (list x y))))

;;; --- comparisons against constants (imm12 and lri paths) ---
(let ((consts '(0 1 -1 2 -2 511 512 4095 4096 -4095 -4096 1000000)))
  (run-test "fx-cmp-const"
    `(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0)))
       (list ,@(loop for c in consts
                     append `((= x ,c) (< x ,c) (> x ,c) (<= x ,c) (>= x ,c)))))
    `(lambda (x)
       (list ,@(loop for c in consts
                     append `((funcall (symbol-function '=) x ,c)
                              (funcall (symbol-function '<) x ,c)
                              (funcall (symbol-function '>) x ,c)
                              (funcall (symbol-function '<=) x ,c)
                              (funcall (symbol-function '>=) x ,c)))))
    (loop for x in *fx-boundaries* collect (list x))))

;;; --- comparisons on u64 (unsigned semantics) ---
(run-test "u64-cmp-var-var"
  '(lambda (x y) (declare (type (unsigned-byte 64) x y) (optimize (speed 3) (safety 0)))
     (list (= x y) (/= x y) (< x y) (<= x y) (> x y) (>= x y)))
  '(lambda (x y)
     (list (funcall (symbol-function '=) x y) (funcall (symbol-function '/=) x y)
           (funcall (symbol-function '<) x y) (funcall (symbol-function '<=) x y)
           (funcall (symbol-function '>) x y) (funcall (symbol-function '>=) x y)))
  (loop for x in (list 0 1 (expt 2 63) (1- (expt 2 63)) (1- (expt 2 64)) (expt 2 60))
        append (loop for y in (list 0 1 (expt 2 63) (1- (expt 2 63)) (1- (expt 2 64)))
                     collect (list x y))))

(let ((consts (list 0 1 4095 4096 (expt 2 32) (expt 2 63))))
  (run-test "u64-cmp-const"
    `(lambda (x) (declare (type (unsigned-byte 64) x) (optimize (speed 3) (safety 0)))
       (list ,@(loop for c in consts
                     append `((= x ,c) (< x ,c) (> x ,c) (<= x ,c) (>= x ,c)))))
    `(lambda (x)
       (list ,@(loop for c in consts
                     append `((funcall (symbol-function '=) x ,c)
                              (funcall (symbol-function '<) x ,c)
                              (funcall (symbol-function '>) x ,c)
                              (funcall (symbol-function '<=) x ,c)
                              (funcall (symbol-function '>=) x ,c)))))
    (loop for x in (list 0 1 (expt 2 63) (1- (expt 2 63)) (1- (expt 2 64)) (expt 2 60) 4095)
          collect (list x))))

;;; --- fixnum-ash (bounded types; result provably fixnum) ---
(run-test "fixnum-ash-bounded"
  '(lambda (x n) (declare (type (signed-byte 40) x) (type (integer -20 20) n)
                          (optimize (speed 3) (safety 0)))
     (ash x n))
  '(lambda (x n) (funcall (symbol-function 'ash) x n))
  (loop for x in (list 0 1 -1 (1- (expt 2 39)) (- (expt 2 39)) (- (expt 2 38))
                       (1- (expt 2 30)) (- (expt 2 30)))
        append (loop for n in (list -20 -19 -1 0 1 19 20)
                     collect (list x n))))

;;; --- fixnum-ash-left only (amt type >= 0) ---
(run-test "fixnum-ash-left-only"
  '(lambda (x n) (declare (type (signed-byte 50) x) (type (integer 0 10) n)
                          (optimize (speed 3) (safety 0)))
     (ash x n))
  '(lambda (x n) (funcall (symbol-function 'ash) x n))
  (loop for x in (list 0 1 -1 (1- (expt 2 49)) (- (expt 2 49)) (1- (expt 2 40)))
        append (loop for n in (list 0 1 9 10) collect (list x n))))

;;; --- %ilsl from mul2 power-of-two ---
(run-test "mul-shift-65536"
  '(lambda (x) (declare (type (signed-byte 44) x) (optimize (speed 3) (safety 0)))
     (* x 65536))
  '(lambda (x) (funcall (symbol-function '*) x 65536))
  (loop for x in (list 0 1 -1 (1- (expt 2 43)) (- (expt 2 43)) (1- (expt 2 44)) (- (expt 2 44)))
        collect (list x)))

(run-test "mul-shift-8"
  '(lambda (x) (declare (type (signed-byte 57) x) (optimize (speed 3) (safety 0)))
     (* x 8))
  '(lambda (x) (funcall (symbol-function '*) x 8))
  (loop for x in (list 0 1 -1 (1- (expt 2 56)) (- (expt 2 56)) most-positive-fixnum)
        collect (list x)))

;;; ash with constant positive count on bounded x -> %ilsl
(run-test "ash-const-left-bounded"
  '(lambda (x) (declare (type (signed-byte 45) x) (optimize (speed 3) (safety 0)))
     (ash x 16))
  '(lambda (x) (funcall (symbol-function 'ash) x 16))
  (loop for x in (list 0 1 -1 (1- (expt 2 44)) (- (expt 2 44)) (1- (expt 2 45)))
        collect (list x)))

;;; ash of constant num by bounded variable amt -> %ilsl other order
(run-test "ash-const-num-var-amt"
  '(lambda (n) (declare (type (integer 0 58) n) (optimize (speed 3) (safety 0)))
     (ash 3 n))
  '(lambda (n) (funcall (symbol-function 'ash) 3 n))
  (loop for n in (list 0 1 29 57 58) collect (list n)))

;;; --- %i* multiply-fixnums at the top of the provable range ---
(run-test "mul-i-star"
  '(lambda (x y) (declare (type (signed-byte 34) x) (type (integer (- (expt 2 25)) (1- (expt 2 26))) y)
                          (optimize (speed 3) (safety 0)))
     (* x y))
  '(lambda (x y) (funcall (symbol-function '*) x y))
  (loop for x in (list 0 1 -1 (1- (expt 2 33)) (- (expt 2 33)) 1024)
        append (loop for y in (list 0 1 -1 (1- (expt 2 26)) (- (expt 2 25)) (1- (expt 2 25)))
                     collect (list x y))))

;;; multiply-immediate path: constant (signed-byte 16) operand
(run-test "mul-immediate"
  '(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0)))
     (* x 12345))
  '(lambda (x) (funcall (symbol-function '*) x 12345))
  (loop for x in (list 0 1 -1 100000 most-positive-fixnum most-negative-fixnum)
        collect (list x)))

;;; --- negate overflow ---
(run-test "negate"
  '(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0)))
     (- x))
  '(lambda (x) (funcall (symbol-function '-) x))
  (loop for x in (list 0 1 -1 most-positive-fixnum most-negative-fixnum
                       (1- most-negative-fixnum) (1+ most-positive-fixnum))
        collect (list x)))

;;; --- fixnum add/sub overflow -> bignum ---
(run-test "fx-add-overflow"
  '(lambda (x y) (declare (type fixnum x y) (optimize (speed 3) (safety 0)))
     (+ x y))
  '(lambda (x y) (funcall (symbol-function '+) x y))
  (list (list most-positive-fixnum 1)
        (list 1 most-positive-fixnum)
        (list most-positive-fixnum most-positive-fixnum)
        (list most-negative-fixnum -1)
        (list -1 most-negative-fixnum)
        (list most-negative-fixnum most-negative-fixnum)
        (list (1- most-positive-fixnum) 1)
        (list (1+ most-negative-fixnum) -1)
        (list 0 0)))

(run-test "fx-sub-overflow"
  '(lambda (x y) (declare (type fixnum x y) (optimize (speed 3) (safety 0)))
     (- x y))
  '(lambda (x y) (funcall (symbol-function '-) x y))
  (list (list most-positive-fixnum most-negative-fixnum)
        (list most-negative-fixnum most-positive-fixnum)
        (list 0 most-negative-fixnum)
        (list most-positive-fixnum -1)
        (list most-negative-fixnum 1)
        (list 5 3)))

;;; 1+ / 1- at boundaries
(run-test "one-plus-minus"
  '(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0)))
     (list (1+ x) (1- x)))
  '(lambda (x)
     (list (funcall (symbol-function '1+) x) (funcall (symbol-function '1-) x)))
  (loop for x in (list 0 1 -1 most-positive-fixnum most-negative-fixnum)
        collect (list x)))

;;; chained adds that overflow in the middle
(run-test "fx-add-chain"
  '(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0)))
     (+ (+ x x) (+ x x)))
  '(lambda (x)
     (funcall (symbol-function '+)
              (funcall (symbol-function '+) x x)
              (funcall (symbol-function '+) x x)))
  (loop for x in (list 0 1 -1 (floor most-positive-fixnum 2)
                       most-positive-fixnum most-negative-fixnum
                       (+ 1 (floor most-positive-fixnum 2))
                       (- 1 (floor most-negative-fixnum 2)))
        collect (list x)))

(format t "~&wave2 done: ~d tests, ~d diffs~%" *tests* *fails*)
(quit)
