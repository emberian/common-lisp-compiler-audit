(in-package "ACL2")

; Soundness probe: doppelganger-apply$-userfn (supporters = nil) bypasses
; ACL2 8.7's chk-stobj-attachments / mark-attachment-disallowed check
; (other-events.lisp:21585-21640, 33641-33647), corrupting a live stobj's
; (satisfies ...) field invariant across defattach WITHOUT memoize,
; causing a guard-verified constant-T function to evaluate to NIL and
; proving (defthm nil-proved nil) with :ttag nil and :skip-proofs-seen nil.

(defstub my-p (x) nil)
(defun my-p-int (x) (declare (xargs :guard t)) (integerp x))
(defun my-p-nat (x) (declare (xargs :guard t)) (natp x))

; Warranted wrapper calling attachable my-p
(defun my-call-p (x)
  (declare (xargs :guard t))
  (if (my-p x) t nil))

(make-event
 (let ((badge '(APPLY$-BADGE 1 1 . T)))
   `(encapsulate ()
      ,@(defwarrant-events 'my-call-p '(x) badge)
      (table badge-table
             :badge-userfn-structure
             (put-badge-userfn-structure-tuple-in-alist
              (make-badge-userfn-structure-tuple 'my-call-p T ',badge)
              (cdr (assoc :badge-userfn-structure
                          (table-alist 'badge-table world)))
              'defwarrant)
             :put)
      (defattach ,(warrant-name 'my-call-p) true-apply$-warrant))))

(defun check-via-apply (x)
  (declare (xargs :guard t))
  (equal (apply$ 'my-call-p (list x)) t))

; 1. Attach my-p to integerp BEFORE introducing st!
; chk-stobj-attachments calls canonical-ancestors on check-via-apply, which
; stops at doppelganger-apply$-userfn (supporters = nil) and misses my-p!
(defattach my-p my-p-int)

(defstobj st
  (fld :type (or null (satisfies check-via-apply)) :initially nil))

(defun set-st (x st)
  (declare (xargs :stobjs st :guard t))
  (if (check-via-apply x)
      (update-fld x st)
    st))

; 2. Store -1 into st while my-p is attached to integerp
(make-event
 (let* ((st (set-st -1 st)))
   (mv nil '(value-triple :populated-neg1) state st)))

; 3. Guard-verified function whose logical value is literally T!
(defun always-true (st)
  (declare (xargs :stobjs st :guard t))
  (mbe :logic t
       :exec (or (null (fld st))
                 (check-via-apply (fld st)))))

; 4. Switch attachment of my-p to natp — NOT blocked by attachment-disallowed!
(defattach my-p my-p-nat)

; Observe: (always-true st) is logically T, guard-verified, yet evaluates to NIL!
(make-event
 (let ((v (always-true st)))
   (mv nil `(value-triple '(:always-true-eval ,v)) state)))

; 5. Prove NIL via a verified stobj-taking clause-processor (NO memoize!)
(defevaluator my-ev my-ev-lst ((if x y z)))

(defun my-cp (clause hint st)
  (declare (xargs :stobjs st :guard t)
           (ignore hint))
  (mv nil
      (if (always-true st)
          (list clause)
        nil)
      st))

(defthm my-cp-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (my-ev (conjoin-clauses (clauses-result (my-cp clause hint st))) a))
           (my-ev (disjoin clause) a))
  :rule-classes :clause-processor)

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (my-cp clause nil st)))
  :rule-classes nil)

(value-triple
 (list :theorem (getpropc 'nil-proved 'theorem nil (w state))
       :ttag (ttag (w state))
       :skip-proofs-seen (global-val 'skip-proofs-seen (w state))
       :redef-seen (global-val 'redef-seen (w state))))
