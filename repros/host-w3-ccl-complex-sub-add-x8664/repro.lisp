;;;; Repro: CCL 1.14 x86-64 complex single-float target aliasing in x862-%complex-single-float--2
;;;; and x862-%complex-single-float+-2 (compiler/X86/x862.lisp:9591-9592, 9606-9607).
;;;; Zero-UB at default optimize policy. Both omit `target` from `(with-fp-target (r1 target) ...)`.

(in-package :cl-user)

(defun test-complex-sub ()
  (let* ((f (compile nil '(lambda (a b c d)
                            (declare (type (complex single-float) a b c d))
                            (- (+ a b) (- c d)))))
         (got (funcall f #c(1f0 2f0) #c(3f0 4f0) #c(5f0 6f0) #c(7f0 8f0)))
         (expected #c(6.0f0 8.0f0)))
    (format t "sub default-opt: got=~s expected=~s pass=~s~%" got expected (equal got expected))))

(defun test-complex-add ()
  (let* ((f (compile nil '(lambda (a b c d)
                            (declare (type (complex single-float) a b c d))
                            (+ (+ a b) (- c d)))))
         (got (funcall f #c(1f0 2f0) #c(3f0 4f0) #c(5f0 6f0) #c(7f0 8f0)))
         (expected #c(2.0f0 4.0f0)))
    (format t "add default-opt: got=~s expected=~s pass=~s~%" got expected (equal got expected))))

(format t "Impl: ~a ~a (~a)~%" (lisp-implementation-type) (lisp-implementation-version) (machine-type))
(test-complex-sub)
(test-complex-add)
#+ccl (ccl:quit 0)
#+sbcl (sb-ext:exit :code 0)
