;;; P: arithmetic with large/signed constants, including u64 minus negative.
(setq *compile-print* nil *compile-verbose* nil)
(defparameter *p-fails* 0)
(defparameter *p-count* 0)
(defparameter *p-vals*
  '(0 1 -1 2 -2 3 -3 4 -4 63 -64 64 -65
    4611686018427387902 4611686018427387903 -4611686018427387903 -4611686018427387904
    4611686018427387904 -4611686018427387905
    9223372036854775806 9223372036854775807 -9223372036854775807 -9223372036854775808
    9223372036854775808 -9223372036854775809
    18446744073709551614 18446744073709551615 18446744073709551616
    -18446744073709551616 -18446744073709551617
    170141183460469231731687303715884105727 -170141183460469231731687303715884105728))
(defparameter *p-constants*
  '(-18446744073709551616 -18446744073709551615
    -9223372036854775809 -9223372036854775808 -9223372036854775807
    -4611686018427387905 -4611686018427387904 -4611686018427387903
    -65537 -65536 -257 -256 -255 -17 -16 -15 -9 -8 -7 -5 -4 -3 -2 -1
    0 1 2 3 4 5 7 8 9 15 16 17 255 256 257 65535 65536 65537
    4611686018427387902 4611686018427387903 4611686018427387904
    9223372036854775806 9223372036854775807 9223372036854775808
    18446744073709551614 18446744073709551615 18446744073709551616))
(defun p-result (thunk)
  (handler-case (multiple-value-list (funcall thunk))
    (error (e) (list :error (type-of e) (princ-to-string e)))))
(defun p-compile (form)
  (let ((result nil))
    (with-output-to-string (*standard-output*)
      (with-output-to-string (*error-output*)
        (setf result (compile nil form))))
    result))
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128)))
  (dolist (c *p-constants*)
    (dolist (body `((+ x ,c) (+ ,c x) (- x ,c) (- ,c x) (* x ,c) (* ,c x)))
      (incf *p-count*)
      (handler-case
          (let ((f (p-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0))) ,body)))
                (g (p-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0)))
                                 (locally (declare (notinline + - * ash)) ,body)))))
            (dolist (x *p-vals*)
              (when (typep x type)
                (let ((a (p-result (lambda () (funcall f x))))
                      (b (p-result (lambda () (funcall g x)))))
                  (unless (equal a b)
                    (incf *p-fails*)
                    (format t "PDIVERGE type=~s body=~s x=~s inline=~s ref=~s~%" type body x a b))))))
        (error (e) (format t "PERROR type=~s body=~s: ~a~%" type body e))))))
(format t "probe P done, cases=~d fails=~d~%" *p-count* *p-fails*)
