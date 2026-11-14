;;;; Repro: CCL 1.14 x86-64 & ARM64 "bad regspec: NIL" compiler crash on for-effect
;;;; float negation and complex-float binary operations (including at (safety 3)).
;;;; Root causes:
;;;;   1. x862-%double/single-float-negate (x862.lisp:8785-8811) & arm642-%double/single-float-negate
;;;;      (arm642.lisp:7273-7297) call (ensuring-node-target (target vreg) ...) even when vreg=NIL.
;;;;   2. x862-%complex-{double,single}-float{+-2,--2,*-2} (x862.lisp:9540-9628) &
;;;;      arm642-%complex-{double,single}-float{+-2,--2,*-2} (arm642.lisp:7915-8003) do the same.

(in-package :cl-user)

(format t "Impl: ~a ~a (~a)~%" (lisp-implementation-type) (lisp-implementation-version) (machine-type))

(dolist (case-spec '(("safety-3 inferred double-float negate"
                      (lambda () (declare (optimize (speed 1) (safety 3)))
                        (progn (let ((y (if (zerop (random 2)) 1.0d0 2.0d0))) (- y)) :ok))
                      nil)
                     ("safety-3 inferred single-float negate"
                      (lambda () (declare (optimize (speed 1) (safety 3)))
                        (progn (let ((y (if (zerop (random 2)) 1.0f0 2.0f0))) (- y)) :ok))
                      nil)
                     ("safety-1 declared double-float negate"
                      (lambda (x) (declare (type double-float x) (optimize (speed 1) (safety 1)))
                        (progn (- x) :ok))
                      (1.0d0))
                     ("default complex double-float +"
                      (lambda (a b) (declare (type (complex double-float) a b))
                        (progn (+ a b) :ok))
                      (#c(1.0d0 2.0d0) #c(3.0d0 4.0d0)))
                     ("default complex single-float -"
                      (lambda (a b) (declare (type (complex single-float) a b))
                        (progn (- a b) :ok))
                      (#c(1.0f0 2.0f0) #c(3.0f0 4.0f0)))
                     ("default complex double-float *"
                      (lambda (a b) (declare (type (complex double-float) a b))
                        (progn (* a b) :ok))
                      (#c(1.0d0 2.0d0) #c(3.0d0 4.0d0)))))
  (destructuring-bind (label lam args) case-spec
    (let ((res (handler-case
                   (apply (compile nil lam) args)
                 (error (e) (format nil "ERR: ~a" e)))))
      (format t "  ~a => ~a~%" label res))))

#+ccl (ccl:quit 0)
#+sbcl (sb-ext:exit :code 0)
