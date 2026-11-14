;; Verifies false ACL2 theorems are NIL in ACL2 while SMT-interpret accepts Z3's "proved" output
;; Source: books/projects/smtlink/z3_interface/ACL2_to_Z3.py:84-118 & trusted/run.lisp:48
(in-package "ACL2")

;; Exact ACL2 evaluation of all 8 conjectures -> all are NIL
(defthm acl2-truth-all-false
  (and (not (equal 'nil '0))
       (not (equal 't '1))
       (not (< 'nil 't))
       (not (< '0 't))
       (not (equal (+ 't '-1) '0))
       (not (equal (- 't) '-1))
       (not (equal (/ 't) '1))
       (not (equal (* 'nil 'nil) 'nil)))
  :rule-classes nil)

;; Exact SMT-interpret decision predicate from books/projects/smtlink/trusted/run.lisp:48
(defun smt-interpret-car-proved (lines)
  (declare (xargs :guard (string-listp lines)))
  (cond ((atom lines) nil)
        ((equal (car lines) "proved") t)
        (t nil)))

(value-triple
 (cw "~%@CHECK smt-interpret('(\"proved\"))=~x0~%"
     (smt-interpret-car-proved '("proved"))))
