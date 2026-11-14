;;;; Repro: SBCL 2.6.10 ARM64 srctran.lisp ash-inverted + arm64/arith.lisp VOP
;;;; Confirmed zero-UB at (safety 3) and (safety 0).
;;;; Two bugs:
;;;;   1. srctran.lisp:4084 & 4118 check (combination-typed-p use %negate (:not (integer * 0))),
;;;;      which means "not guaranteed <= 0" instead of "guaranteed >= 0". For (type integer x),
;;;;      x = -1 passes and gets wrapped in (truly-the (mod 64) x), emitting LSR/ASR by (x & 63).
;;;;   2. arm64/arith.lisp:1183-1188 (ash-inverted/signed/unsigned) sets temp = #xffffffffffffffff
;;;;      via CSINV when |x| >= 64, then executes LSL result, number, temp when x < 0, which uses
;;;;      low 6 bits (63) instead of returning 0 (e.g. for (type (signed-byte 64) x) at x = -64).

(declaim (optimize (speed 1) (safety 3)))

(defun f-int (x)
  (declare (type integer x))
  (logand #xffffffffffffffff (ash 1 (- x))))

(defun f-sb64 (x)
  (declare (type (signed-byte 64) x))
  (logand #xffffffffffffffff (ash 1 (- x))))

(defun f-ref (x)
  (declare (notinline ash logand -))
  (logand #xffffffffffffffff (ash 1 (- x))))

(let ((r1 (f-int -1))
      (e1 (f-ref -1))
      (r2 (f-sb64 -64))
      (e2 (f-ref -64)))
  (format t "Arch: ~A ~A (~A)~%" (lisp-implementation-type) (lisp-implementation-version) (machine-type))
  (format t "f-int(-1)   = ~S (expected ~S, match=~S)~%" r1 e1 (eql r1 e1))
  (format t "f-sb64(-64) = ~S (expected ~S, match=~S)~%" r2 e2 (eql r2 e2)))
#+ccl (ccl:quit 0)
