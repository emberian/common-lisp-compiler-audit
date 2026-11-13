; Sibling of NOTE-3-6 encapsulate redundancy: changed default measure function.
(defun zero-m (x) (declare (ignore x)) 0)
(encapsulate
 ()
 (local (encapsulate ()
          (defun f (x) (if (consp x) (f (cdr x)) x))))
 (set-measure-function zero-m)
 (encapsulate ()
   (defun f (x) (if (consp x) (f (cdr x)) x))))
(defthm bad (not (consp x)) :rule-classes nil
  :hints (("Goal" :use (:termination-theorem f))))
(defthm nil-proved nil :rule-classes nil
  :hints (("Goal" :use (:instance bad (x '(1))))))
(quit)
