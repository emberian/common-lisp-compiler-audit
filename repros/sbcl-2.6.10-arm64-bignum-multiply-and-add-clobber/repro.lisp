;;;; SBCL 2.6.10 (arm64) — Double Register-Lifetime Clobber in `BIGNUM-MULT-AND-ADD-4-ARG`
;;;; (`sb-bignum:%multiply-and-add`, `src/compiler/arm64/arith.lisp:2790-2808`)
;;;;
;;;; Reproduces at DEFAULT policy `(speed 1) (safety 1)`, `(speed 3) (safety 3)`,
;;;; and `(speed 3) (safety 0)`.
;;;;
;;;; Two independent register-lifetime bugs in one VOP:
;;;;   1. `y` (`(:argument 1)`) lacks `:to :result`, while `hi` has `:from :eval` (`:eval > (:argument 1)`).
;;;;      `hi` and `y` share `NL0`, so `(inst umulh hi x y)` overwrites `y` before `(inst mul lo x y)`!
;;;;   2. `prev` and `carry-in` specify `:to :result` = `(:result 0)`, while `lo` is the SECOND
;;;;      result (`born = (:result 1) > (:result 0)`). `lo` and `prev` share `NL1`, so
;;;;      `(inst mul lo x y)` overwrites `prev` before `(inst adds lo lo prev)`!

(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(defun mul-add-safe-ref (x y prev cin)
  (declare (type (unsigned-byte 64) x y prev cin))
  (let ((full (+ (* x y) prev cin)))
    (list (ldb (byte 64 64) full)
          (ldb (byte 64 0) full)
          x)))

(defun mul-add-compiled (x y prev cin)
  (declare (optimize (speed 3) (safety 3))
           (type (unsigned-byte 64) x y prev cin))
  (dotimes (i 1 (list y prev x))
    (multiple-value-setq (y prev)
      (sb-bignum:%multiply-and-add x y prev cin))))

(format t "SBCL ~A (~A)~%" (lisp-implementation-version) (machine-type))
(disassemble #'mul-add-compiled)

(let* ((x    #x8000000000000003)
       (y    #x4000000000000005)
       (prev #x1111111111111111)
       (cin  #x2222222222222222)
       (got  (mul-add-compiled x y prev cin))
       (want (mul-add-safe-ref x y prev cin)))
  (format t "~%Got     : ~S~%Expected: ~S~%" got want)
  (unless (equal got want)
    (format t "BUG CONFIRMED: both high and low 64-bit words were silently corrupted!~%")
    (sb-ext:exit :code 1)))
