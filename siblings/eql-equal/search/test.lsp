; Logically (search x y) is (search-fn x y nil 'equal 0 0 nil nil nil nil): the
; ACL2 macro supplies :test 'equal by default (axioms.lisp, #+acl2-loop-only
; defmacro search).  In raw Lisp that macro does not exist, so the same form is
; COMMON-LISP:SEARCH with its own default :test, EQL.  The guard
; (search-fn-guard) admits any two true lists, so a guard-verified caller runs
; the EQL version on arguments where EQL and EQUAL differ.
; Inputs are built at call time: (list 1) and (coerce (list #\a) 'string) are
; fresh objects, EQUAL to but not EQ to their twins.
(defun srch-gv (x y)
  (declare (xargs :guard (and (true-listp x) (true-listp y))))
  (search x y))
(defun srch-nogv (x y)
  (declare (xargs :guard (and (true-listp x) (true-listp y)) :verify-guards nil))
  (search x y))
(defun srch-fe-gv (x y)
  (declare (xargs :guard (and (true-listp x) (true-listp y))))
  (search x y :from-end t))
(defun srch-fe-nogv (x y)
  (declare (xargs :guard (and (true-listp x) (true-listp y)) :verify-guards nil))
  (search x y :from-end t))
; Control: the same call with the default written out agrees.
(defun srch-eq-gv (x y)
  (declare (xargs :guard (and (true-listp x) (true-listp y))))
  (search x y :test 'equal))
(defun srch-eq-nogv (x y)
  (declare (xargs :guard (and (true-listp x) (true-listp y)) :verify-guards nil))
  (search x y :test 'equal))
(cw "RESULT cons guard-verified: ~x0~%" (srch-gv (list (list 1)) (list 0 (list 1))))
(cw "RESULT cons not guard-verified: ~x0~%" (srch-nogv (list (list 1)) (list 0 (list 1))))
(cw "RESULT string guard-verified: ~x0~%"
    (srch-gv (list (coerce (list #\a) 'string)) (list (coerce (list #\a) 'string))))
(cw "RESULT string not guard-verified: ~x0~%"
    (srch-nogv (list (coerce (list #\a) 'string)) (list (coerce (list #\a) 'string))))
(cw "RESULT from-end guard-verified: ~x0~%" (srch-fe-gv (list (list 1)) (list 0 (list 1))))
(cw "RESULT from-end not guard-verified: ~x0~%" (srch-fe-nogv (list (list 1)) (list 0 (list 1))))
(cw "RESULT control :test 'equal guard-verified: ~x0~%" (srch-eq-gv (list (list 1)) (list 0 (list 1))))
(cw "RESULT control :test 'equal not guard-verified: ~x0~%" (srch-eq-nogv (list (list 1)) (list 0 (list 1))))
; The logical value is a theorem: the guard-verified function is proved to
; return 1 on the very call that evaluates to NIL above.
(defthm srch-gv-value (equal (srch-gv (list (list 1)) (list 0 (list 1))) 1))
(cw "RESULT theorem srch-gv-value admitted: ~x0~%"
    (and (getpropc 'srch-gv-value 'theorem nil (w state)) t))
; Consequence in the prover: ground evaluation runs the raw code, so the
; evaluated value is also a theorem, and the two together prove NIL.
(defthm srch-gv-evaluated (equal (srch-gv '((1)) '(0 (1))) nil) :rule-classes nil)
(defthm srch-gv-logical (equal (srch-gv '((1)) '(0 (1))) 1) :rule-classes nil
  :hints (("Goal" :in-theory (disable (:e srch-gv) (:e search-fn)))))
(defthm srch-nil nil :rule-classes nil
  :hints (("Goal" :use (srch-gv-evaluated srch-gv-logical))))
(cw "RESULT theorems admitted: evaluated ~x0 logical ~x1 nil ~x2~%"
    (and (getpropc 'srch-gv-evaluated 'theorem nil (w state)) t)
    (and (getpropc 'srch-gv-logical 'theorem nil (w state)) t)
    (and (getpropc 'srch-nil 'theorem nil (w state)) t))
