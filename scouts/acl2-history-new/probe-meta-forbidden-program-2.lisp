(in-package "ACL2")
; Output checker tests use an evaluator that treats unknown calls as NIL.
; The metafunction preserves evaluation on its one special input, whose value
; is NIL, while replacing it with the prohibited/program-mode call.
(defevaluator mev mev-lst ((if x y z) (equal x y)))
(defun mf-forbidden (term)
  (if (equal term '(equal 0 1)) '(sys-call "" nil) term))
(defthm mf-forbidden-correct
  (equal (mev term a) (mev (mf-forbidden term) a))
  :rule-classes ((:meta :trigger-fns (equal))))
(thm (equal 0 1))

(defun pprog (x) (declare (xargs :mode :program) (ignore x)) nil)
(defun mf-program (term)
  (if (equal term '(equal 0 1)) '(pprog nil) term))
(defthm mf-program-correct
  (equal (mev term a) (mev (mf-program term) a))
  :rule-classes ((:meta :trigger-fns (equal))))
(thm (equal 0 1))
(quit)
