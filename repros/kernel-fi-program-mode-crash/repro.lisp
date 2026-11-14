(in-package "ACL2")

(encapsulate
  (((ef *) => *))
  (local (defun ef (x) x))
  (defthm ef-id (equal (ef x) (ef x)) :rule-classes nil))

(defun prog-id (x)
  (declare (xargs :mode :program))
  x)

(defthm prog-fi-crash
  (equal (car (cons a b)) a)
  :hints (("Goal"
           :use ((:instance (:functional-instance ef-id (ef prog-id)) (x 0)))))
  :rule-classes nil)
