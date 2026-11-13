;;; M: division transforms selected by their destination context.
(setq *compile-print* nil *compile-verbose* nil)
(defparameter *m-fails* 0)
(defparameter *m-count* 0)
(defparameter *m-ops* '(floor truncate ceiling mod rem = < > <= >= abs + - * min max ash logand))
(defparameter *m-vals*
  '(0 1 -1 2 -2 3 -3 4 -4 5 -5 6 -6 7 -7 8 -8 9 -9 10 -10
    127 -128 128 -129 129 -130 255 -256 256 -257 257 -258
    4611686018427387902 4611686018427387903 -4611686018427387903 -4611686018427387904
    4611686018427387904 -4611686018427387905
    9223372036854775806 9223372036854775807 -9223372036854775807 -9223372036854775808
    9223372036854775808 -9223372036854775809
    18446744073709551614 18446744073709551615
    170141183460469231731687303715884105727 -170141183460469231731687303715884105728))
(defparameter *m-divisors*
  '(2 -2 3 -3 5 -5 6 -6 7 -7 10 -10 12 -12 129 -129 130 -130
    255 256 257 1000 -1000 65537
    2147483647 2147483648 4294967295 4294967296
    4611686018427387903 4611686018427387904
    9223372036854775807 -9223372036854775808 18446744073709551615))
(defun m-result (thunk)
  (handler-case (multiple-value-list (funcall thunk))
    (error (e) (list :error (type-of e) (princ-to-string e)))))
(defun m-compile (form)
  (let ((result nil))
    (with-output-to-string (*standard-output*)
      (with-output-to-string (*error-output*)
        (setf result (compile nil form))))
    result))
(defun m-drive (name type body)
  (incf *m-count*)
  (handler-case
      (let ((f (m-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0))) ,body)))
            (g (m-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0)))
                             (locally (declare (notinline ,@*m-ops*)) ,body)))))
        (dolist (x *m-vals*)
          (when (typep x type)
            (let ((a (m-result (lambda () (funcall f x))))
                  (b (m-result (lambda () (funcall g x)))))
              (unless (equal a b)
                (incf *m-fails*)
                (format t "MDIVERGE ~s type=~s x=~s inline=~s ref=~s~%" name type x a b))))))
    (error (e) (format t "MERROR ~s type=~s: ~a~%" name type e))))

;;; M1: divisibility/remainder sign predicates. These select code paths that
;;; a multiple-value-list comparison of TRUNCATE itself does not reach.
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128)))
  (dolist (c *m-divisors*)
    (dolist (body `((= (rem x ,c) 0)
                    (> (rem x ,c) 0)
                    (< (rem x ,c) 0)
                    (= (mod x ,c) 0)
                    (> (mod x ,c) 0)
                    (< (mod x ,c) 0)))
      (m-drive (list 'remainder-predicate body) type body))))

;;; M2: nested ABS/division rewrites; compare all values.
(dolist (type '(fixnum (signed-byte 64) (signed-byte 128)))
  (dolist (outer '(truncate floor ceiling))
    (dolist (inner '(truncate floor ceiling))
      (dolist (c1 '(2 -2 3 -3 16 -16 129 -129))
        (dolist (c2 '(2 -2 3 -3 16 -16 129 -129))
          (m-drive (list 'nested-div outer inner c1 c2) type
                   `(,outer (abs (,inner x ,c1)) ,c2)))))))

;;; M3: same-variable division and small-range checked-result shapes.
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128)))
  (dolist (op '(truncate floor ceiling))
    (m-drive (list 'same-var op) type `(,op x x))))
(dolist (op '(truncate floor ceiling))
  (dolist (c '(2 -2 3 -3 129 -129))
    (m-drive (list 'checked-fixnum op c) '(integer -1000 1000)
             `(the fixnum (,op x ,c)))))
(format t "probe M done, cases=~d fails=~d~%" *m-count* *m-fails*)
