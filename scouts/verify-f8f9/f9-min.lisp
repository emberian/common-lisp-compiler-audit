(defstobj s8 (a8 :type (array (or character (and integer symbol)) (2))
                 :initially #\a))
(defun h ()
  (declare (xargs :guard t))
  (with-local-stobj s8
    (mv-let (v s8)
      (mv (s8p s8) s8)
      v)))
(defthm h-is-t (equal (h) t)
  :hints (("Goal" :in-theory (disable (:e h)))))
(defthm h-is-nil (equal (h) nil)
  :hints (("Goal" :in-theory '((:e h)))))
(defthm contradiction nil
  :rule-classes nil
  :hints (("Goal" :use (h-is-t h-is-nil) :in-theory nil)))
