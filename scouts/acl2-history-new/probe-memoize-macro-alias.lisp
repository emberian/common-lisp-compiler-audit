(in-package "ACL2")
; World-dependent memoize :invoke through macro alias and encapsulate pass 2.
(defun victim (x) (declare (xargs :guard t)) (cons x x))
(defun g (x) (declare (xargs :guard t)) (if (equal x 3) 99 (victim x)))
(defun good (x) (declare (xargs :guard t)) (if (equal x 3) 99 (victim x)))
(defthm good-is-g (equal (good x) (g x)) :rule-classes nil)
(defmacro m (x) (list 'good x))
(encapsulate ()
  (local (defun marker (x) x))
  (table macro-aliases-table 'm
         (if (function-symbolp 'marker world) 'good 'victim))
  (memoize 'm :invoke 'g))
(quit)
