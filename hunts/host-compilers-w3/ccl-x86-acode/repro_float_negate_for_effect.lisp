;;; Reproducer 2:
;;; x862-%double-float-negate / x862-%single-float-negate (x862.lisp:8785-8811)
;;; and arm642-%double-float-negate / arm642-%single-float-negate (arm642.lisp:7273-7297)
;;; unconditionally call (ensuring-node-target (target vreg) ...) when vreg is NIL.
;;; Via acode-rewrite-minus1 (acode-rewrite.lisp:388-402), this crashes COMPILE
;;; with "bad regspec: NIL" even at (optimize (speed 1) (safety 3))!

(in-package :cl-user)

(dolist (opt '((optimize (speed 1) (safety 3))
               (optimize (speed 1) (safety 1))
               (optimize (speed 3) (safety 0))))
  (dolist (case-spec `(("double-float inferred"
                        (lambda () (declare ,opt)
                          (progn (let ((y (if (zerop (random 2)) 1.0d0 2.0d0))) (- y)) :ok)))
                       ("single-float inferred"
                        (lambda () (declare ,opt)
                          (progn (let ((y (if (zerop (random 2)) 1.0f0 2.0f0))) (- y)) :ok)))
                       ("double-float declared"
                        (lambda (x) (declare (type double-float x) ,opt)
                          (progn (- x) :ok)))
                       ("single-float declared"
                        (lambda (x) (declare (type single-float x) ,opt)
                          (progn (- x) :ok)))))
    (destructuring-bind (label lam) case-spec
      (let ((res (handler-case
                     (let ((fn (compile nil lam)))
                       (if (= (length (cadr lam)) 0)
                         (funcall fn)
                         (funcall fn (if (search "double" label) 1.0d0 1.0f0))))
                   (error (e) (format nil "ERR: ~a" e)))))
        (format t "~s ~a => ~a~%" opt label res)))))

#+ccl (ccl:quit 0)
#+sbcl (sb-ext:exit :code 0)
