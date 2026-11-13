;;; O: range< / range<= / check-range transforms and VOPs.
(setq *compile-print* nil *compile-verbose* nil)
(defparameter *o-fails* 0)
(defparameter *o-count* 0)
(defparameter *o-ops* '(< <= > >= = typep + -))
(defparameter *o-vals*
  '(0 1 -1 2 -2 3 -3 63 -64 64 -65 127 -128 128 -129
    4611686018427387902 4611686018427387903 -4611686018427387903 -4611686018427387904
    4611686018427387904 -4611686018427387905
    9223372036854775806 9223372036854775807 -9223372036854775807 -9223372036854775808
    9223372036854775808 -9223372036854775809
    18446744073709551614 18446744073709551615 18446744073709551616
    -18446744073709551616 -18446744073709551617
    170141183460469231731687303715884105727 -170141183460469231731687303715884105728))
(defparameter *o-bounds*
  '(-9223372036854775808 -4611686018427387904 -65 -2 -1 0 1 2 3 63 64
    4611686018427387902 4611686018427387903 4611686018427387904
    9223372036854775807 9223372036854775808 18446744073709551615))
(defun o-result (thunk)
  (handler-case (multiple-value-list (funcall thunk))
    (error (e) (list :error (type-of e) (princ-to-string e)))))
(defun o-compile (form)
  (let ((result nil))
    (with-output-to-string (*standard-output*)
      (with-output-to-string (*error-output*)
        (setf result (compile nil form))))
    result))
(defun o-drive (name type body)
  (incf *o-count*)
  (handler-case
      (let ((f (o-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0))) ,body)))
            (g (o-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0)))
                             (locally (declare (notinline ,@*o-ops*)) ,body)))))
        (dolist (x *o-vals*)
          (when (typep x type)
            (let ((a (o-result (lambda () (funcall f x))))
                  (b (o-result (lambda () (funcall g x)))))
              (unless (equal a b)
                (incf *o-fails*)
                (format t "ODIVERGE ~s type=~s x=~s inline=~s ref=~s~%" name type x a b))))))
    (error (e) (format t "OERROR ~s type=~s: ~a~%" name type e))))

;;; O1: three-argument comparisons become range VOPs.
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128) integer))
  (dolist (lo *o-bounds*)
    (dolist (hi *o-bounds*)
      (dolist (op '(< <=))
        (o-drive (list 'range op lo hi) type `(,op ,lo x ,hi))))))

;;; O2: TYPEP with an integer range reaches the checking variants.
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128) integer))
  (dolist (lo *o-bounds*)
    (dolist (hi *o-bounds*)
      (o-drive (list 'typep-range lo hi) type `(typep x '(integer ,lo ,hi))))))

;;; O3: variable endpoints, including mixed fixnum representations.
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128)))
  (dolist (op '(< <=))
    (incf *o-count*)
    (let ((f (o-compile `(lambda (x lo hi)
                           (declare (type ,type x) (type fixnum lo hi)
                                    (optimize (speed 3) (safety 0)))
                           (,op lo x hi))))
          (g (o-compile `(lambda (x lo hi)
                           (declare (type ,type x) (type fixnum lo hi)
                                    (optimize (speed 3) (safety 0)))
                           (locally (declare (notinline ,@*o-ops*)) (,op lo x hi))))))
      (dolist (x *o-vals*)
        (when (typep x type)
          (dolist (lo '(-4611686018427387904 -65 -2 -1 0 1 2 63 64 4611686018427387903))
            (dolist (hi '(-4611686018427387904 -65 -2 -1 0 1 2 63 64 4611686018427387903))
              (let ((a (o-result (lambda () (funcall f x lo hi))))
                    (b (o-result (lambda () (funcall g x lo hi)))))
                (unless (equal a b)
                  (incf *o-fails*)
                  (format t "ODIVERGE variable-range op=~s type=~s args=~s inline=~s ref=~s~%"
                          op type (list x lo hi) a b))))))))))
(format t "probe O done, cases=~d fails=~d~%" *o-count* *o-fails*)
