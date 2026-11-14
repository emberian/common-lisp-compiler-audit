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

(defun do-swap-k1 (state)
  (declare (xargs :stobjs state))
  (with-global-stobj
   parent (parent state)
   (with-global-stobj
    kid (parent kid)
    (swap-k1 parent kid))))

(defun do-swap-k2 (state)
  (declare (xargs :stobjs state))
  (with-global-stobj
   parent (parent state)
   (with-global-stobj
    kid (parent kid)
    (swap-k2 parent kid))))

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

;; Step 1: Inside (encapsulate () (local ...)), introduce a local stobj TMP
;; (which pushes a shallow snapshot of *user-stobj-alist* onto *undo-stack*)
;; and swap parent's k1 slot with global kid.
;; When encapsulate finishes pass 1, retract-world1 undoes TMP and restores
;; *user-stobj-alist* so global KID again points to V_A, while PARENT's k1
;; slot was mutated in place and ALSO points to V_A!
(encapsulate ()
  (local (defstobj tmp dummy))
  (local
   (make-event
    (let ((state (do-swap-k1 state)))
      (mv nil '(value-triple :swapped-k1) state)))))

;; Step 2: Now swap parent's k2 slot with global kid (which is V_A!).
;; Now BOTH k1 and k2 inside live PARENT are EQ to the exact same vector V_A!
(make-event
 (let ((state (do-swap-k2 state)))
   (mv nil '(value-triple :swapped-k2) state)))

;; Step 3: Pure :logic guard-verified function & stobj clause-processor.
;; Logically, setting k1 := 1 then k2 := 2 leaves (get-k1 parent) == 1 ALWAYS!
;; At runtime, because k1 and k2 alias V_A, setting k2 := 2 overwrites k1 to 2!
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

(value-triple
 (list :nil-proved-theorem (getpropc 'nil-proved 'theorem nil (w state))
       :ttag (ttag (w state))
       :skip-proofs-seen (global-val 'skip-proofs-seen (w state))
       :redef-seen (global-val 'redef-seen (w state))))
