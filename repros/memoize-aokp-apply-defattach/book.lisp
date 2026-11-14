(in-package "ACL2")

; SCR-S1: (memoize ... :aokp t) + apply$ + defattach + :clause-processor proves NIL
;
; Root cause: doppelganger-apply$-userfn is introduced via partial-encapsulate
; with supporters = nil (other-events.lisp:33641-33647), so
; (ext-ancestors-attachments 'my-caller wrld) (other-events.lisp:33756-33828,
; stored in :ext-anc-attachments at memoize-raw.lisp:3647) misses attachable
; functions (my-h) called inside warranted functions (my-u) invoked via apply$.
; When (defattach my-h my-h-false) changes the attachment of my-h,
; update-memo-entries-for-attachments (memoize-raw.lisp:5207-5286) fails to
; clear my-caller's memo table. A verified :clause-processor evaluated with
; aok = t (prove.lisp:1079-1090) observes (apply$-warrant-my-u) = T, stale
; (my-caller 10) = T, and live (my-h 10) = NIL, returning NIL and proving NIL.

(defstub my-h (x) t)
(defun my-h-true (x) (declare (xargs :guard t) (ignore x)) t)
(defun my-h-false (x) (declare (xargs :guard t) (ignore x)) nil)
(defun my-u (x) (declare (xargs :guard t)) (my-h x))

(make-event
 (let ((badge '(APPLY$-BADGE 1 1 . T)))
   `(encapsulate ()
      ,@(defwarrant-events 'my-u '(x) badge)
      (table badge-table
             :badge-userfn-structure
             (put-badge-userfn-structure-tuple-in-alist
              (make-badge-userfn-structure-tuple 'my-u T ',badge)
              (cdr (assoc :badge-userfn-structure
                          (table-alist 'badge-table world)))
              'defwarrant)
             :put)
      (defattach ,(warrant-name 'my-u) true-apply$-warrant))))

(defun my-caller (x)
  (declare (xargs :guard t))
  (apply$ 'my-u (list x)))

(defevaluator my-ev my-ev-lst ((if x y z)))

(defun my-cp (clause)
  (declare (xargs :guard t))
  (if (or (not (apply$-warrant-my-u))
          (equal (my-caller 10) (my-h 10)))
      (list clause)
    nil))

(defthm my-cp-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (my-ev (conjoin-clauses (my-cp clause)) a))
           (my-ev (disjoin clause) a))
  :rule-classes :clause-processor)

(defattach my-h my-h-true)
(memoize 'my-caller :aokp t)

(make-event
 (let ((v (my-caller 10)))
   (declare (ignore v))
   '(value-triple :warmed)))

(defattach my-h my-h-false)

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (my-cp clause)))
  :rule-classes nil)
