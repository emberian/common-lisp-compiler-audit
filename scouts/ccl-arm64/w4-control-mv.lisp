;;; Differential wave 4: comparisons, MV transfer, division, self-calls.
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
  (let ((fast (if (symbolp fast-form) (symbol-function fast-form) (compile nil fast-form)))
        (ref (compile nil ref-form)) (bad 0) (n 0))
    (dolist (args arglists)
      (incf n) (incf *tests*)
      (let ((f (multiple-value-list (ignore-errors (apply fast args))))
            (r (multiple-value-list (ignore-errors (apply ref args)))))
        (unless (vl= f r)
          (incf bad) (incf *fails*)
          (format t "~&DIFF ~a args=~s fast=~s ref=~s~%" name args f r))))
    (format t "~&RESULT ~a cases=~d diffs=~d~%" name n bad)))
(defparameter *fx* (list most-negative-fixnum (1+ most-negative-fixnum)
                         (- (expt 2 59)) -4097 -4096 -4095 -513 -512 -511
                         -2 -1 0 1 2 511 512 513 4095 4096 4097
                         (1- (expt 2 59)) (1- most-positive-fixnum) most-positive-fixnum))

;;; H14: comparison immediate and register paths, both operand orders.
(dolist (c '(-1000000 -4096 -512 -511 -1 0 1 511 512 4096 1000000))
  (dolist (op '(= /= < <= > >=))
    (check (format nil "cmp-right-~a-~d" op c)
      `(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0))) (,op x ,c))
      `(lambda (x) (funcall (symbol-function ',op) x ,c))
      (mapcar #'list *fx*))
    (check (format nil "cmp-left-~a-~d" op c)
      `(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0))) (,op ,c x))
      `(lambda (x) (funcall (symbol-function ',op) ,c x))
      (mapcar #'list *fx*))))
(check "cmp-fixnum-variables"
  '(lambda (x y) (declare (type fixnum x y) (optimize (speed 3) (safety 0)))
     (list (= x y) (/= x y) (< x y) (<= x y) (> x y) (>= x y)))
  '(lambda (x y) (list (funcall (symbol-function '=) x y) (funcall (symbol-function '/=) x y)
                       (funcall (symbol-function '<) x y) (funcall (symbol-function '<=) x y)
                       (funcall (symbol-function '>) x y) (funcall (symbol-function '>=) x y)))
  (loop for x in *fx* append (loop for y in (list most-negative-fixnum -1 0 1 most-positive-fixnum)
                                  collect (list x y))))

;;; H15: u64 comparisons across the sign-bit boundary (generic or natural path).
(dolist (op '(= /= < <= > >=))
  (check (format nil "cmp-u64-~a" op)
    `(lambda (x y) (declare (type (unsigned-byte 64) x y) (optimize (speed 3) (safety 0))) (,op x y))
    `(lambda (x y) (funcall (symbol-function ',op) x y))
    (loop for x in (list 0 1 (1- (expt 2 60)) (expt 2 60) (1- (expt 2 63)) (expt 2 63) (1- (expt 2 64)))
          append (loop for y in (list 0 1 (1- (expt 2 63)) (expt 2 63) (1- (expt 2 64)))
                       collect (list x y)))))

;;; H16: binary division and remainder, including MIN/-1 and all signs.
(defparameter *division-pairs*
  (loop for x in (list most-negative-fixnum (1+ most-negative-fixnum) -100 -7 -2 -1 0 1 2 7 100
                       (1- most-positive-fixnum) most-positive-fixnum)
        append (loop for y in (list most-negative-fixnum -256 -7 -2 -1 1 2 7 256 most-positive-fixnum)
                     collect (list x y))))
(dolist (op '(floor ceiling truncate round))
  (check (format nil "binary-~a" op)
    `(lambda (x y) (declare (type fixnum x y) (optimize (speed 3) (safety 0)))
       (multiple-value-bind (q r) (,op x y) (list q r)))
    `(lambda (x y) (multiple-value-list (funcall (symbol-function ',op) x y)))
    *division-pairs*))
(dolist (op '(mod rem))
  (check (format nil "binary-~a" op)
    `(lambda (x y) (declare (type fixnum x y) (optimize (speed 3) (safety 0))) (,op x y))
    `(lambda (x y) (funcall (symbol-function ',op) x y))
    *division-pairs*))

;;; H17: MVB with missing/excess values and computed values.
(check "mvb-missing-values"
  '(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0)))
     (multiple-value-bind (a b c d) (values x) (list a b c d)))
  '(lambda (x) (let ((v (multiple-value-list (funcall (symbol-function 'values) x))))
                 (list (nth 0 v) (nth 1 v) (nth 2 v) (nth 3 v))))
  (mapcar #'list *fx*))
(check "mvb-excess-values"
  '(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0)))
     (multiple-value-bind (a b) (values x (+ x 1) (- x 1) (lognot x)) (list a b)))
  '(lambda (x) (let ((v (list x (funcall (symbol-function '+) x 1)
                              (funcall (symbol-function '-) x 1)
                              (funcall (symbol-function 'lognot) x))))
                 (list (nth 0 v) (nth 1 v))))
  (mapcar #'list (list -100 -2 -1 0 1 2 100)))

;;; H18: NTH-VALUE constant and variable, including out-of-range nil.
(dolist (n '(0 1 2 3 4 20 60))
  (check (format nil "nth-value-~d" n)
    `(lambda (a b c) (declare (optimize (speed 3) (safety 0))) (nth-value ,n (values a b c)))
    `(lambda (a b c) (nth ,n (multiple-value-list (funcall (symbol-function 'values) a b c))))
    '((1 2 3) (nil x #\a))))
;;; Variable N with several object types.
(check "nth-value-variable-objects"
  '(lambda (n a b c) (declare (type (integer 0 60) n) (optimize (speed 3) (safety 0)))
     (nth-value n (values a b c)))
  '(lambda (n a b c) (nth n (multiple-value-list (funcall (symbol-function 'values) a b c))))
  (loop for n in '(0 1 2 3 4 20 60) append (list (list n 1 2 3) (list n nil 'x #\a))))

;;; H19: LOGBITP, LOGCOUNT, INTEGER-LENGTH at fixnum/bignum and 64-bit boundaries.
(defparameter *bit-values*
  (list most-negative-fixnum (1+ most-negative-fixnum) -65 -64 -63 -2 -1 0 1 2 63 64 65
        most-positive-fixnum (expt 2 60) (1+ (expt 2 60)) (1- (expt 2 63))
        (expt 2 63) (1+ (expt 2 63)) (1- (expt 2 64)) (- (expt 2 63)) (1- (- (expt 2 63)))))
(check "logbitp-variable"
  '(lambda (n x) (declare (type (unsigned-byte 8) n) (type integer x)
                          (optimize (speed 3) (safety 0))) (logbitp n x))
  '(lambda (n x) (funcall (symbol-function 'logbitp) n x))
  (loop for x in *bit-values* append (loop for n in '(0 1 2 59 60 61 62 63 64 65 100 255)
                                          collect (list n x))))
(check "logcount-integer-length"
  '(lambda (x) (declare (type integer x) (optimize (speed 3) (safety 0)))
     (list (logcount x) (integer-length x)))
  '(lambda (x) (list (funcall (symbol-function 'logcount) x)
                     (funcall (symbol-function 'integer-length) x)))
  (mapcar #'list *bit-values*))

;;; H20: generated tail self-calls with 4..24 data args and rotated stack args.
(defun self-reference (n vals)
  (dotimes (i n vals)
    (declare (ignore i))
    (setq vals (append (cdr vals)
                       (list (funcall (symbol-function '+) (car vals) 3))))))
(dolist (count '(3 4 6 8 12 16 20 24))
  (let* ((name (intern (format nil "SELF-ROTATE-~d" count)))
         (args (loop for i below count collect (intern (format nil "A~d" i))))
         (rotated (append (cdr args) (list `(+ ,(car args) 3))))
         (form `(defun ,name (n ,@args)
                  (declare (type fixnum n ,@args) (optimize (speed 3) (safety 0) (debug 0)))
                  (if (zerop n) (list ,@args) (,name (1- n) ,@rotated)))))
    (eval form)
    (check (format nil "self-tail-~d" count) name
      '(lambda (n &rest vals) (self-reference n vals))
      (loop for n in '(0 1 2 7)
            collect (cons n (loop for i below count collect (- i 10)))))))

;;; H21: the same self-call pressure with many returned values.
(dolist (count '(2 3 4 6 8 12 16 20 24))
  (let* ((name (intern (format nil "SELF-MV-~d" count)))
         (args (loop for i below count collect (intern (format nil "A~d" i))))
         (rotated (append (cdr args) (list `(+ ,(car args) 3))))
         (form `(defun ,name (n ,@args)
                  (declare (type fixnum n ,@args) (optimize (speed 3) (safety 0) (debug 0)))
                  (if (zerop n) (values ,@args) (,name (1- n) ,@rotated)))))
    (eval form)
    (check (format nil "self-tail-mv-~d" count) name
      '(lambda (n &rest vals) (values-list (self-reference n vals)))
      (loop for n in '(0 1 2 7)
            collect (cons n (loop for i below count collect (- i 10)))))))

(format t "~&wave4 done: ~d tests, ~d diffs~%" *tests* *fails*)
(quit)
