;;;; SBCL 2.6.10 (x86-64) — Pure ANSI CL Segfault at (SAFETY 3) in `%MORE-ARG-VALUES-SKIP`
;;;;
;;;; Bug: `src/compiler/x86-64/values.lisp:162-190` (`%more-arg-values-skip`)
;;;;   `(:results (start :scs (any-reg) :from :eval) (count :scs (any-reg) :from :eval))`
;;;;   `count` has `:from :eval`, so it does NOT conflict with `:args` `context` (`dies = (:argument 0)`)
;;;;   or `skip` (`dies = (:argument 1)`). Yet line 175 executes `(zeroize count)` (`XOR ECX, ECX`)
;;;;   BEFORE line 178 `(inst lea src (ea (- (* (tn-value skip) n-word-bytes)) context))` (`LEA R11, [RCX-8]`)!
;;;;   When `context` and `count` are both allocated to `RCX`, `XOR ECX, ECX` zeroes `context`,
;;;;   setting `src = -8` (`0xFFFFFFFFFFFFFFF8`), and the copy loop dereferences `0xFFFFFFFFFFFFFFF8`
;;;;   and crashes SBCL with `CORRUPTION WARNING: Memory fault at 0xfffffffffffffff8` — even in
;;;;   100% pure ANSI Common Lisp at `(optimize (speed 3) (safety 3))`!

(declaim (muffle-conditions sb-ext:compiler-note style-warning))

(declaim (notinline sink))
(defun sink (x) x)

(defun safe-baseline (p0 p1 p2 p3 p4 p5 p6 p7 p8 p9 &rest r)
  (declare (optimize (speed 0) (safety 3) (debug 3))
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
      (sink (list l0 l1 l2 l3 l4 l5)))))

(defun buggy-speed3-safety3 (p0 p1 p2 p3 p4 p5 p6 p7 p8 p9 &rest r)
  (declare (optimize (speed 3) (safety 3))
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
      (sink (list l0 l1 l2 l3 l4 l5)))))

(format t "SBCL ~A (~A)~%" (lisp-implementation-version) (machine-type))
(format t "Safe ((speed 0) (safety 3)) => ~S~%"
        (multiple-value-list
         (safe-baseline 0 1 2 3 4 5 6 7 8 9 :drop :keep-a :keep-b)))
(format t "~%Disassembly of BUGGY-SPEED3-SAFETY3 (note XOR ECX, ECX followed by LEA ..., [RCX-8]):~%")
(disassemble #'buggy-speed3-safety3)
(finish-output)

(format t "~%Invoking BUGGY-SPEED3-SAFETY3...~%")
(finish-output)
(format t "Fast ((speed 3) (safety 3)) => ~S~%"
        (multiple-value-list
         (buggy-speed3-safety3 0 1 2 3 4 5 6 7 8 9 :drop :keep-a :keep-b)))
