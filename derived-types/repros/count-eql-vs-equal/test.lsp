; Logically (count item lst) is count-fn, which compares list elements with EQUAL
; (count-listp in axioms.lisp), so (count (list 1) (list (list 1))) is 1.
(defun cnt-gv (item lst)
  (declare (xargs :guard (true-listp lst)))
  (count item lst))
(defun cnt-nogv (item lst)
  (declare (xargs :guard (true-listp lst) :verify-guards nil))
  (count item lst))
(cw "RESULT guard-verified: ~x0~%" (cnt-gv (list 1) (list (list 1))))
(cw "RESULT not guard-verified: ~x0~%" (cnt-nogv (list 1) (list (list 1))))
