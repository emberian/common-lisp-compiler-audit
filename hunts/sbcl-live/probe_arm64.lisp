(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(format t "=== Probing SBCL ~A (~A) ===~%" (lisp-implementation-version) (machine-type))

;;; 1. Probe arm64 `*/unsigned*s128=>s128` (src/compiler/arm64/arith.lisp:3073)
;;; `(define-vop (*/unsigned*s128=>s128 */s128*unsigned=>s128)
;;;    (:args (y :scs (unsigned-reg)) ((lo-x hi-x) :scs (signed-128-reg))))`
;;; Missing `:to :save` on BOTH `y` AND `(lo-x hi-x)`!
;;; Generator:
;;;   (inst umulh hi lo-x y)
;;;   (inst madd hi y hi-x hi)
;;;   (inst mul lo lo-x y)
;;; Whenever `(lo-x hi-x)` is packed into `(lo hi)` OR `y` is packed into `hi`,
;;; `(inst umulh hi lo-x y)` CLOBBERS `hi-x` (when `lo-x = lo, hi-x = hi`) or `y` (when `y = hi`)!
;;; NOTE: On arm64 there are ~24 allocatable GPRs, so we hold 16..26 live `(unsigned-byte 64)` values
;;; across `(* y s128)` so the register allocator MUST pack `(lo hi)` into `(lo-x hi-x)` or `y`!

(defun probe-arm64-s128-mul ()
  (dolist (nlive '(0 8 14 18 20 21 22 23 24 25 26))
    (let* ((lvars (loop for i below nlive collect (intern (format nil "L~D" i))))
           (fn-fast
             (compile nil
                      `(lambda (u a b ,@lvars)
                         (declare (optimize (speed 3) (safety 0))
                                  (type (unsigned-byte 63) u)
                                  (type (signed-byte 64) a b ,@lvars))
                         (let* ((s128 (+ a b))
                                ;; s128 dies here while lvars stay live in GPRs!
                                (prod (* u s128))
                                (hi64 (ash prod -64))
                                (lo64 (logand prod #xFFFFFFFFFFFFFFFF))
                                (keep (logxor ,@(or lvars '(0)))))
                           (list hi64 lo64 keep)))))
           (fn-safe
             (compile nil
                      `(lambda (u a b ,@lvars)
                         (declare (optimize (speed 0) (safety 3) (debug 3)))
                         (let* ((s128 (+ a b))
                                (prod (* u s128))
                                (hi64 (ash prod -64))
                                (lo64 (logand prod #xFFFFFFFFFFFFFFFF))
                                (keep (logxor ,@(or lvars '(0)))))
                           (list hi64 lo64 keep)))))
           ;; Choose a, b so s128 has NONZERO hi-x (e.g. negative or > 2^64-1)!
           ;; a = #x6000000000000003, b = #x6000000000000005 => s128 = #xC000000000000008 (hi-x = 0? Wait: signed 128! #xC000... fits in u64, hi-x = 0!
           ;; Make a = #x7000000000000003, b = #x7000000000000005 => a+b = #xE000000000000008 (still hi-x = 0!).
           ;; Make a = -5000000000000000000, b = -5000000000000000000 => a+b < -2^63, so hi-x = -1 (#xFFFFFFFFFFFFFFFF)!!
           ;; Even better: a = #x7FFFFFFFFFFFFFFF, b = #x7FFFFFFFFFFFFFFF => a+b = 2^64 - 2, hi-x = 0;
           ;; whereas (ash a 10) has hi-x = #x1FF! Let's test BOTH negative a+b AND (ash a 10)!
           (args (list* #x5000000000000003
                        (- (ash 1 62))
                        (- (ash 1 62) 7)
                        (loop for i below nlive collect (+ 1000 i)))))
      (let ((got (apply fn-fast args))
            (exp (apply fn-safe args)))
        (unless (equal got exp)
          (format t "~&*** HIT BUG: arm64 */unsigned*s128=>s128 (nlive=~D) ***~%  got=~S~%  exp=~S~%"
                  nlive got exp)
          (disassemble fn-fast)
          (return-from probe-arm64-s128-mul t)))))

  ;; Also test with (ash a 20) as the s128 operand so hi-x is nontrivial (#x3FFFF)!
  (dolist (nlive '(0 16 20 22 23 24 25))
    (let* ((lvars (loop for i below nlive collect (intern (format nil "K~D" i))))
           (fn-fast
             (compile nil
                      `(lambda (u a ,@lvars)
                         (declare (optimize (speed 3) (safety 0))
                                  (type (unsigned-byte 43) u)
                                  (type (signed-byte 64) a ,@lvars))
                         ;; u is (unsigned-byte 43) — wait, that's fixnum! Make u (unsigned-byte 63) and shift a by 1!
                         (let* ((s128 (ash a 1))
                                (prod (* (the (unsigned-byte 63) u) s128))
                                (hi64 (ash prod -64))
                                (lo64 (logand prod #xFFFFFFFFFFFFFFFF))
                                (keep (logxor ,@(or lvars '(0)))))
                           (list hi64 lo64 keep)))))
           (fn-safe
             (compile nil
                      `(lambda (u a ,@lvars)
                         (declare (optimize (speed 0) (safety 3) (debug 3)))
                         (let* ((s128 (ash a 1))
                                (prod (* u s128))
                                (hi64 (ash prod -64))
                                (lo64 (logand prod #xFFFFFFFFFFFFFFFF))
                                (keep (logxor ,@(or lvars '(0)))))
                           (list hi64 lo64 keep)))))
           (args (list* #x5000000000000003
                        #x6123456789ABCDEF
                        (loop for i below nlive collect (+ 2000 i)))))
      (let ((got (apply fn-fast args))
            (exp (apply fn-safe args)))
        (unless (equal got exp)
          (format t "~&*** HIT BUG (ash s128): arm64 */unsigned*s128=>s128 (nlive=~D) ***~%  got=~S~%  exp=~S~%"
                  nlive got exp)
          (disassemble fn-fast)
          (return-from probe-arm64-s128-mul t))))))

(probe-arm64-s128-mul)

;;; 2. Probe arm64 `%make-simd-pack-single` (src/compiler/arm64/simd-pack.lisp:269)
;;; Hold 26..31 live `single-float` values across `%make-simd-pack-single` while keeping `x` live
;;; and letting `z` die at `%make-simd-pack-single`, so `tmp` (:from (:argument 2)) MUST reuse `z`!
(defun probe-arm64-simd-single ()
  (dolist (nlive '(0 20 26 27 28 29 30 31))
    (let* ((lvars (loop for i below nlive collect (intern (format nil "F~D" i))))
           (fn-fast
             (compile nil
                      `(lambda (x y z w ,@lvars)
                         (declare (optimize (speed 3) (safety 0))
                                  (type single-float x y z w ,@lvars))
                         ;; z dies at %make-simd-pack-single, while x, y, w and all lvars stay live!
                         (let* ((p (sb-ext:%make-simd-pack-single x y z w))
                                (keep (+ x y w ,@(or lvars '(0.0f0)))))
                           (list (sb-ext:%simd-pack-single-item p 0)
                                 (sb-ext:%simd-pack-single-item p 1)
                                 (sb-ext:%simd-pack-single-item p 2)
                                 (sb-ext:%simd-pack-single-item p 3)
                                 keep)))))
           (args (list* 11.0f0 22.0f0 33.0f0 44.0f0
                        (loop for i below nlive collect (float (+ 100 i) 1.0f0)))))
      (let ((got (subseq (apply fn-fast args) 0 4))
            (exp '(11.0f0 22.0f0 33.0f0 44.0f0)))
        (unless (equal got exp)
          (format t "~&*** HIT BUG: arm64 %make-simd-pack-single (nlive=~D) ***~%  got=~S~%  exp=~S~%"
                  nlive got exp)
          (disassemble fn-fast)
          (return-from probe-arm64-simd-single t))))))

(probe-arm64-simd-single)

;;; 3. Probe arm64 `sb-bignum:%multiply-and-add` (src/compiler/arm64/arith.lisp:2790)
;;; Hold 18..26 live `(unsigned-byte 64)` values across `%multiply-and-add` while `y` (or `prev`/`carry-in`) dies!
(defun probe-arm64-mul-add ()
  (dolist (nlive '(0 16 18 20 21 22 23 24 25 26))
    (let* ((lvars (loop for i below nlive collect (intern (format nil "U~D" i))))
           (fn-fast
             (compile nil
                      `(lambda (x y prev cin ,@lvars)
                         (declare (optimize (speed 3) (safety 0))
                                  (type (unsigned-byte 64) x y prev cin ,@lvars))
                         ;; Let y, prev, cin die at %multiply-and-add while x and all lvars stay live!
                         (multiple-value-bind (hi lo)
                             (sb-bignum:%multiply-and-add x y prev cin)
                           (list hi lo (logxor x ,@(or lvars '(0))))))))
           (args (list* #x8000000000000003
                        #x4000000000000005
                        #x1111111111111111
                        #x2222222222222222
                        (loop for i below nlive collect (+ 500 i))))
           (full (+ (* #x8000000000000003 #x4000000000000005)
                    #x1111111111111111
                    #x2222222222222222))
           (exp (list (ldb (byte 64 64) full) (ldb (byte 64 0) full))))
      (let ((got (subseq (apply fn-fast args) 0 2)))
        (unless (equal got exp)
          (format t "~&*** HIT BUG: arm64 sb-bignum:%multiply-and-add (nlive=~D) ***~%  got=~S~%  exp=~S~%"
                  nlive got exp)
          (disassemble fn-fast)
          (return-from probe-arm64-mul-add t))))))

(probe-arm64-mul-add)
(format t "=== Done arm64 probes ===~%")
