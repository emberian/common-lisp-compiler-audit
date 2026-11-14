;;;; CCL 1.14 P2 backend compiler bugs in low-level float/bit primitives:
;;;;
;;;; [Bug 4a] `arm642-fixnum-ref-double-float` (compiler/ARM64/arm642.lisp:9637-9638;
;;;;          also x862.lisp:11880-11881 and arm2.lisp:9772-9773) passes `(base seg)`
;;;;          REVERSED to `arm642-form` when `vreg` is `nil` (for-effect position):
;;;;            (if (null vreg)
;;;;              (progn
;;;;                (arm642-form base seg nil nil)   ; <-- signature is (seg form vreg xfer)!
;;;;                (arm642-form index seg nil xfer)) ...)
;;;;          Crashes `compile` with `COMPILER-BUG: arm642-form ? NIL`.
;;;;
;;;; [Bug 4b] `arm642-get-bit` (compiler/ARM64/arm642.lisp:8161) and
;;;;          `arm642-set-bit` (compiler/ARM64/arm642.lisp:9131) check
;;;;          `(and byte-index (< byte-index 4096))` WITHOUT `(<= 0 byte-index)`.
;;;;          Negative constant bit offsets (which work cleanly via `notinline`
;;;;          and on x86-64 CCL) crash `compile` on ARM64 because `byte-index = -1`
;;;;          violates the `:U16CONST` constraint in `MEM-REF-C-BIT-FIXNUM` /
;;;;          `MEM-SET-C-BIT-0`.

#-ccl
(progn
  (format t "This reproducer tests CCL-internal low-level primitives (ccl::%fixnum-ref-double-float, ccl::%get-bit).~%")
  #+sbcl (sb-ext:exit))

#+ccl
(progn
  (format t "~&[4a] Compiling (progn (ccl::%fixnum-ref-double-float v 0) :ok):~%")
  (format t "     => ~S~%"
          (handler-case
              (progn
                (compile nil '(lambda (v) (progn (ccl::%fixnum-ref-double-float v 0) :ok)))
                :compiled-ok)
            (error (c)
              (list :compiler-crash (type-of c) (princ-to-string c)))))

  (format t "~%[4b] Compiling (ccl::%get-bit ptr -8) vs notinline execution:~%")
  (ccl:rlet ((buf (:array :unsigned-byte 4)))
    (setf (ccl:%get-unsigned-byte buf 0) #xff
          (ccl:%get-unsigned-byte buf 1) #x00)
    (let ((p1 (ccl:%inc-ptr buf 1))
          (fn-ni (compile nil '(lambda (p)
                                 (declare (notinline ccl::%get-bit))
                                 (ccl::%get-bit p -8)))))
      (format t "     notinline (ccl::%get-bit (ptr+1) -8) => ~S  (expected 1)~%"
              (funcall fn-ni p1))))
  (format t "     inline compile (ccl::%get-bit p -8)  => ~S~%"
          (handler-case
              (progn
                (compile nil '(lambda (p) (ccl::%get-bit p -8)))
                :compiled-ok)
            (error (c)
              (list :compiler-crash (type-of c) (princ-to-string c)))))
  (format t "     inline compile (setf (ccl::%get-bit p -8) 0) => ~S~%"
          (handler-case
              (progn
                (compile nil '(lambda (p) (setf (ccl::%get-bit p -8) 0)))
                :compiled-ok)
            (error (c)
              (list :compiler-crash (type-of c) (princ-to-string c)))))
  (finish-output)
  (ccl:quit))
