; Modern NOTE-2.3/3-5 sibling: hide subversive recursion in a FOR LOOP$.
; CAR(COLLECT ...) transports the recursive result without booleanizing it.
(encapsulate
 ()
 (defun h (x) (declare (ignore x)) t)
 (in-theory (disable (:type-prescription h)))
 (local (in-theory (enable (:type-prescription h))))
 (encapsulate (((f *) => *))
   (local (defun f (x) (cdr x)))
   (defun$ g (x)
     (declare (xargs :loop$-recursion t :measure (acl2-count x)))
     (if (consp x)
         (car (loop$ for e in (list (f x)) collect (g e)))
       (h x))))
 (defthm atom-g (atom (g x)) :rule-classes nil))
(defthm contradiction nil
  :hints (("Goal" :use ((:instance
                         (:functional-instance
                          atom-g
                          (f identity)
                          (g (lambda (x) (if (consp x) x t))))
                         (x '(a b))))))
  :rule-classes nil)
(quit)
