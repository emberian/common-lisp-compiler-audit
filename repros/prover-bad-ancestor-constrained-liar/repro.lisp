(in-package "ACL2")

; Pure-Kernel Evaluation-Theory / Attachment-Consistency Bug:
; `bad-ancestor1` (apply.lisp:1242, 1262) checks ancestral dependence on
; `*apply$-userfn-callers*` solely via `(body fn nil wrld)`, which is `NIL` for
; constrained functions introduced by `encapsulate`!
;
; Defining `stub` with constraint `(implies (symbolp fn) (equal (stub fn x) (not (apply$ fn (list x)))))`
; and `(defun liar (x) (stub 'liar x))` misclassifies `liar` as G1 in
; `ok-defbadge` (apply.lisp:1773) and `chk-acceptable-defwarrant1` (:1867),
; admitting `apply$-warrant-liar` and `(defattach apply$-warrant-liar true-apply$-warrant)`
; with zero proof obligation (other-events.lisp:31432-31445, 32347-32358).
;
; Consequently, ACL2 proves `(defthm not-warrant-liar (not (apply$-warrant-liar)))`
; while top-level evaluation `(apply$-warrant-liar)` returns `T` — directly
; falsifying `Proposition (Attachment Consistency)` (other-events.lisp:30435)
; and vacuously verifying `:guard nil` in `vacuous-guard-verified`!

(encapsulate
  (((stub * *) => *))
  (local (defun stub (fn x)
           (declare (xargs :guard t))
           (if (symbolp fn)
               (not (apply$ fn (list x)))
             nil)))
  (defthm stub-spec
    (implies (symbolp fn)
             (equal (stub fn x)
                    (not (apply$ fn (list x)))))))

(defun liar (x)
  (declare (xargs :guard t))
  (stub 'liar x))

(defun-sk apply$-warrant-liar ()
  (forall (args)
    (and (equal (badge-userfn 'liar) '(APPLY$-BADGE 1 1 . T))
         (equal (apply$-userfn 'liar args) (liar (car args)))))
  :constrain t)

(in-theory (disable apply$-warrant-liar-definition))

(defthm apply$-liar
  (implies (force (apply$-warrant-liar))
           (and (equal (badge 'liar) '(APPLY$-BADGE 1 1 . T))
                (equal (apply$ 'liar args) (liar (car args)))))
  :hints (("Goal" :use apply$-warrant-liar-necc
           :expand ((:free (x) (hide (badge x))))
           :in-theory (e/d (badge apply$) (apply$-warrant-liar-necc liar)))))

(table badge-table :badge-userfn-structure
  (put-badge-userfn-structure-tuple-in-alist
   (make-badge-userfn-structure-tuple 'liar t '(APPLY$-BADGE 1 1 . T))
   (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table world)))
   'defwarrant)
  :put)

(defattach apply$-warrant-liar true-apply$-warrant)

; Proves (not (apply$-warrant-liar)) in first-order logic while
; (apply$-warrant-liar) evaluates to T via true-apply$-warrant!
(defthm not-warrant-liar
  (not (apply$-warrant-liar))
  :hints (("Goal"
           :use (:instance apply$-liar (args '(nil)))
           :in-theory (e/d (liar stub-spec) (apply$-liar)))))

; Vacuously verifies `:guard nil`!
(defun vacuous-guard-verified ()
  (declare (xargs :guard t))
  (collect$ (lambda$ (x) (declare (xargs :guard nil)) x)
            (cons (if t nil (apply$ 'liar '(nil))) '(nil))))

(assert-event
 (and (equal (apply$-warrant-liar) t)
      (equal (formula 'not-warrant-liar t (w state))
             '(not (apply$-warrant-liar)))
      (eq (symbol-class 'vacuous-guard-verified (w state))
          :common-lisp-compliant)
      (null (ttag (w state)))
      (null (global-val 'ttags-seen (w state)))
      (null (global-val 'skip-proofs-seen (w state)))
      (null (global-val 'redef-seen (w state)))))

(mv-let (erp val state)
  (ld '((cw "@LIAR eval=~x0 thm=~x1 ttag=~x2 skip=~x3 redef=~x4~%"
            (apply$-warrant-liar)
            (consp (formula 'not-warrant-liar t (w state)))
            (ttag (w state))
            (global-val 'skip-proofs-seen (w state))
            (global-val 'redef-seen (w state)))))
  (declare (ignore erp val))
  state)
(quit)
