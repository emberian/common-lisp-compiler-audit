; Modern sibling of NOTE-3-5: put the subversive recursion in MBE branches.
(encapsulate
 ()
 (defun h (x) (declare (ignore x)) t)
 (in-theory (disable (:type-prescription h)))
 (local (in-theory (enable (:type-prescription h))))
 (encapsulate (((f *) => *))
   (local (defun f (x) (cdr x)))
   (defun g (x)
     (mbe :logic (if (consp x) (g (f x)) (h x))
          :exec (if (consp x) (g (f x)) (h x)))))
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
