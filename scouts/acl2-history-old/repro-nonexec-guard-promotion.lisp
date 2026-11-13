; Modern sibling of NOTE-2-8 guard-status redundancy via :NON-EXECUTABLE.
(encapsulate
 ()
 (local (defun f (x)
          (declare (xargs :non-executable t :guard t :verify-guards nil))
          (prog2$ (throw-nonexec-error 'f (list x)) (car x))))
 (defun f (x)
   (declare (xargs :non-executable t :guard t :verify-guards t))
   (prog2$ (throw-nonexec-error 'f (list x)) (car x))))
(defthm bad
  (or (consp x) (equal x nil))
  :rule-classes nil
  :hints (("Goal" :use (:guard-theorem f))))
(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal" :use (:instance bad (x 0)))))
(quit)
