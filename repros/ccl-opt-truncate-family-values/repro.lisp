;;;; CCL compiler-macro bug: unary TRUNCATE/FLOOR/ROUND/CEILING on a fixnum
;;;; returns ONE value instead of TWO at (speed 3)(safety 0).
;;;;
;;;; Root cause: compiler/optimizers.lisp, the unary branch of each macro
;;;;   (define-compiler-macro truncate ... (if (not n1p) n0 ...))   ; ~line 1400
;;;;   (define-compiler-macro floor    ... (if (not n1p) n0 ...))   ; ~line 1410
;;;;   (define-compiler-macro round    ... (if (not n1p) n0 ...))   ; ~line 1420
;;;;   (define-compiler-macro ceiling  ... (if (not n1p) n0 ...))   ; ~line 1430
;;;; rewrites (truncate x) -> x, dropping the second (remainder/quotient) value.
;;;; CL requires exactly TWO values from these functions.
;;;;
;;;; Correct in SBCL. The defect is in shared source-level optimizer code
;;;; (no arch-specific form), so it is architecture-independent; verified on arm64.
;;;;
;;;; Note: with a CONSTANT argument, (truncate 7)/(floor 7)/(round 7) are instead
;;;; constant-folded (they appear in CAN-CONSTANT-FOLD, optimizers.lisp ~line 77)
;;;; and return the correct two values; CEILING is NOT in that list, so (ceiling 7)
;;;; shows the bug even with a constant. Using a non-constant fixnum exposes all four.

(declaim (notinline opaque))
(defun opaque (x) (declare (fixnum x)) x)   ; defeats constant-folding; type stays fixnum

(defun mvl (thunk) (multiple-value-list (funcall thunk)))

(macrolet ((probe (op)
             `(let ((bad (compile nil '(lambda ()
                          (declare (optimize (speed 3) (safety 0)))
                          (let ((x (opaque 7))) (declare (fixnum x)) (,op x)))))
                    (good (compile nil '(lambda ()
                          (declare (notinline ,op))
                          (let ((x (opaque 7))) (declare (fixnum x)) (,op x))))))
                (format t "~&~8a  opt(speed3,safety0)=~s   notinline=~s~%"
                        ',op (mvl bad) (mvl good)))))
  (probe truncate)
  (probe floor)
  (probe round)
  (probe ceiling))

(format t "~%Expected (correct, as SBCL and the notinline column): two values, e.g. (7 0).~%")
(finish-output)
#+ccl (ccl:quit)
#+sbcl (sb-ext:exit)
