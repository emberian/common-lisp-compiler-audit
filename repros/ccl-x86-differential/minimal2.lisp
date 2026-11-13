;;; Characterize the extra-values leak: which value-restricting wrappers leak, and
;;; which optimize policies trigger it. A conforming result is 1 value in every case
;;; below (each wrapper restricts to the primary value).
(defmacro mk (name policy expr) `(defun ,name (x) (declare (integer x) (optimize ,@policy)) ,expr))

;; wrapper sweep, all (speed 3)(safety 0)
(mk w-identity ((speed 3)(safety 0)) (identity (truncate x 10)))
(mk w-values   ((speed 3)(safety 0)) (values (truncate x 10)))           ; (values e) => exactly 1 value
(mk w-prog1    ((speed 3)(safety 0)) (prog1 (truncate x 10)))            ; prog1 => primary only
(mk w-let      ((speed 3)(safety 0)) (let ((y (truncate x 10))) y))      ; bind => primary only
(mk w-logior   ((speed 3)(safety 0)) (logior 0 (round x 10)))
(mk w-list1    ((speed 3)(safety 0)) (car (list (truncate x 10))))
(mk w-if       ((speed 3)(safety 0)) (if (plusp x) (identity (truncate x 10)) 0))
(mk w-funcall  ((speed 3)(safety 0)) (funcall #'identity (truncate x 10)))

;; policy sweep on the identity wrapper
(mk p-s3a0 ((speed 3)(safety 0)) (identity (truncate x 10)))
(mk p-s3a1 ((speed 3)(safety 1)) (identity (truncate x 10)))
(mk p-s3a2 ((speed 3)(safety 2)) (identity (truncate x 10)))
(mk p-s3a3 ((speed 3)(safety 3)) (identity (truncate x 10)))
(mk p-s2a0 ((speed 2)(safety 0)) (identity (truncate x 10)))
(mk p-s1a0 ((speed 1)(safety 0)) (identity (truncate x 10)))
(mk p-s0a0 ((speed 0)(safety 0)) (identity (truncate x 10)))
(mk p-def  ()                    (identity (truncate x 10)))             ; default policy

(defun nv (fn) (length (multiple-value-list (funcall fn 37))))
(format t "~%-- wrapper sweep (speed 3 safety 0); correct = 1 value --~%")
(dolist (p (list (cons "identity" #'w-identity) (cons "values  " #'w-values)
                 (cons "prog1   " #'w-prog1) (cons "let-bind" #'w-let)
                 (cons "logior 0" #'w-logior) (cons "car list" #'w-list1)
                 (cons "if-branch" #'w-if) (cons "funcall id" #'w-funcall)))
  (format t "  ~a : nvalues=~a~%" (car p) (nv (cdr p))))
(format t "~%-- policy sweep on (identity (truncate x 10)); correct = 1 value --~%")
(dolist (p (list (cons "speed3 safety0" #'p-s3a0) (cons "speed3 safety1" #'p-s3a1)
                 (cons "speed3 safety2" #'p-s3a2) (cons "speed3 safety3" #'p-s3a3)
                 (cons "speed2 safety0" #'p-s2a0) (cons "speed1 safety0" #'p-s1a0)
                 (cons "speed0 safety0" #'p-s0a0) (cons "default       " #'p-def)))
  (format t "  ~a : nvalues=~a~%" (car p) (nv (cdr p))))
(finish-output)
#+ccl (ccl:quit 0)
#+sbcl (sb-ext:exit :code 0)
