(in-package "ACL2")

(defstobj parent (tbl :type (stobj-table)))

(defun parent-keys (parent)
  (declare (xargs :stobjs parent))
  (tbl-keys parent))

(memoize 'parent-keys)

(encapsulate ()
  (local (defstobj kid fld))
  (local
   (defun put-kid (val parent)
     (declare (xargs :stobjs parent))
     (stobj-let ((kid (tbl-get 'kid parent (create-kid))))
                (kid)
                (update-fld val kid)
                parent)))
  (local
   (make-event
    (mv-let (erp val state)
      (trans-eval
       '(let ((parent (put-kid 42 parent)))
          (mv (parent-keys parent) parent))
       'populate-and-memoize
       state
       t)
      (declare (ignore erp val))
      (value '(value-triple :populated))))))

(defevaluator st-tbl-ev st-tbl-ev-lst ((if x y z)))

(defun st-tbl-cp (clause hint parent)
  (declare (xargs :stobjs parent :guard t) (ignore hint))
  (if (equal (parent-keys parent) (tbl-keys parent))
      (mv nil (list clause) parent)
    (mv nil nil parent)))

(defthm st-tbl-cp-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (st-tbl-ev (conjoin-clauses
                            (clauses-result (st-tbl-cp clause hint parent)))
                           a))
           (st-tbl-ev (disjoin clause) a))
  :rule-classes :clause-processor)

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (st-tbl-cp clause nil parent)))
  :rule-classes nil)
