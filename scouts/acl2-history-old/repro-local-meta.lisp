; NOTE-2-9-4 original local-defevaluator META rule exploit.
(defun meta-foo (term)
  (if (and (consp term) (equal (car term) 'foo)) *nil* term))
(encapsulate
 (((evx * *) => *) ((evx-list * *) => *) ((foo *) => *))
 (local (defun foo (x) (declare (ignore x)) nil))
 (local (defevaluator evx evx-list ((foo x))))
 (defthm meta-foo-rule
   (equal (evx term a) (evx (meta-foo term) a))
   :rule-classes ((:meta :trigger-fns (foo)))))
(defun goo (x) (declare (ignore x)) t)
(defthm qed
  (not (goo x))
  :hints (("Goal" :use (:functional-instance (:theorem (not (foo x)))
                        (foo goo))
           :in-theory (disable goo (:type-prescription goo) (goo))))
  :rule-classes nil)
(defthm contradiction nil
  :hints (("Goal" :use qed :in-theory (enable goo)))
  :rule-classes nil)
(quit)
