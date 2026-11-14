(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(format t "=== 1. Disassemble basic (values-list (cdr r)) ===~%")
(defun f-basic (&rest r)
  (values-list (cdr r)))
(disassemble #'f-basic)

(declaim (notinline sink))
(defun sink (x) x)

(format t "~%=== 2. Probe %more-arg-values-skip register clobber ===~%")
;; Search across combinations of live fixnum/unsigned variables, calls, and consumers
;; to see if `count` (zeroized first!) aliases `context` or `skip`!
(block found
  (dolist (mode '(:return :mv-call :mv-prog1))
    (dotimes (nprefix 12)
      (dotimes (nlive 14)
        (let* ((pvars (loop for i below nprefix collect (intern (format nil "P~D" i))))
               (lvars (loop for i below nlive collect (intern (format nil "L~D" i))))
               (core (ecase mode
                       (:return `(values-list (cdr r)))
                       (:mv-call `(apply #'list (cdr r)))
                       (:mv-prog1 `(multiple-value-prog1 (values-list (cdr r))
                                     (sink (list ,@lvars))))))
               (form `(lambda (,@pvars &rest r)
                        (declare (optimize (speed 3) (safety 3))
                                 (type fixnum ,@pvars))
                        (let (,@(loop for v in lvars for i from 0
                                      collect `(,v (the fixnum (+ ,(1+ i) ,(if pvars (nth (mod i nprefix) pvars) 0))))))
                          (declare (type fixnum ,@lvars))
                          ,(if (eq mode :mv-prog1)
                               core
                               `(multiple-value-call #'list ,core (values ,@lvars))))))
               (fn (compile nil form))
               (dis (with-output-to-string (s) (disassemble fn :stream s))))
          ;; Look for XOR reg, reg immediately followed by LEA ..., [same-reg - 8]
          (let ((lines (let ((res nil) (start 0))
                         (loop for pos = (position #\Newline dis :start start)
                               do (push (subseq dis start (or pos (length dis))) res)
                               while pos do (setf start (1+ pos)))
                         (nreverse res))))
            (loop for (l1 l2 l3) on lines
                  when (and l1 l2 (search "XOR " l1) (or (search "-8]" l2) (and l3 (search "-8]" l3))))
                  do (let* ((xor-pos (search "XOR " l1))
                            (comma (and xor-pos (position #\, l1 :start xor-pos)))
                            (reg32 (and xor-pos comma (string-trim " " (subseq l1 (+ xor-pos 4) comma))))
                            (reg64 (cond ((and (>= (length reg32) 2) (char= (char reg32 0) #\E))
                                          (concatenate 'string "R" (subseq reg32 1)))
                                         ((and (>= (length reg32) 2) (char= (char reg32 (1- (length reg32))) #\D))
                                          (subseq reg32 0 (1- (length reg32))))
                                         (t reg32)))
                            (target-line (if (search "-8]" l2) l2 l3)))
                       (when (and reg64 (search (concatenate 'string "[" reg64 "-8]") target-line))
                         (format t "HIT! mode=~S nprefix=~D nlive=~D reg=~A~%  ~A~%  ~A~%"
                                 mode nprefix nlive reg64 l1 target-line)
                         (format t "Full disassembly:~%~A~%" dis)
                         ;; Do NOT call without handler or guard, it may segfault! Let's see disasm first!
                         (return-from found t))))))))))

(format t "~%=== 3. Disassemble sb-bignum::add-bignums & negate-bignum in image ===~%")
(disassemble #'sb-bignum:add-bignums)
(disassemble #'sb-bignum::negate-bignum)

(format t "~%=== 4. Probe bignum-add-loop / bignum-negate-last-two-loop directly ===~%")
(dotimes (nlive 12)
  (let* ((lvars (loop for i below nlive collect (intern (format nil "U~D" i))))
         (fn (compile nil
               `(lambda (a b la lb r ,@lvars)
                  (declare (optimize (speed 3) (safety 0))
                           (type bignum a b r)
                           (type (unsigned-byte 32) la lb ,@lvars))
                  (sb-sys:%primitive sb-vm::bignum-add-loop a b la lb r)
                  (logior ,@lvars 0))))
         (dis (with-output-to-string (s) (disassemble fn :stream s))))
    ;; Check if MOV reg1, reg2 ; MOV reg3, reg4 clobbers la or lb before [a + la*8] or [b + lb*8]
    (when (= nlive 0)
      (format t "bignum-add-loop nlive=0:~%~A~%" dis))
    ;; Test actual execution on 2-word + 3-word bignum!
    (let* ((ba (ash 1 130))      ; len 3
           (bb (+ (ash 1 70) 7)) ; len 2
           (res (sb-bignum::%allocate-bignum 4))
           (args (append (list ba bb 3 2 res) (loop for i below nlive collect i))))
      (apply fn args)
      (let ((norm (sb-bignum::%normalize-bignum res 4))
            (want (+ ba bb)))
        (unless (= norm want)
          (format t "MISMATCH in bignum-add-loop nlive=~D: got ~X want ~X~%Disasm:~%~A~%"
                  nlive norm want dis)
          (return))))))

(dotimes (nlive 12)
  (let* ((lvars (loop for i below nlive collect (intern (format nil "U~D" i))))
         (fn (compile nil
               `(lambda (a l ,@lvars)
                  (declare (optimize (speed 3) (safety 0))
                           (type bignum a)
                           (type (unsigned-byte 32) l ,@lvars))
                  (multiple-value-bind (x1 x2)
                      (sb-sys:%primitive sb-vm::bignum-negate-last-two-loop a l)
                    (list x1 x2 (logior ,@lvars 0)))))))
    (when (= nlive 0)
      (disassemble fn))))
