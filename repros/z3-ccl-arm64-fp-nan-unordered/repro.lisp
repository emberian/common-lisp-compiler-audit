;;;; CCL 1.14 ARM64 IEEE-754 Unordered `NaN` Condition-Code Miscompilation
;;;; (`compiler/ARM64/arm642.lisp:477-485, 7845-7858, 9878-9885` +
;;;;  `level-0/l0-numbers.lisp:366-368, 1165-1169`)
;;;; Discovered via Z3 SMT AArch64 `FCMP` NZCV Modeling (Wave-2 Lane C).
;;;;
;;;; Root Cause:
;;;;   In AArch64 (ARMv8-A ARM C1.2.3), `FCMP d0, d1` sets `NZCV = 0011`
;;;;   (`N=0, Z=0, C=1, V=1`) when either operand is `NaN` (unordered).
;;;;   CCL's `arm642-double-float-compare` / `arm642-single-float-compare`
;;;;   (`arm642.lisp:7845-7858`) and `arm642-short-float-compare` (`9915-9920`)
;;;;   reuse the signed-integer condition map (`condition-to-arm64-cr-bit`):
;;;;     - `:LT` -> `cond-lt` (`0b1011`, `N != V`), which is TRUE on `0011`!
;;;;     - `:LE` -> `(values cond-gt nil)` -> `cond-le` (`0b1101`, `Z==1 || N!=V`),
;;;;                which is ALSO TRUE on `0011`!
;;;;     - `:GT` -> `cond-gt` (`0b1100`, `Z==0 && N==V`), FALSE on `0011`.
;;;;     - `:GE` -> `(values cond-lt nil)` -> `cond-ge` (`0b1010`, `N == V`),
;;;;                FALSE on `0011`.
;;;;
;;;;   On Apple Silicon / AArch64 hardware where FPCR trap-enable bits are RAZ/WI,
;;;;   ALL of the following miscompilations happen under CCL 1.14's **DEFAULT FPU MODE**
;;;;   at safe `(optimize (speed 1) (safety 3))` on quiet NaN (`1d+-0`, `1s+-0`):
;;;;     1. `(< qnan 1.0d0) => T`, `(< 1.0d0 qnan) => T`, `(< qnan qnan) => T`!
;;;;     2. `(<= qnan 1.0d0) => T`, `(<= 1.0d0 qnan) => T`, `(<= qnan qnan) => T`!
;;;;     3. `(not (< qnan 1.0d0)) => NIL`!
;;;;     4. Asymmetry: `(< qnan 1.0d0) => T` vs `(> 1.0d0 qnan) => NIL`;
;;;;        mixed `(> qnan 1.0d0) => NIL` vs `(> qnan 0) => T`!
;;;;     5. Range-guard bypass: `(<= 0.0d0 qnan 1.0d0) => T`!
;;;;     6. Differential miscompilation between generic `(notinline min)` / `(notinline max)`
;;;;        and open-coded `(declare (double-float x y))` `(min x y)` / `(max x y)`!
;;;;     7. Silent `NaN -> integer` corruption: `(truncate 1d+-0) => 0`,
;;;;        `(floor 1d+-0) => 0`, `(ceiling 1d+-0) => 1`, `(round 1d+-0) => 0`!

(defparameter *bugs* 0)

(defun check-bug (label actual expected)
  (let ((bad (not (equal actual expected))))
    (when bad (incf *bugs*))
    (format t "~&[~A] ~A~%    actual:   ~S~%    expected: ~S~%"
            (if bad "BUG CONFIRMED" "PASS")
            label actual expected)))

(defun nan-tag (v)
  (cond ((not (floatp v)) v)
        ((/= v v) :nan)
        (t v)))

