;;; L: direct s128 arithmetic/comparisons and multiple consumers.
(setq *compile-print* nil *compile-verbose* nil)
(defparameter *l-fails* 0)
(defparameter *l-count* 0)
(defparameter *l-ops*
  '(+ - * < <= = > >= min max abs logand logior logxor logeqv lognot ash
    integer-length logcount logbitp evenp oddp))
(defparameter *l-vals*
  '(0 1 -1 2 -2 3 -3 63 -64 64 -65
    4611686018427387903 -4611686018427387904 4611686018427387904
    9223372036854775807 -9223372036854775808 9223372036854775808
    -9223372036854775809 18446744073709551615 18446744073709551616
    -18446744073709551616 -18446744073709551617
    85070591730234615865843651857942052864
    -85070591730234615865843651857942052864
    170141183460469231731687303715884105727
    -170141183460469231731687303715884105728))
(defun l-result (thunk)
  (handler-case (multiple-value-list (funcall thunk))
    (error (e) (list :error (type-of e) (princ-to-string e)))))
(defun l-compile (form)
  (let ((result nil))
    (with-output-to-string (*standard-output*)
      (with-output-to-string (*error-output*)
        (setf result (compile nil form))))
    result))
(defun l-drive2 (name ta tb body &optional vals)
  (incf *l-count*)
  (let ((f (l-compile `(lambda (a b)
                         (declare (type ,ta a) (type ,tb b)
                                  (optimize (speed 3) (safety 0)))
                         ,body)))
        (g (l-compile `(lambda (a b)
                         (declare (type ,ta a) (type ,tb b)
                                  (optimize (speed 3) (safety 0)))
                         (locally (declare (notinline ,@*l-ops*)) ,body))))
        (vals (or vals *l-vals*)))
    (dolist (a vals)
      (when (typep a ta)
        (dolist (b vals)
          (when (typep b tb)
            (let ((x (l-result (lambda () (funcall f a b))))
                  (y (l-result (lambda () (funcall g a b)))))
              (unless (equal x y)
                (incf *l-fails*)
                (format t "LDIVERGE ~s types=~s/~s args=~s inline=~s ref=~s~%"
                        name ta tb (list a b) x y)))))))))

;;; L1: full-range direct s128 operations. The reference decides whether an
;;; out-of-s128 mathematical result needs a larger bignum.
(dolist (op '(+ - * logand logior logxor logeqv min max < <= = > >=))
  (l-drive2 (list 's128 op) '(signed-byte 128) '(signed-byte 128) `(,op a b)))

;;; L2: mixed s128/word operations, both argument orders.
(dolist (other '((signed-byte 64) (unsigned-byte 64)))
  (dolist (op '(+ - logand logior logxor logeqv min max < <= = > >=))
    (l-drive2 (list 's128-other op other) '(signed-byte 128) other `(,op a b))
    (l-drive2 (list 'other-s128 op other) other '(signed-byte 128) `(,op a b))))

;;; L3: unary operations on the full signed-128 range.
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128)))
  (dolist (body '((- x) (abs x) (lognot x) (integer-length x) (logcount x)
                  (evenp x) (oddp x)))
    (incf *l-count*)
    (let ((f (l-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0))) ,body)))
          (g (l-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0)))
                           (locally (declare (notinline ,@*l-ops*)) ,body)))))
      (dolist (x *l-vals*)
        (when (typep x type)
          (let ((a (l-result (lambda () (funcall f x))))
                (b (l-result (lambda () (funcall g x)))))
            (unless (equal a b)
              (incf *l-fails*)
              (format t "LDIVERGE unary type=~s body=~s x=~s inline=~s ref=~s~%"
                      type body x a b))))))))

;;; L4: several consumers of one s128 result, forcing coexisting boxed and
;;; unboxed representations. Products of two s64 values fit in signed 128.
(dolist (producer '(+ - * logior logxor logand))
  (dolist (tail '(0 1 2))
    (incf *l-count*)
    (let* ((body `(let ((z (,producer a b)))
                    ,(case tail
                       (0 '(list z (ash z -64) (logand z 18446744073709551615)))
                       (1 '(list (< z 0) (= z 0) (integer-length z) (logcount z)))
                       (2 '(list (ash z 1) (ash z -1) (logbitp 100 z) (abs z))))))
           (f (l-compile `(lambda (a b)
                            (declare (type (signed-byte 64) a b)
                                     (optimize (speed 3) (safety 0))) ,body)))
           (g (l-compile `(lambda (a b)
                            (declare (type (signed-byte 64) a b)
                                     (optimize (speed 3) (safety 0)))
                            (locally (declare (notinline ,@*l-ops*)) ,body)))))
      (dolist (a *l-vals*)
        (when (typep a '(signed-byte 64))
          (dolist (b *l-vals*)
            (when (typep b '(signed-byte 64))
              (let ((x (l-result (lambda () (funcall f a b))))
                    (y (l-result (lambda () (funcall g a b)))))
                (unless (equal x y)
                  (incf *l-fails*)
                  (format t "LDIVERGE multi producer=~s tail=~d args=~s inline=~s ref=~s~%"
                          producer tail (list a b) x y))))))))))
(format t "probe L done, cases=~d fails=~d~%" *l-count* *l-fails*)
