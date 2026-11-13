;;; Corrected differential wave: all inputs satisfy all declarations.
(in-package :cl-user)
(defparameter *tests* 0)
(defparameter *fails* 0)
(defun value-list= (a b)
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
        (unless (value-list= f r)
          (incf bad) (incf *fails*)
          (format t "~&DIFF ~a args=~s fast=~s ref=~s~%" name args f r))))
    (format t "~&RESULT ~a cases=~d diffs=~d~%" name n bad)))
(defun ref1 (op x) `(funcall (symbol-function ',op) ,x))
(defun ref2 (op x y) `(funcall (symbol-function ',op) ,x ,y))
(defparameter *mpf* most-positive-fixnum)
(defparameter *mnf* most-negative-fixnum)
(defparameter *fx* (list *mnf* (1+ *mnf*) (- (expt 2 59)) (- (expt 2 59) 1)
                         -4097 -4096 -4095 -513 -512 -511 -2 -1 0 1 2
                         511 512 513 4095 4096 4097 (1- (expt 2 59))
                         (expt 2 59) (1- *mpf*) *mpf*))

;;; H1: constant left shifts via %ilsl-c, using the exact truthful signed width.
(dolist (k '(1 2 3 7 15 16 31 32 59 60))
  (let* ((w (- 61 k)) (lo (- (expt 2 (1- w)))) (hi (1- (expt 2 (1- w)))))
    (check (format nil "ilsl-c-k~d" k)
      `(lambda (x) (declare (type (signed-byte ,w) x) (optimize (speed 3) (safety 0))) (ash x ,k))
      `(lambda (x) (funcall (symbol-function 'ash) x ,k))
      (loop for v in (list lo (1+ lo) -1 0 1 (1- hi) hi)
            when (<= lo v hi) collect (list v)))))

;;; H2: constant arithmetic right shifts, including counts beyond word size.
(dolist (k '(-1 -2 -3 -31 -32 -59 -60 -61 -62 -63 -64 -65 -100))
  (check (format nil "iasr-c-k~d" k)
    `(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0))) (ash x ,k))
    `(lambda (x) (funcall (symbol-function 'ash) x ,k))
    (mapcar #'list *fx*)))

;;; H3: constant numerator with variable nonnegative count selects boxed %ilsl.
(dolist (num '(1 -1 2 -2 3 -3 7 -7))
  (let* ((width (1+ (integer-length num))) (max-shift (- 61 width)))
    (check (format nil "ilsl-var-num~d" num)
      `(lambda (n) (declare (type (integer 0 ,max-shift) n) (optimize (speed 3) (safety 0))) (ash ,num n))
      `(lambda (n) (funcall (symbol-function 'ash) ,num n))
      (mapcar #'list (list 0 1 (1- max-shift) max-shift)))))

;;; H4: bidirectional variable fixnum-ash with bounded, always-fixnum result.
(check "fixnum-ash-bidirectional"
  '(lambda (x n) (declare (type (signed-byte 40) x) (type (integer -20 20) n)
                          (optimize (speed 3) (safety 0))) (ash x n))
  '(lambda (x n) (funcall (symbol-function 'ash) x n))
  (loop for x in (list (- (expt 2 39)) (1- (- (expt 2 39))) -1 0 1 (1- (expt 2 39)))
        append (loop for n in '(-20 -19 -2 -1 0 1 2 19 20) collect (list x n))))
(check "fixnum-ash-left-variable"
  '(lambda (x n) (declare (type (signed-byte 50) x) (type (integer 0 10) n)
                          (optimize (speed 3) (safety 0))) (ash x n))
  '(lambda (x n) (funcall (symbol-function 'ash) x n))
  (loop for x in (list (- (expt 2 49)) -1 0 1 (1- (expt 2 49)))
        append (loop for n in '(0 1 9 10) collect (list x n))))

;;; H5: natural left shift where the declared u64 result really contains every result.
(dolist (k '(1 2 31 32 60 61 62 63))
  (let* ((w (- 64 k)) (hi (1- (expt 2 w))))
    (check (format nil "natural-left-k~d" k)
      `(lambda (x) (declare (type (unsigned-byte ,w) x) (optimize (speed 3) (safety 0)))
         (the (unsigned-byte 64) (ash x ,k)))
      `(lambda (x) (funcall (symbol-function 'ash) x ,k))
      (mapcar #'list (list 0 1 (1- hi) hi)))))

;;; H6: natural right shifts and the >=64 zero rewrite.
(dolist (k '(-1 -2 -31 -32 -60 -61 -62 -63 -64 -65 -100))
  (check (format nil "natural-right-k~d" k)
    `(lambda (x) (declare (type (unsigned-byte 64) x) (optimize (speed 3) (safety 0))) (ash x ,k))
    `(lambda (x) (funcall (symbol-function 'ash) x ,k))
    (mapcar #'list (list 0 1 (1- (expt 2 60)) (expt 2 60) (1- (expt 2 63))
                         (expt 2 63) (1- (expt 2 64))))))

;;; H7: natural addition, including results requiring two- and three-digit bignums.
(let ((lo 0) (hi (1- (expt 2 63))))
  (declare (ignore lo))
  (check "natural-add-u63"
    '(lambda (x y) (declare (type (unsigned-byte 63) x y) (optimize (speed 3) (safety 0)))
       (the (unsigned-byte 64) (+ x y)))
    '(lambda (x y) (funcall (symbol-function '+) x y))
    (loop for x in (list 0 1 (1- (expt 2 60)) (expt 2 60) (1- (expt 2 63)))
          append (loop for y in (list 0 1 (1- (expt 2 60)) (expt 2 60) (1- (expt 2 63)))
                       collect (list x y)))))

;;; H8: natural subtraction guarded at runtime so THE u64 is always true.
(check "natural-sub-guarded"
  '(lambda (x y) (declare (type (unsigned-byte 64) x y) (optimize (speed 3) (safety 0)))
     (if (< x y) 0 (the (unsigned-byte 64) (- x y))))
  '(lambda (x y) (if (< x y) 0 (funcall (symbol-function '-) x y)))
  (loop for x in (list 0 1 (expt 2 60) (expt 2 63) (1- (expt 2 64)))
        append (loop for y in (list 0 1 (expt 2 60) (expt 2 63) (1- (expt 2 64)))
                     collect (list x y))))

;;; H9: fixnum addition/subtraction/negation overflow repair.
(check "fixnum-add-overflow"
  '(lambda (x y) (declare (type fixnum x y) (optimize (speed 3) (safety 0))) (+ x y))
  '(lambda (x y) (funcall (symbol-function '+) x y))
  (loop for x in *fx* append (loop for y in (list *mnf* -1 0 1 *mpf*) collect (list x y))))
(check "fixnum-sub-overflow"
  '(lambda (x y) (declare (type fixnum x y) (optimize (speed 3) (safety 0))) (- x y))
  '(lambda (x y) (funcall (symbol-function '-) x y))
  (loop for x in *fx* append (loop for y in (list *mnf* -1 0 1 *mpf*) collect (list x y))))
(check "fixnum-negate-overflow"
  '(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0))) (- x))
  '(lambda (x) (funcall (symbol-function '-) x))
  (mapcar #'list *fx*))

;;; H10: one/two-lane add-immediate with no-overflow type bounds.
(dolist (c '(-1048576 -524289 -524288 -524287 -4097 -4096 -4095 -513 -512 -511
             -1 0 1 511 512 513 4095 4096 4097 524287 524288 524289 1048575))
  (check (format nil "add-immediate-~d" c)
    `(lambda (x) (declare (type (signed-byte 45) x) (optimize (speed 3) (safety 0))) (+ x ,c))
    `(lambda (x) (funcall (symbol-function '+) x ,c))
    (mapcar #'list (list (- (expt 2 44)) -1 0 1 (1- (expt 2 44))))))

;;; H11: immediate and variable fixnum multiplication with provably in-range products.
(dolist (c '(-32767 -4095 -255 -3 -2 -1 1 2 3 255 4095 32767))
  (check (format nil "multiply-immediate-~d" c)
    `(lambda (x) (declare (type (signed-byte 32) x) (optimize (speed 3) (safety 0))) (* x ,c))
    `(lambda (x) (funcall (symbol-function '*) x ,c))
    (mapcar #'list (list (- (expt 2 31)) -1 0 1 (1- (expt 2 31))))))
(check "multiply-fixnums"
  '(lambda (x y) (declare (type (signed-byte 30) x y) (optimize (speed 3) (safety 0))) (* x y))
  '(lambda (x y) (funcall (symbol-function '*) x y))
  (loop for x in (list (- (expt 2 29)) -1 0 1 (1- (expt 2 29)))
        append (loop for y in (list (- (expt 2 29)) -1 0 1 (1- (expt 2 29))) collect (list x y))))

;;; H12: tagged logical immediates, including negative masks and rotated patterns.
(dolist (c '(-1 -2 -3 -8 -16 -255 -256 -257 #x55555555 #x33333333 #x0f0f0f0f
             #x00ff00ff #x1f1f1f1f #x7fffffff (1- (expt 2 59))))
  (dolist (op '(logand logior logxor))
    (check (format nil "logical-~a-~d" op c)
      `(lambda (x) (declare (type fixnum x) (optimize (speed 3) (safety 0))) (,op x ,c))
      `(lambda (x) (funcall (symbol-function ',op) x ,c))
      (mapcar #'list *fx*))))

;;; H13: exact-width signed/unsigned identities force unboxing/reboxing where selected.
(dolist (spec '((signed-byte 8) (unsigned-byte 8) (signed-byte 16) (unsigned-byte 16)
                (signed-byte 32) (unsigned-byte 32) (signed-byte 64) (unsigned-byte 64)))
  (let* ((signed (eq (car spec) 'signed-byte)) (bits (cadr spec))
         (lo (if signed (- (expt 2 (1- bits))) 0))
         (hi (1- (expt 2 (if signed (1- bits) bits)))))
    (check (format nil "the-identity-~s" spec)
      `(lambda (x) (declare (type ,spec x) (optimize (speed 3) (safety 0))) (the ,spec x))
      '(lambda (x) x)
      (loop for v in (list lo (1+ lo) -1 0 1 (1- hi) hi)
            when (<= lo v hi) collect (list v)))))

(format t "~&wave3 done: ~d tests, ~d diffs~%" *tests* *fails*)
(quit)
