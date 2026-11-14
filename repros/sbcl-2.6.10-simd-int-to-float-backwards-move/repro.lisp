;;;; SBCL 2.6.10 (x86-64 AND arm64) — Backwards `(move x y)` in ALL EIGHT
;;;; `%SIMD-PACK{,-256,-512}-INT-TO-{SINGLE,DOUBLE}` VOPs!
;;;;
;;;; Affected VOPs in SBCL 2.6.10:
;;;;   1-2. `src/compiler/arm64/simd-pack.lisp:334-351` (`%simd-pack-int-to-double`, `%simd-pack-int-to-single`)
;;;;   3-4. `src/compiler/x86-64/simd-pack.lisp:362-379` (`%simd-pack-int-to-double`, `%simd-pack-int-to-single`)
;;;;   5-6. `src/compiler/x86-64/simd-pack-256.lisp:357-374` (`%simd-pack-256-int-to-double`, `%simd-pack-256-int-to-single`)
;;;;   7-8. `src/compiler/x86-64/simd-pack-512.lisp:631-648` (`%simd-pack-512-int-to-double`, `%simd-pack-512-int-to-single`)
;;;;
;;;; Root cause:
;;;;   In SBCL's backends, `(move dst src)` takes DESTINATION first and SOURCE second.
;;;;   All 8 VOPs take `(:args (x ...))` and `(:results (y ...))`, omit `:target y` on `x`,
;;;;   and emit `(move x y)` (or `(move x y :16b)` on arm64) — BACKWARDS!
;;;;   Whenever `x` and `y` are allocated distinct registers (e.g. `x` remains live after the VOP),
;;;;   `(move x y)` copies uninitialized/stale `y` INTO `x`, simultaneously corrupting the caller's
;;;;   live `x` variable AND leaving `y` with stale register contents!

(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(defun trigger-backwards-simd-move (lo hi poison-lo poison-hi)
  (declare (optimize (speed 3) (safety 3))
           (type (unsigned-byte 64) lo hi poison-lo poison-hi))
  (let* ((poison (sb-ext:%make-simd-pack-ub64 poison-lo poison-hi))
         (p-int  (sb-ext:%make-simd-pack-ub64 lo hi))
         ;; Touch `poison` so its SIMD register holds `poison` and then dies right before `p-flt`:
         (touch  #+x86-64 (sb-kernel:%simd-pack-low poison)
                 #+arm64  (sb-vm::%simd-pack-double-item poison 0))
         (p-flt  (sb-vm::%simd-pack-int-to-single p-int))
         ;; Read from `p-int` AFTER `%simd-pack-int-to-single` — `p-int` itself was overwritten!
         (after  #+x86-64 (sb-kernel:%simd-pack-low p-int)
                 #+arm64  (sb-vm::%simd-pack-single-item p-int 0)))
    (list :touch touch :after-from-p-int after :p-int p-int :p-flt p-flt)))

(format t "SBCL ~A (~A)~%" (lisp-implementation-version) (machine-type))
(disassemble #'trigger-backwards-simd-move)

;; `lo`/`hi` encode floats (11.0f0, 23.5f0, 33.0f0, 44.0f0); `poison` encodes 999.0f0 in all lanes!
(let* ((res      (trigger-backwards-simd-move
                  #x41bc000041300000 #x4230000042040000
                  #x4479c0004479c000 #x4479c0004479c000))
       (flt-str  (prin1-to-string (getf res :p-flt)))
       (want-str (prin1-to-string (sb-ext:%make-simd-pack-single 11.0f0 23.5f0 33.0f0 44.0f0))))
  (format t "~%Got p-flt     : ~A~%Expected p-flt: ~A~%after-from-p-int: ~S (expected ~S)~%"
          flt-str want-str (getf res :after-from-p-int)
          #+x86-64 #x41bc000041300000 #+arm64 11.0f0)
  (when (string/= flt-str want-str)
    (format t "BUG CONFIRMED on ~A: backwards (move x y) corrupted both p-int and p-flt with poison (999.0f0)!~%"
            (machine-type))
    (sb-ext:exit :code 1)))
