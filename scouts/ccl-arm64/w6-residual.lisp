;;; Wave 6: residual frontend rewrites and wide value transfer.
(in-package :cl-user)
(defparameter *tests* 0)
(defparameter *fails* 0)
(defun vl= (a b)
  (and (= (length a) (length b))
       (loop for x in a for y in b always
             (cond ((and (typep x 'condition) (typep y 'condition))
                    (eq (class-name (class-of x)) (class-name (class-of y))))
                   ((or (typep x 'condition) (typep y 'condition)) nil)
                   (t (equal x y))))))
(defun check (name fast-form ref-form arglists)
  (let ((fast (compile nil fast-form)) (ref (compile nil ref-form)) (bad 0) (n 0))
    (dolist (args arglists)
      (incf n) (incf *tests*)
      (let ((f (multiple-value-list (ignore-errors (apply fast args))))
            (r (multiple-value-list (ignore-errors (apply ref args)))))
        (unless (vl= f r)
          (incf bad) (incf *fails*)
          (format t "~&DIFF ~a args=~s fast=~s ref=~s~%" name args f r))))
    (format t "~&RESULT ~a cases=~d diffs=~d~%" name n bad)))
(defparameter *fx* (list most-negative-fixnum (1+ most-negative-fixnum) (- (expt 2 59))
                         -3 -2 -1 0 1 2 3 (1- (expt 2 59))
                         (1- most-positive-fixnum) most-positive-fixnum))

;;; H31: 1+/1- and nested additions across the fixnum overflow boundary.
(check "one-plus-one-minus"
  '(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0))) (list (1+ x) (1- x)))
  '(lambda (x) (list (funcall (symbol-function '1+) x) (funcall (symbol-function '1-) x)))
  (mapcar #'list *fx*))
(check "nested-add-overflow"
  '(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0))) (+ (+ x x) (+ x x)))
  '(lambda (x) (funcall (symbol-function '+)
                        (funcall (symbol-function '+) x x)
                        (funcall (symbol-function '+) x x)))
  (mapcar #'list *fx*))

;;; H32: MUL2 -> ASH -> %ILSL with truthful signed-byte widths.
(dolist (k '(1 2 3 7 15 16 31 32 59 60))
  (let* ((w (- 61 k)) (lo (- (expt 2 (1- w)))) (hi (1- (expt 2 (1- w))))
         (c (ash 1 k)))
    (check (format nil "mul-power-2-~d" k)
      `(lambda (x) (declare (type (signed-byte ,w) x) (optimize (speed 3) (safety 0))) (* x ,c))
      `(lambda (x) (funcall (symbol-function '*) x ,c))
      (loop for v in (list lo (1+ lo) -1 0 1 (1- hi) hi)
            when (<= lo v hi) collect (list v)))))

;;; H33: u64 comparisons against fixnum and bignum constants.
(dolist (c (list 0 1 511 512 4095 4096 (1- (expt 2 60)) (expt 2 60)
                 (1- (expt 2 63)) (expt 2 63) (1- (expt 2 64))))
  (dolist (op '(= /= < <= > >=))
    (check (format nil "u64-cmp-right-~a-~d" op c)
      `(lambda (x) (declare (type (unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (,op x ,c))
      `(lambda (x) (funcall (symbol-function ',op) x ,c))
      (mapcar #'list (list 0 1 511 512 4095 4096 (1- (expt 2 60)) (expt 2 60)
                           (1- (expt 2 63)) (expt 2 63) (1- (expt 2 64)))))
    (check (format nil "u64-cmp-left-~a-~d" op c)
      `(lambda (x) (declare (type (unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (,op ,c x))
      `(lambda (x) (funcall (symbol-function ',op) ,c x))
      (mapcar #'list (list 0 1 511 512 4095 4096 (1- (expt 2 60)) (expt 2 60)
                           (1- (expt 2 63)) (expt 2 63) (1- (expt 2 64)))))))

;;; H34: composite logical rewrites on fixnums.
(dolist (op '(logandc1 logandc2 logorc1 logorc2 lognand lognor logeqv))
  (check (format nil "logical-composite-~a" op)
    `(lambda (x y) (declare (type fixnum x y) (optimize (speed 3) (safety 0))) (,op x y))
    `(lambda (x y) (funcall (symbol-function ',op) x y))
    (loop for x in *fx* append (loop for y in (list most-negative-fixnum -1 0 1 most-positive-fixnum)
                                    collect (list x y)))))

;;; H35: very large NTH-VALUE indices must produce NIL without indexing arithmetic wrap.
(check "nth-value-large-index"
  '(lambda (n a b c) (declare (type (integer 0 #.most-positive-fixnum) n)
                              (optimize (speed 3) (safety 0)))
     (nth-value n (values a b c)))
  '(lambda (n a b c) (nth n (multiple-value-list (funcall (symbol-function 'values) a b c))))
  (loop for n in (list 0 1 2 3 4 60 61 1000 (expt 2 32) most-positive-fixnum)
        append (list (list n 1 2 3) (list n nil 'x #\a))))

;;; H36: wide MVB (20 bindings) with exact, missing, and excess values.
(let* ((vars (loop for i below 20 collect (intern (format nil "V~d" i))))
       (values20 (loop for v in vars for i from 0 collect `(+ ,v ,i))))
  (declare (ignore values20))
  (dolist (nvalues '(1 19 20 21 24))
    (let* ((args (loop for i below 20 collect (intern (format nil "X~d" i))))
           (producer `(values ,@(loop for i below nvalues collect `(nth ,i (list ,@args))))))
      (check (format nil "wide-mvb-~d-values" nvalues)
        `(lambda ,args
           (declare (optimize (speed 3) (safety 0)))
           (multiple-value-bind ,vars ,producer (list ,@vars)))
        `(lambda ,args
           (let ((vals (multiple-value-list (funcall (symbol-function 'values)
                                                     ,@(loop for i below nvalues collect `(nth ,i (list ,@args)))))))
             (list ,@(loop for i below 20 collect `(nth ,i vals)))))
        (list (loop for i below 20 collect (- i 10)))))))

;;; H37: MULTIPLE-VALUE-PROG1 preserves all values across later forms.
(check "multiple-value-prog1"
  '(lambda (x) (declare (type (signed-byte 30) x) (optimize (speed 3) (safety 0)))
     (multiple-value-prog1 (values x (+ x 1) (- x 1) (lognot x))
       (+ x 100) (logand x 255)))
  '(lambda (x) (values-list (list x
                 (funcall (symbol-function '+) x 1)
                 (funcall (symbol-function '-) x 1)
                 (funcall (symbol-function 'lognot) x))))
  (mapcar #'list (list (- (expt 2 29)) -1 0 1 (1- (expt 2 29)))))

(format t "~&wave6 done: ~d tests, ~d diffs~%" *tests* *fails*)
(quit)
