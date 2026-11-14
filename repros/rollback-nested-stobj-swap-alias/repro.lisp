;; WRB-S1: Shallow *user-stobj-alist* undo snapshot + trans-eval functional
;; spine copy + nested swap-stobjs aliases two sibling child stobj fields
;; (parent.k1 and parent.k2 become EQ), violating Stobj Evaluation Invariant
;; (C1) and proving (defthm nil-proved nil) with :ttags nil!
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

;; Pass 1 of encapsulate pushes *user-stobj-alist* via (local (defstobj tmp dummy)),
;; then swaps live KID (#<V0>) into parent.k1 via trans-eval (mutating parent[0]
;; in-place to #<V0> while put-assoc-eq-alist copies the alist spine for KID).
;; Pass 2 rolls back (local (defstobj tmp dummy)), restoring *user-stobj-alist*
;; so KID points to #<V0> again while parent[0] STILL holds #<V0>!
(encapsulate ()
  (local (defstobj tmp dummy))
  (local
   (make-event
    (mv-let (erp val state)
      (trans-eval '(swap-k1 parent kid) 'swap1 state t)
      (declare (ignore erp val))
      (value '(value-triple :swapped-k1))))))

;; Swapping KID (#<V0>) into parent.k2 now makes parent[0] and parent[1] EQ!
(make-event
 (mv-let (erp val state)
   (trans-eval '(swap-k2 parent kid) 'swap2 state t)
   (declare (ignore erp val))
   (value '(value-triple :swapped-k2))))

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

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (c1-cp clause nil parent)))
  :rule-classes nil)

(make-event
 (let ((w (w state)))
   (prog2$
    (cw "@WRB-S1 ~x0 def=~x1 thm=~x2 ttag=~x3 seen=~x4 skip=~x5 redef=~x6~%"
        (@ host-lisp)
        (not (eq (getpropc 'nil-proved 'theorem :none w) :none))
        (getpropc 'nil-proved 'theorem :none w)
        (ttag w)
        (global-val 'ttags-seen w)
        (global-val 'skip-proofs-seen w)
        (global-val 'redef-seen w))
    (value '(value-triple :done)))))
