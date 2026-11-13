; Both hosts prove NIL.  ACL2's maybe-contained-in-character (basis-a.lisp)
; decides that an array of (or character (and integer symbol)) cannot be a
; string, so the single-field stobj is represented by the bare array; both
; hosts see that (and integer symbol) is empty, upgrade the element type to
; CHARACTER and make a string.  The live stobj then fails its own recognizer.
(defstobj s8 (a8 :type (array (or character (and integer symbol)) (2))
                 :initially #\a))
(cw "RESULT (s8p s8) at top level = ~x0~%" (s8p s8))
(defun h ()
  (declare (xargs :guard t))
  (with-local-stobj s8
    (mv-let (v s8)
      (mv (s8p s8) s8)
      v)))
(cw "RESULT (h) = ~x0~%" (h))
(defthm h-is-t (equal (h) t)
  :hints (("Goal" :in-theory (disable (:e h)))))
(defthm h-is-nil (equal (h) nil)
  :hints (("Goal" :in-theory '((:e h)))))
(defthm contradiction nil
  :rule-classes nil
  :hints (("Goal" :use (h-is-t h-is-nil) :in-theory nil)))
(cw "RESULT end of script~%")
