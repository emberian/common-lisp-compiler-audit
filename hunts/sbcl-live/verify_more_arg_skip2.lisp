(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(declaim (notinline sink))
(defun sink (x) x)

(format t "=== 1. Test exact HIT at (safety 3) AND default policy ===~%")
(dolist (opt '(((speed 1) (safety 1))
               ((speed 2) (safety 3))
               ((speed 3) (safety 3))
               ((speed 0) (safety 3))))
  (let* ((fn (compile nil
               `(lambda (p0 p1 p2 p3 p4 p5 p6 p7 p8 p9 &rest r)
                  (declare (optimize ,@opt)
                           (type fixnum p0 p1 p2 p3 p4 p5 p6 p7 p8 p9))
                  (let ((l0 (the fixnum (+ 1 p0)))
                        (l1 (the fixnum (+ 2 p1)))
                        (l2 (the fixnum (+ 3 p2)))
                        (l3 (the fixnum (+ 4 p3)))
                        (l4 (the fixnum (+ 5 p4)))
                        (l5 (the fixnum (+ 6 p5))))
                    (declare (type fixnum l0 l1 l2 l3 l4 l5))
                    (multiple-value-prog1
                        (values-list (cdr r))
                      (sink (list l0 l1 l2 l3 l4 l5)))))))
         (dis (with-output-to-string (s) (disassemble fn :stream s))))
    (format t "Policy ~S: XOR+RCX-8=~A~%"
            opt (and (search "XOR ECX, ECX" dis) (search "[RCX-8]" dis) t))
    (handler-case
        (let ((res (multiple-value-list
                    (funcall fn 0 1 2 3 4 5 6 7 8 9 :drop :keep-a :keep-b))))
          (format t "  Returned: ~S~%" res))
      (serious-condition (e)
        (format t "  CRASHED (~S): ~A~%" (type-of e) e)))))

(format t "~%=== 2. Probe bignum-add-loop & bignum-negate-last-two-loop & nlx-entry-multiple ===~%")
(dotimes (nlive 12)
  (let* ((lvars (loop for i below nlive collect (intern (format nil "U~D" i))))
         (fn (compile nil
               `(lambda (a b la lb r ,@lvars)
                  (declare (optimize (speed 3) (safety 0))
                           (type bignum a b r)
                           (type (unsigned-byte 32) la lb ,@lvars))
                  (sb-sys:%primitive sb-vm::bignum-add-loop a b la lb r)
                  (logior ,@lvars 0))))
         (dis (with-output-to-string (s) (disassemble fn :stream s)))
         (ba (ash 1 130))
         (bb (+ (ash 1 70) 7))
         (res (sb-bignum:%allocate-bignum 4))
         (args (append (list ba bb 3 2 res) (loop for i below nlive collect (1+ i)))))
    (apply fn args)
    (let ((norm (sb-bignum::%normalize-bignum res 4))
          (want (+ ba bb)))
      (unless (= norm want)
        (format t "BIGNUM-ADD-LOOP MISMATCH nlive=~D: got #x~X want #x~X~%~A~%"
                nlive norm want dis)
        (return)))))

;; Also try keeping la live vs lb dead, and lb live vs la dead!
(dolist (keep '(:none :la :lb :both))
  (dotimes (nlive 10)
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
           (ba (+ (ash -1 130) 99)) ; negative 3-word bignum!
           (bb (+ (ash 1 70) 7))    ; positive 2-word bignum!
           (res (sb-bignum:%allocate-bignum 4))
           (args (append (list ba bb 3 2 res) (loop for i below nlive collect (1+ i)))))
      (apply fn args)
      (let ((norm (sb-bignum::%normalize-bignum res 4))
            (want (+ ba bb)))
        (unless (= norm want)
          (format t "BIGNUM-ADD-LOOP MISMATCH keep=~S nlive=~D: got ~D want ~D~%"
                  keep nlive norm want)
          (disassemble fn)
          (return))))))

;; Probe bignum-negate-last-two-loop (used inline in float conversion of negative bignums!)
(format t "~%=== 3. Test float conversion of negative multi-word bignums under reg pressure ===~%")
(dotimes (nlive 12)
  (let* ((lvars (loop for i below nlive collect (intern (format nil "U~D" i))))
         (fn (compile nil
               `(lambda (b ,@lvars)
                  (declare (optimize (speed 3) (safety 0))
                           (type bignum b)
                           (type (unsigned-byte 64) ,@lvars))
                  (values (coerce b 'double-float)
                          (coerce b 'single-float)
                          (logior ,@lvars 0)))))
         (b (- (+ (ash 1 195) (ash 3 130) 17)))
         (args (cons b (loop for i below nlive collect (+ #x1000 i)))))
    (multiple-value-bind (df sf u) (apply fn args)
      (declare (ignore u))
      (unless (and (= df (coerce b 'double-float))
                   (= sf (coerce b 'single-float)))
        (format t "BIGNUM->FLOAT MISMATCH nlive=~D: got ~S ~S~%" nlive df sf)))))

;; Probe bignum-negate-last-two-loop directly:
;; When `l` dies at the VOP and `last1` is unused (e.g. (nth-value 1 ...)) or `last2` gets `l`'s reg!
;; Wait: if `last2` gets `l`'s reg, `(zeroize last2)` sets `l = 0`, then `DEC length` wraps 0 -> 2^32-1 (reads 32 GiB -> segfault)!
;; So inspect DISASSEMBLY first before calling!
(format t "~%=== 4. Inspect disassembly of bignum-negate-last-two-loop for zeroize-clobbers-l ===~%")
(dotimes (nlive 12)
  (let* ((lvars (loop for i below nlive collect (intern (format nil "U~D" i))))
         (fn (compile nil
               `(lambda (a l ,@lvars)
                  (declare (optimize (speed 3) (safety 0))
                           (type bignum a)
                           (type (unsigned-byte 32) l ,@lvars))
                  (multiple-value-bind (last1 last2)
                      (sb-sys:%primitive sb-vm::bignum-negate-last-two-loop a l)
                    (declare (ignore last1))
                    (logxor last2 ,@lvars))))))
         (dis (with-output-to-string (s) (disassemble fn :stream s))))
    (when (= nlive 0)
      (format t "nlive=0:~%~A~%" dis))
    ;; Check if XOR reg, reg clobbers the source of MOV length, l!
    (when (or (search "MOV ECX, ECX" dis) (search "MOV EDX, EDX" dis) (search "MOV R" dis))
      ;; Print compact XOR/MOV lines
      (dolist (line (let ((res nil) (st 0))
                      (loop for p = (position #\Newline dis :start st)
                            do (push (subseq dis st (or p (length dis))) res)
                            while p do (setf st (1+ p)))
                      (nreverse res)))
        (when (or (search "XOR " line) (search "SBB " line) (search "MOV " line))
          (when (= nlive 8)
            (format t "  [nlive=8] ~A~%" line)))))))
