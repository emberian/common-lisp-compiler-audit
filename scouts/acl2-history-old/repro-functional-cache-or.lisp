; NOTE-2-7 cache variant through the newer :OR hint control flow.
(encapsulate (((g1) => *))
  (local (defun g1 () 0))
  (defthm 0=g1 (equal 0 (g1)) :rule-classes nil))
(defun g1-lst (lst)
  (cond ((endp lst) (g1)) (t (g1-lst (cdr lst)))))
(defthm g1-lst=g1 (equal (g1-lst lst) (g1)))
(encapsulate (((f1) => *)) (local (defun f1 () 1)))
(defun f1-lst (lst)
  (cond ((endp lst) (f1)) (t (f1-lst (cdr lst)))))
(defthm f1-lst=f1
  (equal (f1-lst lst) (f1))
  :hints (("Goal" :or
                  ((:use (:functional-instance g1-lst=g1
                           (g1 f1) (g1-lst f1-lst)))
                   (:induct t)))))
(defthm 0=f1
  (equal 0 (f1)) :rule-classes nil
  :hints (("Goal" :use (:functional-instance 0=g1 (g1 f1)))))
(defthm 0=1
  (equal 0 1) :rule-classes nil
  :hints (("Goal" :use (:functional-instance 0=f1 (f1 (lambda () 1))))))
(quit)
