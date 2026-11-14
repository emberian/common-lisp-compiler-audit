(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(format t "=== Probing SBCL ~A (~A) ===~%" (lisp-implementation-version) (machine-type))

;;; 1. Probe x86-64 `ash-mod64/signed=>unsigned` (src/compiler/x86-64/arith.lisp:3076)
;;; In `ash-mod64/signed=>unsigned`, `(:results (result :scs (unsigned-reg)))` dropped `:from (:argument 0)`,
;;; so `result` (born (:result 0)) does NOT conflict with `amount` (dies (:argument 1)).
;;; Yet the generator executes:
;;;   (move result number)
;;;   (move ecx amount amount-width)
;;; If `(location= result amount)`, `(move result number)` overwrites `amount` with `number`!
;;; How to force `(location= result amount)`:
;;; Put 12-16 live `(unsigned-byte 64)` / `(signed-byte 64)` values in registers across the shift,
;;; OR put `amount` in a loop variable that receives `(ldb ... result)`!

(defun probe-ash-mod64 ()
  ;; Strategy A: Loop variable `amt` updated from `result`, plus N live register variables!
  (dolist (nlive '(0 4 8 10 11 12 13 14 15 16))
    (let* ((lvars (loop for i below nlive collect (intern (format nil "L~D" i))))
           (fn-fast
             (compile nil
                      `(lambda (num amt ,@lvars)
                         (declare (optimize (speed 3) (safety 0))
                                  (type (signed-byte 64) num amt ,@lvars))
                         ;; Keep all lvars + num live in registers across the shift!
                         (let ((u-amt amt))
                           (declare (type (signed-byte 64) u-amt))
                           (dotimes (k 1 u-amt)
                             ;; u-amt dies at (ash num u-amt), and result is assigned right back into u-amt!
                             (let ((r (logand (ash num u-amt) #xFFFFFFFFFFFFFFFF)))
                               (declare (type (unsigned-byte 64) r))
                               (setf u-amt (sb-ext:truly-the (signed-byte 64)
                                             (if (> r #x7FFFFFFFFFFFFFFF) 0 r))))))
                         )))
           ;; Wait: u-amt must be returned AND lvars + num must ALSO be used AFTER dotimes so they stay in regs!
           (fn-fast2
             (compile nil
                      `(lambda (num amt ,@lvars)
                         (declare (optimize (speed 3) (safety 0))
                                  (type (signed-byte 64) num amt ,@lvars))
                         (let* ((r (logand (ash num amt) #xFFFFFFFFFFFFFFFF))
                                ;; Keep num and ALL lvars live in registers AFTER `ash` while `amt` dies at `ash`!
                                (keep (+ num ,@(or lvars '(0)))))
                           (values r keep ,@lvars)))))
           (fn-safe2
             (compile nil
                      `(lambda (num amt ,@lvars)
                         (declare (optimize (speed 0) (safety 3) (debug 3)))
                         (let* ((r (logand (ash num amt) #xFFFFFFFFFFFFFFFF))
                                (keep (+ num ,@(or lvars '(0)))))
                           (values r keep ,@lvars)))))
           (args (list* 17 2 (loop for i below nlive collect (+ 100 i)))))
      (declare (ignore fn-fast))
      (let ((got (multiple-value-list (apply fn-fast2 args)))
            (exp (multiple-value-list (apply fn-safe2 args))))
        (unless (equal got exp)
          (format t "~&*** HIT BUG: x86-64 ash-mod64/signed=>unsigned (nlive=~D) ***~%  got=~S~%  exp=~S~%"
                  nlive got exp)
          (disassemble fn-fast2)
          (return-from probe-ash-mod64 t)))))

  ;; Strategy B: `amt` in RAX (via truncate/floor result) and `r` targeted to RAX (return value or truncate dividend)!
  (dolist (nlive '(0 6 10 12 13 14))
    (let* ((lvars (loop for i below nlive collect (intern (format nil "M~D" i))))
           (fn-fast
             (compile nil
                      `(lambda (num a b ,@lvars)
                         (declare (optimize (speed 3) (safety 0))
                                  (type (signed-byte 64) num a ,@lvars)
                                  (type (integer 1 100) b))
                         ;; truncate puts quotient in RAX!
                         (let* ((amt (the (signed-byte 64) (truncate a b)))
                                ;; Now shift `num` by `amt`; `r` is then divided by `b` (targeting RAX!)
                                ;; while `num` and `lvars` remain live!
                                (r (logand (ash num amt) #xFFFFFFFFFFFFFFFF))
                                (q (truncate r b)))
                           (values r q num ,@lvars)))))
           (fn-safe
             (compile nil
                      `(lambda (num a b ,@lvars)
                         (declare (optimize (speed 0) (safety 3) (debug 3)))
                         (let* ((amt (the (signed-byte 64) (truncate a b)))
                                (r (logand (ash num amt) #xFFFFFFFFFFFFFFFF))
                                (q (truncate r b)))
                           (values r q num ,@lvars)))))
           (args (list* 17 6 3 (loop for i below nlive collect (+ 200 i)))))
      (let ((got (multiple-value-list (apply fn-fast args)))
            (exp (multiple-value-list (apply fn-safe args))))
        (unless (equal got exp)
          (format t "~&*** HIT BUG (RAX target): x86-64 ash-mod64/signed=>unsigned (nlive=~D) ***~%  got=~S~%  exp=~S~%"
                  nlive got exp)
          (disassemble fn-fast)
          (return-from probe-ash-mod64 t))))))

(probe-ash-mod64)

;;; 2. Probe x86-64 `%more-arg-values-skip` (src/compiler/x86-64/values.lisp:162)
;;; Triggered by `(multiple-value-call ... (values-list ...))` or `(nthcdr skip rest)` -> `values-list`!
;;; Let's check both variable `skip` under register pressure and `apply` patterns.
(defun probe-more-arg-skip ()
  (dolist (nlive '(0 6 8 10 11 12 13 14))
    (let* ((lvars (loop for i below nlive collect (intern (format nil "R~D" i))))
           (fn-fast
             (compile nil
                      `(lambda (skip ,@lvars &rest more)
                         (declare (optimize (speed 3) (safety 0))
                                  (type (integer 0 100) skip)
                                  (type fixnum ,@lvars))
                         (multiple-value-bind (x y z)
                             (values-list (nthcdr skip more))
                           (list x y z (+ ,@(or lvars '(0))))))))
           (fn-safe
             (compile nil
                      `(lambda (skip ,@lvars &rest more)
                         (declare (optimize (speed 0) (safety 3) (debug 3)))
                         (multiple-value-bind (x y z)
                             (values-list (nthcdr skip more))
                           (list x y z (+ ,@(or lvars '(0))))))))
           (args (append (list 2)
                         (loop for i below nlive collect (1+ i))
                         (list :a :b :c :d :e))))
      (let ((got (apply fn-fast args))
            (exp (apply fn-safe args)))
        (unless (equal got exp)
          (format t "~&*** HIT BUG: x86-64 %more-arg-values-skip (nlive=~D) ***~%  got=~S~%  exp=~S~%"
                  nlive got exp)
          (disassemble fn-fast)
          (return-from probe-more-arg-skip t))))))

(probe-more-arg-skip)

;;; 3. Probe x86-64 `bignum-add-loop` & `bignum-negate-loop`
(defun probe-bignum-loops ()
  ;; Test bignum addition and negation across multi-word sizes (2..8 words) and signs
  (let ((vals (list (- (ash 1 65) 1)
                    (- (ash 1 128) 1)
                    (- (ash 1 192) 3)
                    (- (ash 1 256) 5)
                    (- (1+ (ash 1 64)))
                    (- (1+ (ash 1 128)))
                    (- (1+ (ash 1 192)))
                    (ash #xdeadbeefcafebabe 64)
                    (logior (ash #x7fffffffffffffff 128) (ash #x123456789abcdef0 64) 1))))
    (dolist (a vals)
      (let ((neg-fast (funcall (compile nil '(lambda (x) (declare (optimize (speed 3) (safety 0))) (- (the bignum x)))) a))
            (neg-safe (- a)))
        (unless (= neg-fast neg-safe)
          (format t "~&*** HIT BUG: bignum negate a=~X got=~X exp=~X ***~%" a neg-fast neg-safe)))
      (dolist (b vals)
        (let ((sum-fast (funcall (compile nil '(lambda (x y) (declare (optimize (speed 3) (safety 0))) (+ (the bignum x) (the bignum y)))) a b))
              (sum-safe (+ a b)))
          (unless (= sum-fast sum-safe)
            (format t "~&*** HIT BUG: bignum add a=~X b=~X got=~X exp=~X ***~%" a b sum-fast sum-safe)))))))

(probe-bignum-loops)
(format t "=== Done x86-64 probes ===~%")
