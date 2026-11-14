;;; Reproducer 4:
;;; x862-compare-*-float-registers (x862.lisp:4887-4934) and double/single-float-compare
;;; (x8664-vinsns.lisp:1718-1726) emit COMISD/COMISS + unsigned flag tests (JE/JNE/JB/JBE).
;;; With :invalid nil, unordered NaN sets ZF=PF=CF=1, breaking =, /=, <, <= on x86-64.

(in-package :cl-user)

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
    (format t "dnan vs 1.0d0: ~s (expected (NIL T NIL NIL NIL NIL))~%" (funcall fd dnan 1.0d0))
    (format t "snan vs 1.0f0: ~s (expected (NIL T NIL NIL NIL NIL))~%" (funcall fs snan 1.0f0)))
  (ccl:quit 0))
#-ccl
(format t "CCL-specific FPU test~%")
