;;;; SBCL 2.6.10 Soundness & Compiler-Failure Bug Family in `same-arg` Float `derive-type`
;;;; (`src/compiler/srctran.lisp:2098-2121, 2247-2250, 2611-2626, 2808-2813, 2843-2849`)
;;;; Discovered via Z3 SMT IEEE-754 Symbolic Interval Checking (Wave-2 Lane C).
;;;;
;;;; Root Causes:
;;;;   1. Compile-time bogus full WARNING (`compile-file` `failure-p = T`) at default
;;;;      `(optimize (speed 1) (safety 3))`:
;;;;      In `(defun f (x) (declare (double-float x)) (truncate x x))` (and `floor`,
;;;;      `ceiling`), `truncate-derive-type-quot-aux` (`srctran.lisp:2614`) sees
;;;;      `same-arg = T` and derives quotient type `(INTEGER 1 1)`, which conflicts
;;;;      with the `BIGNUM` arm of `unary-truncate` (`src/compiler/float-tran.lisp:1870`),
;;;;      emitting a full `WARNING` during compilation without ever calling `f`!
;;;;   2. Runtime wrong folding of `0.0d0 / 0.0d0 = NaN` to `1.0d0`:
;;;;      `/-derive-type-aux` (`srctran.lisp:2247-2250`), `truncate-derive-type-quot-aux`
;;;;      (`srctran.lisp:2611-2626`), and `ffloor`/`fceiling` `derive-type`
;;;;      (`srctran.lisp:2808-2813, 2843-2849`) derive singleton `1.0d0` (and remainder
;;;;      `0.0d0`) whenever `x` has bounded float type `(double-float -1.0d0 1.0d0)`,
;;;;      forgetting that `0.0d0` is in `[-1.0d0, 1.0d0]` and `0.0d0 / 0.0d0 = NaN`!
;;;;   3. Runtime wrong signed-zero folding of `(- x x)` under `:negative-infinity`
;;;;      rounding (`srctran.lisp:2098-2121`):
;;;;      `--derive-type-aux` derives `(double-float 0.0d0 0.0d0)` with
;;;;      `:normalize-zeros nil`, folding `(- 1.0d0 1.0d0)` to `+0.0d0` even though
;;;;      IEEE-754 `roundTowardNegative` specifies `x - x = -0.0d0`!
;;;;
;;;; Every runtime input below strictly satisfies its declared type (zero UB).

(defparameter *bugs* 0)

(defun note-bug (fmt &rest args)
  (incf *bugs*)
  (format t "~&[BUG CONFIRMED] ~?~%" fmt args))

;;; --- Part 1: Bogus full WARNING breaking `compile` / `compile-file` at default safety ---
(dolist (op '(truncate floor ceiling))
  (let ((full-warnings nil))
    (handler-bind ((warning (lambda (w)
                              (when (not (typep w 'style-warning))
                                (push (princ-to-string w) full-warnings)))))
      (compile nil `(lambda (x)
                      (declare (optimize (speed 1) (safety 3))
                               (type double-float x))
                      (,op x x))))
    (if full-warnings
        (note-bug "(~A x x) on DOUBLE-FLOAT emitted ~D full WARNING(s) at compile time: ~A"
                  op (length full-warnings) (first full-warnings))
        (format t "~&[PASS] (~A x x) compiled cleanly~%" op))))

;;; --- Part 2: 0.0d0 / 0.0d0 => NaN folded to 1.0d0 ---
(let ((f-div-same (compile nil '(lambda (x)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type (double-float -1.0d0 1.0d0) x))
                                  (let ((q (/ x x)))
                                    (list :nan-p (sb-ext:float-nan-p q)
                                          :eql-1 (eql q 1.0d0)
                                          :val q)))))
      (f-div-ref  (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type (double-float -1.0d0 1.0d0) x y))
                                  (let ((q (/ x y)))
                                    (list :nan-p (sb-ext:float-nan-p q)
                                          :eql-1 (eql q 1.0d0)
                                          :val q)))))
      (f-ftrunc   (compile nil '(lambda (x)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type (double-float -1.0d0 1.0d0) x))
                                  (multiple-value-bind (q r) (ftruncate x x)
                                    (list :q-nan (sb-ext:float-nan-p q)
                                          :r-nan (sb-ext:float-nan-p r)
                                          :q q :r r)))))
      (f-ffloor   (compile nil '(lambda (x)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type (double-float -1.0d0 1.0d0) x))
                                  (multiple-value-bind (q r) (ffloor x x)
                                    (list :q-nan (sb-ext:float-nan-p q)
                                          :r-nan (sb-ext:float-nan-p r)
                                          :q q :r r)))))
      (f-fceil    (compile nil '(lambda (x)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type (double-float -1.0d0 1.0d0) x))
                                  (multiple-value-bind (q r) (fceiling x x)
                                    (list :q-nan (sb-ext:float-nan-p q)
                                          :r-nan (sb-ext:float-nan-p r)
                                          :q q :r r))))))
  (sb-int:with-float-traps-masked (:invalid :divide-by-zero)
    (let ((same (funcall f-div-same 0.0d0))
          (ref  (funcall f-div-ref  0.0d0 0.0d0)))
      (if (not (equal (subseq same 0 4) (subseq ref 0 4)))
          (note-bug "(/ x x) at x=0.0d0 => ~S, expected reference (/ x y) => ~S" same ref)
          (format t "~&[PASS] (/ x x) at x=0.0d0 matches reference~%")))
    (dolist (entry (list (cons 'ftruncate f-ftrunc)
                         (cons 'ffloor    f-ffloor)
                         (cons 'fceiling  f-fceil)))
      (let ((res (funcall (cdr entry) 0.0d0)))
        (if (not (and (getf res :q-nan) (getf res :r-nan)))
            (note-bug "(~A x x) at x=0.0d0 folded NaN to ~S" (car entry) res)
            (format t "~&[PASS] (~A x x) preserved NaN~%" (car entry)))))))

;;; --- Part 3: (- x x) under IEEE-754 roundTowardNegative (:negative-infinity) ---
(let ((f-sub-same (compile nil '(lambda (x)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type (double-float 0.0d0 2.0d0) x))
                                  (let ((d (- x x)))
                                    (list :sign (float-sign d)
                                          :eql-neg-zero (eql d -0.0d0))))))
      (f-sub-ref  (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type (double-float 0.0d0 2.0d0) x y))
                                  (let ((d (- x y)))
                                    (list :sign (float-sign d)
                                          :eql-neg-zero (eql d -0.0d0)))))))
  (let ((saved (sb-int:get-floating-point-modes)))
    (unwind-protect
         (progn
           (sb-int:set-floating-point-modes :rounding-mode :negative-infinity)
           (let ((same (funcall f-sub-same 1.0d0))
                 (ref  (funcall f-sub-ref  1.0d0 1.0d0)))
             (if (not (equal same ref))
                 (note-bug "(- x x) under :negative-infinity at x=1.0d0 => ~S, expected ~S"
                           same ref)
                 (format t "~&[PASS] (- x x) under :negative-infinity matches reference~%"))))
      (apply #'sb-int:set-floating-point-modes saved))))

(format t "~&=== Total same-arg derive-type bugs confirmed: ~D ===~%" *bugs*)
(finish-output)
(sb-ext:exit :code (if (> *bugs* 0) 0 1))
