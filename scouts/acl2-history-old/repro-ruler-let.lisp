; NOTE-3-6.1 original LET substitution termination exploit.
(defun foo (x)
  (declare (xargs :ruler-extenders :all))
  (let ((x (cons t x)))
    (if (endp (cdr x))
        x
      (cons t (foo (cdr x))))))
(defthm foo-bad
  nil
  :hints (("Goal" :use ((:instance foo (x '(3))))
           :in-theory (disable foo (foo))))
  :rule-classes nil)
(quit)
