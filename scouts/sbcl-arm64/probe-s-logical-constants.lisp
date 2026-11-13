;;; S: logical operations with constants chosen for ARM64 immediate encodings.
(setq *compile-print* nil *compile-verbose* nil)
(defparameter *s-fails* 0)
(defparameter *s-count* 0)
(defparameter *s-vals*
  '(0 1 -1 2 -2 3 -3 4 -4 15 -16 16 -17 31 -32 32 -33
    255 -256 256 -257 65535 -65536 65536 -65537
    4294967295 -4294967296 4294967296
    4611686018427387902 4611686018427387903 -4611686018427387903 -4611686018427387904
    4611686018427387904 -4611686018427387905
    9223372036854775806 9223372036854775807 -9223372036854775807 -9223372036854775808
    9223372036854775808 -9223372036854775809
    18446744073709551614 18446744073709551615 18446744073709551616
    -18446744073709551616 -18446744073709551617
    170141183460469231731687303715884105727 -170141183460469231731687303715884105728))
(defparameter *s-constants*
  '(0 1 -1 2 -2 3 -3 4 -4 7 -8 15 -16 16 -17 31 -32 32 -33
    255 -256 256 -257 65535 -65536 65536 -65537
    4294967295 -4294967296 4294967296 -4294967297
    281474976710655 -281474976710656
    71777214294589695 -71777214294589696
    4611686018427387902 4611686018427387903 4611686018427387904 4611686018427387905
    -4611686018427387903 -4611686018427387904 -4611686018427387905
    6148914691236517205 -6148914691236517206
    12297829382473034410 -12297829382473034411
    9223372036854775806 9223372036854775807 9223372036854775808 9223372036854775809
    -9223372036854775807 -9223372036854775808 -9223372036854775809
    13835058055282163711 13835058055282163712
    18446744073709551614 18446744073709551615 18446744073709551616
    -18446744073709551615 -18446744073709551616 -18446744073709551617
    170141183460469231731687303715884105727 -170141183460469231731687303715884105728))
(defun s-result (thunk)
  (handler-case (multiple-value-list (funcall thunk))
    (error (e) (list :error (type-of e)))))
(defun s-compile (form)
  (let ((result nil))
    (with-output-to-string (*standard-output*)
      (with-output-to-string (*error-output*) (setf result (compile nil form))))
    result))
(dolist (type '(fixnum (signed-byte 64) (unsigned-byte 64) (signed-byte 128) integer))
  (dolist (c *s-constants*)
    (dolist (body `((logand x ,c) (logand ,c x)
                    (logior x ,c) (logior ,c x)
                    (logxor x ,c) (logxor ,c x)
                    (logeqv x ,c) (logeqv ,c x)))
      (incf *s-count*)
      (handler-case
          (let ((f (s-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0))) ,body)))
                (g (s-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0)))
                                 (locally (declare (notinline logand logior logxor logeqv lognot)) ,body)))))
            (dolist (x *s-vals*)
              (when (typep x type)
                (let ((a (s-result (lambda () (funcall f x))))
                      (b (s-result (lambda () (funcall g x)))))
                  (unless (equal a b)
                    (incf *s-fails*)
                    (format t "SDIVERGE type=~s body=~s x=~s inline=~s ref=~s~%" type body x a b))))))
        (error (e) (format t "SERROR type=~s body=~s: ~a~%" type body e))))))
(format t "probe S done, cases=~d fails=~d~%" *s-count* *s-fails*)
