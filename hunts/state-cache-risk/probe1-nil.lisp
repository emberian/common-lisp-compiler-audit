(in-package "ACL2")

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
(value-triple (my-caller 10))
(defattach my-h my-h-false)

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (my-cp clause)))
  :rule-classes nil)
