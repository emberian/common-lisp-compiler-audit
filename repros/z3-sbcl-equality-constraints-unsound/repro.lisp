;;;; SBCL 2.6.10 Soundness Bug Family in `src/compiler/equality-constraints.lisp`
;;;; Discovered via Z3 SMT Symbolic Equivalence Checking (Wave-2 Lane C).
;;;;
;;;; Root Causes:
;;;;   1. `inherit-equality-p` (`src/compiler/equality-constraints.lisp:169-178`,
;;;;      commits ac267f217 / d22e9121c):
;;;;      When Y already has constraint (FROM Y Z) (NOT-P = NIL) for a finer
;;;;      equivalence FROM in {EQ, EQL, CHAR=} and an IF tests (NEW X Y) for a
;;;;      coarser equivalence NEW in {=, CHAR-EQUAL}, `inherit-equality-p`
;;;;      returns FROM instead of the lattice meet! SBCL therefore derives
;;;;      (FROM X Z) and folds (EQL X Z) / (CHAR= X Z) / (EQ X Z) to T.
;;;;   2. IEEE-754 quiet-NaN equality & ordering inversions
;;;;      (`src/compiler/equality-constraints.lisp:26-31, 535-537, 575-577`):
;;;;      - Line 535-537: `(not (= x y))` folds `(eql x y)` to NIL (fails on
;;;;        quiet NaN under SBCL's DEFAULT FPU mode!).
;;;;      - Line 575-577: `(eql x y)` folds `(= x y)` to T (fails on quiet NaN
;;;;        under SBCL's DEFAULT FPU mode!).
;;;;      - Line 26-31 (`not-operator`): `(not (< x y))` derives `(>= x y)` and
;;;;        `(not (<= x y))` derives `(> x y)` (fails on NaN when `:invalid` is
;;;;        masked).
;;;;
;;;; Zero type declarations are used below; all functions are compiled at safe
;;;; `(optimize (speed 1) (safety 3))`.

(defparameter *failures* 0)

(defun check-case (label actual expected)
  (let ((mismatch (not (equal actual expected))))
    (when mismatch (incf *failures*))
    (format t "~&[~A] ~A~%    actual:   ~S~%    expected: ~S~%"
            (if mismatch "BUG CONFIRMED" "PASS")
            label actual expected)))

(let ((f-eql-num (compile nil '(lambda (x y z)
                                 (declare (optimize (speed 1) (safety 3)))
                                 (if (eql y z)
                                     (if (= x y)
                                         (eql x z)
                                         :not-num-eq)
                                     :not-eql))))
      (f-char    (compile nil '(lambda (x y z)
                                 (declare (optimize (speed 1) (safety 3)))
                                 (if (eql y z)
                                     (if (char-equal x y)
                                         (list (eql x z) (char= x z))
                                         :not-char-equal)
                                     :not-eql))))
      (f-eq-num  (compile nil '(lambda (x y z)
                                 (declare (optimize (speed 1) (safety 3)))
                                 (if (eq y z)
                                     (if (= x y)
                                         (eq x z)
                                         :not-num-eq)
                                     :not-eq))))
      (f-nan-1   (compile nil '(lambda (x y)
                                 (declare (optimize (speed 1) (safety 3)))
                                 (if (= x y)
                                     :num-eq
                                     (if (eql x y)
                                         :eql-nan
                                         :distinct)))))
      (f-nan-2   (compile nil '(lambda (x y)
                                 (declare (optimize (speed 1) (safety 3)))
                                 (if (eql x y)
                                     (= x y)
                                     :not-eql))))
      (f-nan-ord (compile nil '(lambda (x y)
                                 (declare (optimize (speed 1) (safety 3)))
                                 (if (< x y)
                                     :lt
                                     (if (>= x y)
                                         :ge
                                         :unordered))))))
  ;; 1. Fixnum 1 vs double-float 1.0d0
  (check-case "1a: (eql 1.0d0 1.0d0) + (= 1 1.0d0) => (eql 1 1.0d0)"
              (funcall f-eql-num 1 1.0d0 1.0d0)
              nil)

  ;; 2. IEEE-754 -0.0d0 vs +0.0d0
  (check-case "1b: (eql +0.0d0 +0.0d0) + (= -0.0d0 +0.0d0) => (eql -0.0d0 +0.0d0)"
              (funcall f-eql-num -0.0d0 0.0d0 0.0d0)
              nil)

  ;; 3. Character #\a vs #\A (also breaks pure guard-verified ACL2!)
  (check-case "1c: (eql #\\A #\\A) + (char-equal #\\a #\\A) => (list (eql #\\a #\\A) (char= #\\a #\\A))"
              (funcall f-char #\a #\A #\A)
              '(nil nil))

  ;; 4. Distinct heap-allocated bignums with equal value
  (let* ((base (expt 2 100))
         (b1 (+ base (eval 1)))
         (b2 (+ base (eval 1))))
    (assert (and (not (eq b1 b2)) (= b1 b2)))
    (check-case "1d: (eq b2 b2) + (= b1 b2) => (eq b1 b2) on distinct equal bignums"
                (funcall f-eq-num b1 b2 b2)
                nil))

  ;; 5 & 6. Quiet NaN under DEFAULT FPU mode (no trap masking!)
  #+sbcl
  (let ((qnan (sb-kernel:make-double-float #x7ff80000 1)))
    (format t "~&[INFO] SBCL default FPU modes: ~S~%" (sb-int:get-floating-point-modes))
    (check-case "1e [DEFAULT FPU]: (not (= qnan qnan)) unsoundly folds (eql qnan qnan) to NIL"
                (funcall f-nan-1 qnan qnan)
                :eql-nan)
    (check-case "1f [DEFAULT FPU]: (eql qnan qnan) unsoundly folds (= qnan qnan) to T"
                (funcall f-nan-2 qnan qnan)
                nil)
    (sb-int:with-float-traps-masked (:invalid)
      (check-case "1g [:invalid masked]: (not (< qnan 1.0d0)) unsoundly folds (>= qnan 1.0d0) to T"
                  (funcall f-nan-ord qnan 1.0d0)
                  :unordered))))

(format t "~&=== Total miscompilations observed: ~D ===~%" *failures*)
(finish-output)
#+sbcl (sb-ext:exit :code (if (> *failures* 0) 0 1))
#+ccl  (ccl:quit (if (= *failures* 0) 0 1))
