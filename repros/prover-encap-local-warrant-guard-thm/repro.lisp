(in-package "ACL2")

; Pure-Kernel Soundness Bug:
; 1. `special-conjectures` (history-management.lisp:13290-13320, 13409-13415)
;    adds warrant hypotheses `(apply$-warrant-g)` via `(get-warrantp val wrld)`
;    for function symbols occurring in `:FN`/`:EXPR` slots of `loop$` scions,
;    including non-lambda expressions such as `(list (apply$ 'g '(nil)))`.
; 2. During Pass 2 of `encapsulate` (`ld-skip-proofsp = 'include-book`), `local`
;    warrant events are skipped and `chk-common-lisp-compliant-subfunctions-cmp`
;    (defuns.lisp:4310-4327) checks warrants ONLY on well-formed quoted lambda
;    objects (`warrants-for-tamep-lambdap-lst`), missing `'g` in the non-lambda
;    target expression! Thus `fn` is exported as `:common-lisp-compliant` into
;    an outer world where `(get-warrantp 'g wrld)` is `NIL`.
; 3. `(:guard-theorem fn)` (history-management.lisp:14550-14596, 14810-14837)
;    recomputes `guard-clauses-for-clique` in the outer world without
;    `(apply$-warrant-g)`, yielding `(equal (apply$-userfn 'g '(nil)) 0)`
;    unconditionally; `:functional-instance` then proves `nil-proved`!

(defun g (x)
  (declare (ignore x) (xargs :guard t))
  0)

(table badge-table :badge-userfn-structure
  (put-badge-userfn-structure-tuple-in-alist
   (make-badge-userfn-structure-tuple 'g nil '(APPLY$-BADGE 1 1 . T))
   (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table world)))
   'defbadge)
  :put)

(encapsulate ()
  (local
   (defun-sk apply$-warrant-g ()
     (forall (args)
       (and (equal (badge-userfn 'g) '(APPLY$-BADGE 1 1 . T))
            (equal (apply$-userfn 'g args) (g (car args)))))
     :constrain t))
  (local
   (in-theory (disable apply$-warrant-g-definition)))
  (local
   (defthm apply$-g
     (implies (force (apply$-warrant-g))
              (and (equal (badge 'g) '(APPLY$-BADGE 1 1 . T))
                   (equal (apply$ 'g args) (g (car args)))))
     :hints (("Goal" :use apply$-warrant-g-necc
              :expand ((:free (x) (hide (badge x))))
              :in-theory (e/d (badge apply$) (apply$-warrant-g-necc g))))))
  (local
   (table badge-table :badge-userfn-structure
     (put-badge-userfn-structure-tuple-in-alist
      (make-badge-userfn-structure-tuple 'g t '(APPLY$-BADGE 1 1 . T))
      (cdr (assoc-eq :badge-userfn-structure (table-alist 'badge-table world)))
      'defwarrant)
     :put))
  (defun fn ()
    (declare (xargs :guard t))
    (collect$ (lambda$ (x) (declare (xargs :guard (equal x 0))) x)
              (list (apply$ 'g '(nil))))))

(defthm step1
  (equal (apply$-userfn 'g '(nil)) 0)
  :rule-classes nil
  :hints (("Goal"
           :use (:instance (:guard-theorem fn)
                           (newv (apply$ 'g '(nil))))
           :in-theory (e/d (apply$)
                           ((:executable-counterpart apply$))))))

(defthm nil-proved
  nil
  :rule-classes nil
  :hints (("Goal"
           :use (:functional-instance
                 step1
                 (badge-userfn (lambda (f) nil))
                 (apply$-userfn (lambda (f args) 1))))))

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
