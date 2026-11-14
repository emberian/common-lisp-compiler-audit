(in-package "ACL2")

; SCR-S2: Default (memoize 'my-caller) (:aokp nil) + apply$-lambda *cl-cache*
; bypasses both *aokp* attachment tracking and *warrant-reqs* warrant tracking,
; proving (defthm nil-proved nil) with no :clause-processor, no defattach,
; no :program mode, and no trust tags.
;
; Root cause: memoize-fn-inner-body (memoize-raw.lisp:2850-2881) relies on
; *aokp* and *warrant-reqs* mutating during misses to block storing attachment-
; or warrant-dependent results in :aokp nil memo tables (which are trusted
; unconditionally during proofs). However, apply$-lambda (apply-raw.lisp:4189-4221)
; fast-paths :GOOD compiled *cl-cache* entries via direct (apply :guard-code args)
; and (apply :lambda-code args) without touching doppelganger-apply$-userfn,
; update-attached-fn-called, or *warrant-reqs*. On the 2nd call to (my-caller 10),
; the :aokp nil memo table caches 10 -> 42 (and later 10 -> 99) with zero warrant
; hypotheses recorded, proving both (= (my-caller 10) 42) and (= (my-caller 10) 99).

(defun my-caller (x)
  (declare (xargs :guard t))
  (apply$ (cons 'LAMBDA '((Z) (MY-U Z))) (list x)))

(memoize 'my-caller)

(encapsulate ()
  (local (defun my-u (z) (declare (xargs :guard t) (ignore z)) 42))
  (local
   (make-event
    (let ((badge '(APPLY$-BADGE 1 1 . T)))
      `(encapsulate ()
         ,@(defwarrant-events 'my-u '(z) badge)
         (table badge-table
                :badge-userfn-structure
                (put-badge-userfn-structure-tuple-in-alist
                 (make-badge-userfn-structure-tuple 'my-u T ',badge)
                 (cdr (assoc :badge-userfn-structure
                             (table-alist 'badge-table world)))
                 'defwarrant)
                :put)
         (defattach ,(warrant-name 'my-u) true-apply$-warrant)))))
  (local
   (make-event
    (let* ((v1 (my-caller 10))
           (v2 (my-caller 10)))
      (declare (ignore v1 v2))
      '(value-triple :cached-42))))
  (defthm thm-42
    (equal (my-caller 10) 42)
    :hints (("Goal" :in-theory (disable my-caller)))))

(make-event
 (let ((ign (clear-memoize-tables)))
   (declare (ignore ign))
   '(value-triple :cleared)))

(encapsulate ()
  (local (defun my-u (z) (declare (xargs :guard t) (ignore z)) 99))
  (local
   (make-event
    (let ((badge '(APPLY$-BADGE 1 1 . T)))
      `(encapsulate ()
         ,@(defwarrant-events 'my-u '(z) badge)
         (table badge-table
                :badge-userfn-structure
                (put-badge-userfn-structure-tuple-in-alist
                 (make-badge-userfn-structure-tuple 'my-u T ',badge)
                 (cdr (assoc :badge-userfn-structure
                             (table-alist 'badge-table world)))
                 'defwarrant)
                :put)
         (defattach ,(warrant-name 'my-u) true-apply$-warrant)))))
  (local
   (make-event
    (let* ((v1 (my-caller 10))
           (v2 (my-caller 10)))
      (declare (ignore v1 v2))
      '(value-triple :cached-99))))
  (defthm thm-99
    (equal (my-caller 10) 99)
    :hints (("Goal" :in-theory (disable my-caller)))))

(defthm nil-proved
  nil
  :hints (("Goal" :in-theory (disable my-caller (my-caller))
                  :use (thm-42 thm-99)))
  :rule-classes nil)
