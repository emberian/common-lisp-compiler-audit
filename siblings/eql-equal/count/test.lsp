; (count item lst) is the macro count-fn only under #+acl2-loop-only (axioms.lisp);
; count-fn -> count-listp compares with EQUAL.  In raw Lisp the macro does not
; exist, so compiled guard-verified code calls CL:COUNT, which compares with EQL.
; count-fn's guard (true-listp sequence) does not constrain item to be eqlablep,
; so a guard-verified call runs on an item that is EQUAL but not EQL to a list
; element.  Inputs built at call time: (list 1) / (coerce (list #\a) 'string).
(defun cnt-gv (item lst)
  (declare (xargs :guard (true-listp lst)))
  (count item lst))
(defun cnt-nogv (item lst)
  (declare (xargs :guard (true-listp lst) :verify-guards nil))
  (count item lst))
(cw "RESULT cons guard-verified: ~x0~%" (cnt-gv (list 1) (list (list 1))))
(cw "RESULT cons not guard-verified: ~x0~%" (cnt-nogv (list 1) (list (list 1))))
(cw "RESULT string guard-verified: ~x0~%"
    (cnt-gv (coerce (list #\a) 'string) (list (coerce (list #\a) 'string))))
(cw "RESULT string not guard-verified: ~x0~%"
    (cnt-nogv (coerce (list #\a) 'string) (list (coerce (list #\a) 'string))))
; The contradiction is reachable in the logic: ground eval runs the raw code (0),
; while the definition yields 1 with the executable counterpart disabled.
(defthm cnt-gv-evaluated (equal (cnt-gv '(1) '((1))) 0) :rule-classes nil)
(defthm cnt-gv-logical (equal (cnt-gv '(1) '((1))) 1) :rule-classes nil
  :hints (("Goal" :in-theory (disable (:e cnt-gv) (:e count-fn)))))
(defthm cnt-nil nil :rule-classes nil
  :hints (("Goal" :use (cnt-gv-evaluated cnt-gv-logical))))
(cw "RESULT theorems admitted: evaluated ~x0 logical ~x1 nil ~x2~%"
    (and (getpropc 'cnt-gv-evaluated 'theorem nil (w state)) t)
    (and (getpropc 'cnt-gv-logical 'theorem nil (w state)) t)
    (and (getpropc 'cnt-nil 'theorem nil (w state)) t))
