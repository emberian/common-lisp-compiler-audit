; NOTE-3-0-1 original: a local PROGRAM event must not make a nonterminating
; exported definition look admissible.
(encapsulate ()
  (local (program))
  (defun foo ()
    (declare (xargs :measure 17))
    (+ 1 (foo))))
(thm nil
     :hints (("Goal" :in-theory (disable foo (foo)) :use foo)))
(quit)
