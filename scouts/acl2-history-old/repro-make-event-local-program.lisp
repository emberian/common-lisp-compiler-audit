; Modern sibling of NOTE-3-0-1: hide LOCAL(PROGRAM) behind MAKE-EVENT.
(encapsulate ()
  (make-event '(local (program)))
  (defun foo ()
    (declare (xargs :measure 17))
    (+ 1 (foo))))
(thm nil
     :hints (("Goal" :in-theory (disable foo (foo)) :use foo)))
(quit)
