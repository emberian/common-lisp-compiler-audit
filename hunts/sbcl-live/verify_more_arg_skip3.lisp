(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(declaim (notinline sink))
(defun sink (x) x)

(format t "=== 1. Check if %more-arg-values-skip hits even with ZERO declarations (default policy)! ===~%")
;; Without calling it (so we don't kill SBCL!), check disassembly across shapes at default policy!
(block find-zero-decl
  (dotimes (nprefix 8)
    (dotimes (nlive 12)
      (let* ((pvars (loop for i below nprefix collect (intern (format nil "P~D" i))))
             (lvars (loop for i below nlive collect (intern (format nil "L~D" i))))
             (fn (compile nil
                   `(lambda (,@pvars &rest r)
                      (let (,@(loop for v in lvars for i from 0
                                    collect `(,v (cons ,i ,(if pvars (nth (mod i nprefix) pvars) nil)))))
                        (multiple-value-prog1
                            (values-list (cdr r))
                          (sink (list ,@lvars)))))))
             (dis (with-output-to-string (s) (disassemble fn :stream s))))
        (when (and (search "XOR " dis) (search "-8]" dis))
          (let ((lines (let ((res nil) (st 0))
                         (loop for p = (position #\Newline dis :start st)
                               do (push (subseq dis st (or p (length dis))) res)
                               while p do (setf st (1+ p)))
                         (nreverse res))))
            (loop for (l1 l2) on lines
                  when (and l1 l2 (search "XOR " l1) (search "-8]" l2))
                  do (let* ((xp (search "XOR " l1))
                            (cm (and xp (position #\, l1 :start xp)))
                            (r32 (and xp cm (string-trim " " (subseq l1 (+ xp 4) cm))))
                            (r64 (cond ((and (>= (length r32) 2) (char= (char r32 0) #\E))
                                        (concatenate 'string "R" (subseq r32 1)))
                                       ((and (>= (length r32) 2) (char= (char r32 (1- (length r32))) #\D))
                                        (subseq r32 0 (1- (length r32))))
                                       (t r32))))
                       (when (search (concatenate 'string "[" r64 "-8]") l2)
                         (format t "ZERO-DECL DEFAULT POLICY HIT! nprefix=~D nlive=~D reg=~A~%  ~A~%  ~A~%"
                                 nprefix nlive r64 l1 l2)
                         (return-from find-zero-decl t))))))))))

(format t "~%=== 2. Probe bignum-add-loop ===~%")
(dolist (keep '(:none :la :lb :both))
  (dotimes (nlive 11)
    (let* ((lvars (loop for i below nlive collect (intern (format nil "U~D" i))))
           (ret-expr (ecase keep
                       (:none `(logior ,@lvars 0))
                       (:la `(logior la ,@lvars 0))
                       (:lb `(logior lb ,@lvars 0))
                       (:both `(logior la lb ,@lvars 0))))
           (fn (compile nil
                 `(lambda (a b la lb r ,@lvars)
                    (declare (optimize (speed 3) (safety 0))
                             (type bignum a b r)
                             (type (unsigned-byte 32) la lb ,@lvars))
                    (sb-sys:%primitive sb-vm::bignum-add-loop a b la lb r)
                    ,ret-expr)))
           (dis (with-output-to-string (s) (disassemble fn :stream s)))
           (ba (+ (ash -1 130) 99))
           (bb (+ (ash 1 70) 7))
           (res (sb-bignum:%allocate-bignum 4))
           (args (append (list ba bb 3 2 res) (loop for i below nlive collect (1+ i)))))
      ;; Before calling, check if MOV clobbers la or lb!
      (apply fn args)
      (let ((norm (sb-bignum::%normalize-bignum res 4))
            (want (+ ba bb)))
        (unless (= norm want)
          (format t "BIGNUM-ADD-LOOP MISMATCH keep=~S nlive=~D: got ~D want ~D~%~A~%"
                  keep nlive norm want dis)
          (return))))))

;; Wait: what if `la` and `lb` come from calculations in registers where `remaining-length` gets `lb`'s reg, OR `length` gets `la`'s reg?!
;; Why didn't `remaining-length` get `lb`'s reg above? Because `la` has `:target remaining-length` and `lb` has `:target length`!
;; When `la` is STILL LIVE after `bignum-add-loop`, `remaining-length` CANNOT use `la`'s register!
;; So `remaining-length` looks for ANOTHER free `unsigned-reg` — and if `lb` DIES at `bignum-add-loop` AND `length` CANNOT use `lb`'s register (wait: why wouldn't `length` use `lb`'s register? Because `length` is packed BEFORE or AFTER `remaining-length`! Let's check which temp is packed first, or force `lb` into a specific register like `RCX` via `(ash ... lb)` and force `remaining-length` to want `RCX` after, wait `remaining-length` is an internal temp so it's not used after, it just picks the first free register in SC order (`RAX`, `RDX`, `RCX`, `RBX`, `RSI`, `RDI`, `R8`..)!).
;; WAIT A SECOND! If `lb` is in `RAX` (e.g. returned from a function call or `(rem ...)` or `(truncate ...)`!) AND `la` is STILL LIVE after `bignum-add-loop`, AND `length` is packed... wait: `length` is declared BEFORE `remaining-length` in `(:temporary (:sc unsigned-reg :from (:argument 2)) length)`!
;; What if `lb` is STILL LIVE after `bignum-add-loop`, while `la` DIES at `bignum-add-loop`?!
;; Trace THAT!!
;; - `lb` is STILL LIVE after `bignum-add-loop` -> `length` CANNOT get `lb`'s register!
;; - `la` DIES at `(:argument 2)`!
;; - `length` has `:from (:argument 2)`, so `length` DOES NOT CONFLICT WITH `la`!!
;; - And `la` is in `RAX` (the VERY FIRST register in `unsigned-reg` allocation order!!)!
;; - Wait: `remaining-length` has `:target` from `la`, so if `remaining-length` gets `la`, then `length` can't get `la`. How do we prevent `remaining-length` from getting `la`'s register? Put `la` in a register that conflicts with `remaining-length`? No, `remaining-length` lives `(:argument 3)..:save`, and `length` lives `(:argument 2)..:save`, so `length` and `remaining-length` conflict with each other; whichever is packed FIRST by `pack` gets `la` (`RAX`)! If `length` is packed BEFORE `remaining-length` (higher cost / earlier TN!), `length` steals `la`'s register (`RAX`), while `remaining-length` gets `RDX`!
;; Let's check the disassembly when `keep = :lb` and `la = (ldb (byte 32 0) (sink-u64 x))` (so `la` is in `RAX` or `RDX`!)!
(declaim (notinline id-u32))
(declaim (ftype (function ((unsigned-byte 32)) (values (unsigned-byte 32) &optional)) id-u32))
(defun id-u32 (x) x)

(format t "~%=== 3. Targeted bignum-add-loop (la from call, lb kept live) ===~%")
(dotimes (nlive 10)
  (let* ((lvars (loop for i below nlive collect (intern (format nil "U~D" i))))
         (fn (compile nil
               `(lambda (a b x lb r ,@lvars)
                  (declare (optimize (speed 3) (safety 0))
                           (type bignum a b r)
                           (type (unsigned-byte 32) x lb ,@lvars))
                  (let ((la (id-u32 x)))
                    (sb-sys:%primitive sb-vm::bignum-add-loop a b la lb r)
                    (logior lb ,@lvars 0)))))
         (ba (+ (ash -1 130) 99))
         (bb (+ (ash 1 70) 7))
         (res (sb-bignum:%allocate-bignum 4))
         (args (append (list ba bb 3 2 res) (loop for i below nlive collect (1+ i)))))
    (when (= nlive 0) (disassemble fn))
    (apply fn args)
    (let ((norm (sb-bignum::%normalize-bignum res 4))
          (want (+ ba bb)))
      (unless (= norm want)
        (format t "BIGNUM-ADD-LOOP CALL MISMATCH nlive=~D: got ~D want ~D~%" nlive norm want)
        (disassemble fn)
        (return)))))

(format t "~%=== 4. Inspect bignum-negate-last-two-loop & nlx-entry-multiple ===~%")
;; In bignum-negate-last-two-loop:
;; (:args (a :to :save) (l :target length))
;; (:temporary (:from (:argument 1)) length)
;; (:results (last1) (last2))
;; Generator: (zeroize last2) (zeroize index) (move length l :dword) ...
;; If `last2` is targeted to `RAX` (e.g. returned as primary value!) and `l` is ALSO in `RAX` (e.g. from `(id-u32 x)`) AND `length` doesn't get `RAX` because `last2` (`(:result 1)..:save`) is packed into `RAX` FIRST (since `last2` targets the return register `RDX`! Wait: on x86-64 Lisp calling convention, first return value is `RDX`!!)!
;; WAIT A SECOND! On x86-64 SBCL, single/first return value register is `RDX`!
;; So `(id-u32 x)` puts `l` in `RDX` (unboxed or boxed -> `SHR RDX, 1` in `RDX`)!
;; AND returning `last2` targets `last2` to `RDX`!!
;; Let's test `(let ((l (id-u32 x))) (multiple-value-bind (last1 last2) (%primitive bignum-negate-last-two-loop a l) (declare (ignore last1)) last2))` — DO NOT CALL BEFORE CHECKING DISASSEMBLY (if `XOR EDX, EDX` zeroes `RDX` before `MOV ..., EDX`, calling it would loop 2^32 times and segfault!).
(let* ((fn (compile nil
             '(lambda (a x)
                (declare (optimize (speed 3) (safety 0))
                         (type bignum a)
                         (type (unsigned-byte 32) x))
                (let ((l (id-u32 x)))
                  (multiple-value-bind (last1 last2)
                      (sb-sys:%primitive sb-vm::bignum-negate-last-two-loop a l)
                    (declare (ignore last1))
                    last2))))))
  (disassemble fn))

;; Also test with `l` forced into `RCX` (via shift) and `last2` forced into `RCX` (used as shift count right after!!):
(let* ((fn (compile nil
             '(lambda (a l y)
                (declare (optimize (speed 3) (safety 0))
                         (type bignum a)
                         (type (unsigned-byte 6) l)
                         (type (unsigned-byte 64) y))
                (let ((y2 (ash y l))) ; forces l into RCX? No, l is still live for primitive! Wait: use (let ((l2 (logand l 63))) ...)
                  (multiple-value-bind (last1 last2)
                      (sb-sys:%primitive sb-vm::bignum-negate-last-two-loop a l)
                    (declare (ignore last1))
                    (ash y2 (logand last2 63))))))))
  (disassemble fn))

;; Test nlx-entry-multiple (catch/throw multiple values + unwind-protect multiple values)
(defun test-nlx-mv (x y z)
  (declare (optimize (speed 3) (safety 0)))
  (multiple-value-list
   (catch 'tag
     (unwind-protect
          (throw 'tag (values x y z (+ x y)))
       (sink z)))))
(disassemble #'test-nlx-mv)
(format t "nlx-mv result: ~S~%" (test-nlx-mv 10 20 30))