(let* ((dnan (read-from-string "1d+-0"))
       (snan (read-from-string "1s+-0"))
       (f-lt      (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type double-float x y))
                                  (< x y))))
       (f-le      (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type double-float x y))
                                  (<= x y))))
       (f-gt      (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type double-float x y))
                                  (> x y))))
       (f-ge      (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type double-float x y))
                                  (>= x y))))
       (f-not-lt  (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type double-float x y))
                                  (if (not (< x y)) :not-lt :lt))))
       (f-s-lt    (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type single-float x y))
                                  (< x y))))
       (f-clamp   (compile nil '(lambda (x)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type double-float x))
                                  (if (<= 0.0d0 x 1.0d0) :in-unit-interval :rejected))))
       (f-min-gen (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (notinline min))
                                  (min x y))))
       (f-min-opt (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type double-float x y))
                                  (min x y))))
       (f-max-gen (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (notinline max))
                                  (max x y))))
       (f-max-opt (compile nil '(lambda (x y)
                                  (declare (optimize (speed 1) (safety 3))
                                           (type double-float x y))
                                  (max x y)))))
  #+ccl (format t "~&[INFO] CCL ~A default FPU mode: ~S~%"
                (lisp-implementation-version) (ccl:get-fpu-mode))

  ;; 1. (< NaN y), (< x NaN), (< NaN NaN), single-float (< sNaN 1.0s0)
  (check-bug "1a: (< qNaN 1.0d0) [double-float]"
             (funcall f-lt dnan 1.0d0) nil)
  (check-bug "1b: (< 1.0d0 qNaN) [double-float]"
             (funcall f-lt 1.0d0 dnan) nil)
  (check-bug "1c: (< qNaN qNaN) [double-float]"
             (funcall f-lt dnan dnan) nil)
  (check-bug "1d: (< qNaN 1.0s0) [single-float]"
             (funcall f-s-lt snan 1.0s0) nil)

  ;; 2. (<= NaN y), (<= x NaN), (<= NaN NaN)
  (check-bug "2a: (<= qNaN 1.0d0) [double-float]"
             (funcall f-le dnan 1.0d0) nil)
  (check-bug "2b: (<= 1.0d0 qNaN) [double-float]"
             (funcall f-le 1.0d0 dnan) nil)

  ;; 3. Branch inversion (if (not (< qNaN 1.0d0)) ...)
  (check-bug "3: (if (not (< qNaN 1.0d0)) :not-lt :lt)"
             (funcall f-not-lt dnan 1.0d0) :not-lt)

  ;; 4. Broken anti-symmetry (< x y) vs (> y x), (<= x y) vs (>= y x), and mixed (> qNaN 0)
  (check-bug "4a: symmetry (list (< qNaN 1.0d0) (> 1.0d0 qNaN))"
             (list (funcall f-lt dnan 1.0d0) (funcall f-gt 1.0d0 dnan))
             '(nil nil))
  (check-bug "4b: symmetry (list (<= qNaN 1.0d0) (>= 1.0d0 qNaN))"
             (list (funcall f-le dnan 1.0d0) (funcall f-ge 1.0d0 dnan))
             '(nil nil))
  (check-bug "4c: mixed fixnum/float (> qNaN 0) via fixnum-dfloat-compare"
             (> dnan 0) nil)

  ;; 5. Range check (<= 0.0d0 qNaN 1.0d0) admits NaN!
  (check-bug "5: range guard (if (<= 0.0d0 qNaN 1.0d0) :in-unit-interval :rejected)"
             (funcall f-clamp dnan) :rejected)

  ;; 6. Open-coded vs generic MIN and MAX differential
  (let ((gmin (nan-tag (funcall f-min-gen dnan 1.0d0)))
        (omin (nan-tag (funcall f-min-opt dnan 1.0d0)))
        (gmax (nan-tag (funcall f-max-gen dnan 1.0d0)))
        (omax (nan-tag (funcall f-max-opt dnan 1.0d0))))
    (when (not (equal gmin omin))
      (incf *bugs*)
      (format t "~&[BUG CONFIRMED] 6a: MIN differential on (qNaN, 1.0d0): notinline=>~S vs open-coded=>~S~%"
              gmin omin))
    (when (not (equal gmax omax))
      (incf *bugs*)
      (format t "~&[BUG CONFIRMED] 6b: MAX differential on (qNaN, 1.0d0): notinline=>~S vs open-coded=>~S~%"
              gmax omax)))

  ;; 7. Silent NaN -> integer corruption in TRUNCATE / FLOOR / CEILING / ROUND
  (dolist (op '(truncate floor ceiling round))
    (let ((outcome (handler-case
                       (list :returned-integer (nth-value 0 (funcall op dnan)))
                     (arithmetic-error (c)
                       (list :signaled (type-of c))))))
      (check-bug (format nil "7: (~A qNaN) silently returns integer instead of signaling" op)
                 outcome
                 '(:signaled floating-point-invalid-operation)))))

(format t "~&=== Total CCL 1.14 ARM64 NaN bugs confirmed: ~D ===~%" *bugs*)
(finish-output)
#+ccl  (ccl:quit (if (> *bugs* 0) 0 1))
#+sbcl (sb-ext:exit :code (if (= *bugs* 0) 0 1))
