(in-package "ACL2")

(defstobj kid  (fld  :type integer :initially 0))
(defstobj kid2 (fld2 :type integer :initially 0) :congruent-to kid)
(defstobj parent (k1 :type kid) (k2 :type kid))

(defun swap-k1 (parent kid)
  (declare (xargs :stobjs (parent kid)))
  (stobj-let ((kid2 (k1 parent)))
             (kid2 kid)
             (swap-stobjs kid2 kid)
             (mv parent kid)))

(defun swap-k2 (parent kid)
  (declare (xargs :stobjs (parent kid)))
  (stobj-let ((kid2 (k2 parent)))
             (kid2 kid)
             (swap-stobjs kid2 kid)
             (mv parent kid)))

(defun set-k1 (v parent)
  (declare (xargs :stobjs parent :guard (integerp v)))
  (stobj-let ((kid (k1 parent)))
             (kid)
             (update-fld v kid)
             parent))

(defun set-k2 (v parent)
  (declare (xargs :stobjs parent :guard (integerp v)))
  (stobj-let ((kid (k2 parent)))
             (kid)
             (update-fld v kid)
             parent))

(defun get-k1 (parent)
  (declare (xargs :stobjs parent))
  (stobj-let ((kid (k1 parent)))
             (v)
             (fld kid)
             v))

(defevaluator c1-ev c1-ev-lst ((if x y z)))

(defun c1-cp (clause hint parent)
  (declare (xargs :stobjs parent :guard t) (ignore hint))
  (let* ((parent (set-k1 1 parent))
         (parent (set-k2 2 parent))
         (v (get-k1 parent)))
    (if (equal v 1)
        (mv nil (list clause) parent)
      (mv nil nil parent))))

(defthm c1-cp-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (c1-ev (conjoin-clauses (clauses-result (c1-cp clause hint parent))) a))
           (c1-ev (disjoin clause) a))
  :rule-classes :clause-processor)

(defstobj tmp dummy)
(swap-k1 parent kid)
:u
(swap-k2 parent kid)

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (c1-cp clause nil parent)))
  :rule-classes nil)

(value-triple
 (list :nil-proved-theorem (getpropc 'nil-proved 'theorem nil (w state))
       :ttag (ttag (w state))
       :skip-proofs-seen (global-val 'skip-proofs-seen (w state))
       :redef-seen (global-val 'redef-seen (w state))))
