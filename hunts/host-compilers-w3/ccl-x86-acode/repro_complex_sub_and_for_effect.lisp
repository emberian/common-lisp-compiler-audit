;;; Reproducer 1a & 1b:
;;; 1a: x862-%complex-single-float--2 (compiler/X86/x862.lisp:9607) omits `target`
;;;     from (with-fp-target (r1) (r2 :complex-single-float) ...), clobbering `y`
;;;     on x86-64 (subps fp1, fp1 => #C(0.0 0.0)).
;;; 1b: x862-%complex-{double,single}-float{+-2,--2,*-2} (x862.lisp:9540-9628)
;;;     and arm642-%complex-* (arm642.lisp:7915-8003) crash COMPILE with
;;;     "bad regspec: NIL" when compiled for effect.

(in-package :cl-user)

(defun test-1a ()
  (let* ((f (compile nil '(lambda (a b c d)
                            (declare (type (complex single-float) a b c d))
                            (- (+ a b) (- c d)))))
         (got (funcall f #c(1f0 2f0) #c(3f0 4f0) #c(5f0 6f0) #c(7f0 8f0)))
         (expected #c(6.0f0 8.0f0)))
    (format t "1a default-opt: got=~s expected=~s pass=~s~%" got expected (equal got expected))))

(defun test-1b ()
  (dolist (ty '((complex single-float) (complex double-float)))
    (dolist (op '(+ - *))
      (let* ((form `(lambda (a b)
                      (declare (type ,ty a b))
                      (progn (,op a b) :ok)))
             (res (handler-case (funcall (compile nil form)
                                         (if (equal ty '(complex single-float)) #c(1f0 2f0) #c(1d0 2d0))
                                         (if (equal ty '(complex single-float)) #c(3f0 4f0) #c(3d0 4d0)))
                    (error (e) (format nil "ERR: ~a" e)))))
        (format t "1b ~s ~s: ~a~%" ty op res)))))

(test-1a)
(test-1b)
#+ccl (ccl:quit 0)
#+sbcl (sb-ext:exit :code 0)
