;;; R: constraint propagation with annotated lvars and narrowed branches.
(setq *compile-print* nil *compile-verbose* nil)
(defparameter *r-fails* 0)
(defparameter *r-count* 0)
(defparameter *r-ops* '(< <= = > >= eql typep + - * logand ash floor truncate mod rem))
(defparameter *r-vals*
  '(0 1 -1 2 -2 3 -3 63 -64 64 -65
    4611686018427387902 4611686018427387903 -4611686018427387903 -4611686018427387904
    4611686018427387904 -4611686018427387905
    9223372036854775807 -9223372036854775808 9223372036854775808
    18446744073709551615 18446744073709551616
    170141183460469231731687303715884105727 -170141183460469231731687303715884105728))
(defun r-result (thunk)
  (handler-case (multiple-value-list (funcall thunk))
    (error (e) (list :error (type-of e) (princ-to-string e)))))
(defun r-compile (form)
  (let ((result nil))
    (with-output-to-string (*standard-output*)
      (with-output-to-string (*error-output*)
        (setf result (compile nil form))))
    result))
(defun r-drive (name type body &optional (vals *r-vals*))
  (incf *r-count*)
  (handler-case
      (let ((f (r-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0))) ,body)))
            (g (r-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0)))
                             (locally (declare (notinline ,@*r-ops*)) ,body)))))
        (dolist (x vals)
          (when (typep x type)
            (let ((a (r-result (lambda () (funcall f x))))
                  (b (r-result (lambda () (funcall g x)))))
              (unless (equal a b)
                (incf *r-fails*)
                (format t "RDIVERGE ~s type=~s x=~s inline=~s ref=~s~%" name type x a b))))))
    (error (e) (format t "RERROR ~s type=~s: ~a~%" name type e))))

;;; R1: annotated IF tests and references (34bab7d61).
(dolist (type '(fixnum integer (integer 0 100) (signed-byte 64) (unsigned-byte 64)))
  (dolist (body `((if x x 0)
                  (if (the ,type x) x 0)
                  (if x (the ,type x) 0)
                  (if (the ,type x) (the ,type x) 0)
                  (let ((y x)) (if y (the ,type y) 0))
                  (if x (+ x 1) 0)
                  (if (the ,type x) (+ x 1) 0)))
    (r-drive (list 'annotated-if body) type body)))

;;; R2: positive/negative branches and equality constraints.
(dolist (c '(-4611686018427387904 -1 0 1 4611686018427387902 4611686018427387903
             4611686018427387904 9223372036854775807 9223372036854775808
             18446744073709551615))
  (dolist (body `((if (< x ,c) x 0)
                  (if (< x ,c) 0 x)
                  (if (<= x ,c) x 0)
                  (if (<= x ,c) 0 x)
                  (if (= x ,c) x 0)
                  (if (= x ,c) 0 x)
                  (if (eql x ,c) x 0)
                  (if (eql x ,c) 0 x)
                  (if (< x ,c) (+ x 1) (- x 1))
                  (if (<= x ,c) (logand x 18446744073709551615) (logand x 4611686018427387903))))
    (r-drive (list 'comparison-constraint body) 'integer body)))

;;; R3: TYPEP narrowing, including the resulting representation in each arm.
(dolist (narrow-type '(fixnum (signed-byte 64) (unsigned-byte 64)
                       (integer 0 100) (integer -100 100)
                       (signed-byte 128)))
  (dolist (body `((if (typep x ',narrow-type) x 0)
                  (if (typep x ',narrow-type) 0 x)
                  (if (typep x ',narrow-type) (+ x 1) (- x 1))
                  (if (typep x ',narrow-type)
                      (the ,narrow-type x)
                      0)
                  (if (typep x ',narrow-type)
                      (logand x 18446744073709551615)
                      (ash x -1))))
    (r-drive (list 'typep-constraint narrow-type body) 'integer body)))

;;; R4: exact source regression for lvar annotations, checked for compile/run
;;; errors as well as values. CHECK-TYPE is intentionally only a probe here.
(dolist (form '((lambda (y)
                 (declare (list y) (optimize (speed 3) (safety 0)))
                 (when y (check-type y cons)))
                (lambda (y)
                 (declare (list y) (optimize (speed 3) (safety 0)))
                 (if y (the cons y) nil))
                (lambda (y)
                 (declare (list y) (optimize (speed 3) (safety 0)))
                 (if (the list y) y nil))))
  (dolist (y '(nil (1) (1 . 2)))
    (incf *r-count*)
    (let ((a (r-result (lambda () (funcall (r-compile form) y)))))
      (format t "RVALUE form=~s arg=~s => ~s~%" form y a))))

;;; R5: select-tagging through local recursive variables (cbc4c85d4), value
;;; checked on the exact upstream parser-like graph.
(let ((form '(lambda (s)
             (declare (simple-string s) (optimize (speed 3) (safety 0)))
             (labels ((outer (i sum)
                        (if (< i (length s))
                            (inner i sum 0)
                            sum))
                      (inner (j sum n)
                        (let ((d (and (< j (length s))
                                      (digit-char-p (schar s j)))))
                          (if d
                              (inner (1+ j) sum (+ (* n 10) d))
                              (outer (1+ j) (+ sum n))))))
               (outer 0 0)))))
  (dolist (s '("" "0" "123" "123x45" "999999999999999999" "1x2x3" "x"))
    (incf *r-count*)
    (format t "RVALUE tagging-parser s=~s => ~s~%" s
            (r-result (lambda () (funcall (r-compile form) s))))))
(format t "probe R done, cases=~d fails=~d~%" *r-count* *r-fails*)
