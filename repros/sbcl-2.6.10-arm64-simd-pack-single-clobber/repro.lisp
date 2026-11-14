;;;; SBCL 2.6.10 (arm64) — Silent Miscompilation at DEFAULT Optimization Policy
;;;; in `%MAKE-SIMD-PACK-SINGLE` (`src/compiler/arm64/simd-pack.lisp:269-283`)
;;;;
;;;; Bug:
;;;;   `(:args (x :scs (single-reg) :target tmp) (y :scs (single-reg))`
;;;;   `       (z :scs (single-reg)) (w :scs (single-reg)))`
;;;;   `(:temporary (:sc single-neon-reg :from (:argument 2)) tmp)`
;;;;   Because operand indices are 0-based, 3rd argument `z` has `dies = (:argument 2)`.
;;;;   `tmp` specifies `:from (:argument 2)` instead of `:from (:argument 1)`, so `tmp`
;;;;   does NOT conflict with `z`! Whenever `x` remains live after `%make-simd-pack-single`
;;;;   (preventing `tmp` from sharing `x`'s register) and `z` dies, `tmp` is allocated to
;;;;   `z`'s NEON register (`V0`), and `(inst zip1 tmp x y :2s)` overwrites `z` with `x`
;;;;   BEFORE `(inst zip1 dst z w :2s)` reads `z`!
;;;;
;;;;   Note: Exact x86-64 AVX-512 twin exists in `src/compiler/x86-64/simd-pack-512.lisp:508-540`
;;;;   (`%make-simd-pack-512-single`: `:results (dst :from (:argument 4))` clobbers 5th arg `p4`).

(declaim (muffle-conditions sb-ext:compiler-note style-warning))

;; Pure default optimization policy — zero declarations!
(defun make-pack-default (x y z w)
  (values (sb-ext:%make-simd-pack-single x y z w) x))

(format t "SBCL ~A (~A)~%" (lisp-implementation-version) (machine-type))
(disassemble #'make-pack-default)

(multiple-value-bind (pack x-out)
    (make-pack-default 11.0f0 22.0f0 33.0f0 44.0f0)
  (let ((printed (prin1-to-string pack))
        (expected (prin1-to-string (sb-ext:%make-simd-pack-single 11.0f0 22.0f0 33.0f0 44.0f0))))
    (format t "~%Got     : ~A (x=~S)~%Expected: ~A~%" printed x-out expected)
    (when (string/= printed expected)
      (format t "BUG CONFIRMED: 3rd lane (33.0f0) was silently overwritten with 11.0f0!~%")
      (sb-ext:exit :code 1))))
