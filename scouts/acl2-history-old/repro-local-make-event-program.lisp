; Reverse wrapping from repro-make-event-local-program.lisp.
(encapsulate ()
  (local (make-event '(program)))
  (defun foo ()
    (declare (xargs :measure 17))
    (+ 1 (foo))))
(thm nil
     :hints (("Goal" :in-theory (disable foo (foo)) :use foo)))
(quit)
