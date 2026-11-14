;;;; Repro: CCL 1.14 x86-64 COMISD/COMISS unordered NaN comparison miscompilation
;;;; (compiler/X86/x862.lisp:4887-4934, x8664-vinsns.lisp:1718-1726).
;;;; Extends Z3-3 (ARM64) to x86-64: with :invalid nil, COMISD/COMISS sets ZF=PF=CF=1,
;;;; so unsigned flag tests make NaN compare =, <, <=, and NOT /=!

(in-package :cl-user)

(format t "Impl: ~a ~a (~a)~%" (lisp-implementation-type) (lisp-implementation-version) (machine-type))

#+ccl
(progn
  (ccl:set-fpu-mode :invalid nil)
  (let* ((dnan (read-from-string "1d+-0"))
         (snan (read-from-string "1s+-0"))
         (fd (compile nil '(lambda (x y)
                             (declare (type double-float x y))
                             (list (= x y) (/= x y) (< x y) (<= x y) (> x y) (>= x y)))))
         (fs (compile nil '(lambda (x y)
                             (declare (type single-float x y))
                             (list (= x y) (/= x y) (< x y) (<= x y) (> x y) (>= x y))))))
    (format t "  dnan vs 1.0d0: ~s (expected (NIL T NIL NIL NIL NIL))~%" (funcall fd dnan 1.0d0))
    (format t "  snan vs 1.0f0: ~s (expected (NIL T NIL NIL NIL NIL))~%" (funcall fs snan 1.0f0)))
  (ccl:quit 0))

#-ccl
(format t "CCL-specific FPU test~%")
