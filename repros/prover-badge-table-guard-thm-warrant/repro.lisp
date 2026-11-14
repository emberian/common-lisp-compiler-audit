(in-package "ACL2")

; Pure-Kernel Soundness Bug:
; `badge-table-guard1` (apply.lisp:1966-1972) permits `((null new-lst) t)`
; without checking `(global-val 'boot-strap-flg wrld)`, allowing any `:ttag nil`
; session or book to execute `(table badge-table :badge-userfn-structure nil :put)`
; and abandon all warrants while previously guard-verified functions remain
; `:common-lisp-compliant` (violating both `:guard-theorem` soundness at
; history-management.lisp:13413, 14810 and `add-trip`'s warrant-monotonicity
; invariant at other-events.lisp:33628-33633).
;
; Re-adding `g`'s badge with `warrantp = nil` and invoking `(:guard-theorem fn)`
; drops `(apply$-warrant-g)` even when `g` is inside a quoted lambda object,
; proving `(defthm nil-proved nil :rule-classes nil)` via `:functional-instance`
; with zero `encapsulate` and zero books.

(defun g (x)
  (declare (ignore x) (xargs :guard t))
  0)

(defun-sk apply$-warrant-g ()
  (forall (args)
    (and (equal (badge-userfn 'g) '(APPLY$-BADGE 1 1 . T))
         (equal (apply$-userfn 'g args) (g (car args)))))
  :constrain t)

(in-theory (disable apply$-warrant-g-definition))

(defthm apply$-g
  (implies (force (apply$-warrant-g))
           (and (equal (badge 'g) '(APPLY$-BADGE 1 1 . T))
                (equal (apply$ 'g args) (g (car args)))))
  :hints (("Goal" :use apply$-warrant-g-necc
           :expand ((:free (x) (hide (badge x))))
           :in-theory (e/d (badge apply$) (apply$-warrant-g-necc g)))))

(table badge-table :badge-userfn-structure
  (put-badge-userfn-structure-tuple-in-alist
   (make-badge-userfn-structure-tuple 'g t '(APPLY$-BADGE 1 1 . T))
   (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table world)))
   'defwarrant)
  :put)

(defun fn ()
  (declare (xargs :guard t
                  :guard-hints (("Goal" :in-theory (enable apply$ apply$-lambda ev$)))))
  (sum$ '(lambda (x) (g x)) '(nil)))

; Abandon all userfn badges/warrants via apply.lisp:1967, then restore g's
; badge with warrantp = NIL:
(table badge-table :badge-userfn-structure nil :put)

(table badge-table :badge-userfn-structure
  (list (make-badge-userfn-structure-tuple 'g nil '(APPLY$-BADGE 1 1 . T)))
  :put)

(defthm step1
  (implies (equal (badge-userfn 'g) '(APPLY$-BADGE 1 1 . T))
           (acl2-numberp (apply$-userfn 'g '(nil))))
  :rule-classes nil
  :hints (("Goal"
           :use (:instance (:guard-theorem fn) (newv nil))
           :expand ((:free (x a) (ev$ x a))
                    (:free (x a) (ev$-list x a)))
           :in-theory (e/d (apply$ apply$-lambda badge)
                           (apply$-g
                            (:executable-counterpart apply$)
                            (:executable-counterpart apply$-lambda)
                            (:executable-counterpart ev$))))))

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal"
           :use (:functional-instance
                 step1
                 (badge-userfn (lambda (f) '(APPLY$-BADGE 1 1 . T)))
                 (apply$-userfn (lambda (f args) t))))))

(assert-event
 (and (null (ttag (w state)))
      (null (global-val 'ttags-seen (w state)))
      (null (global-val 'skip-proofs-seen (w state)))
      (null (global-val 'redef-seen (w state)))
      (equal (formula 'nil-proved t (w state)) ''nil)))

(mv-let (erp val state)
  (ld '((cw "@SOUNDNESS nil=~x0 ttag=~x1 seen=~x2 skip=~x3 redef=~x4~%"
            (formula 'nil-proved t (w state))
            (ttag (w state))
            (global-val 'ttags-seen (w state))
            (global-val 'skip-proofs-seen (w state))
            (global-val 'redef-seen (w state)))))
  (declare (ignore erp val))
  state)
(quit)
