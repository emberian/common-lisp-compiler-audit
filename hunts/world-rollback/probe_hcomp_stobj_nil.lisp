(in-package "ACL2")

(defstobj kid fld1)
(defstobj mom (kid-field :type kid))

;; Step 1: Temporarily remove MOM from *user-stobj-alist* so old-pair is NIL
;; during the early compiled-file load of bad_mom_book.
(make-event
 (er-progn (remove-global-stobj 'mom state)
           (value '(value-triple :removed))))

;; Step 2: Attempt to include bad_mom_book (which defines a conflicting MOM
;; with :non-memoizable t). include-book-raw early-loads bad_mom_book's
;; compiled file, clobbering (get '*the-live-mom* 'redundant-raw-lisp-discriminator)
;; with :non-memoizable t, then fails with a soft redefinition error;
;; hcomp-restore-defs fails to restore redundant-raw-lisp-discriminator!
(make-event
 (mv-let (erp val state)
   (include-book "bad_mom_book")
   (declare (ignore val))
   (prog2$
    (cw "~%@R FAILED-INCLUDE-BOOK erp=~x0~%" erp)
    (value '(value-triple :failed-include-cleanly)))))

;; Step 3: Restore global stobj MOM. Logically MOM is unchanged and memoizable,
;; while raw Lisp now believes (non-memoizable-stobj-raw 'mom) = T!
(make-event
 (er-progn (add-global-stobj 'mom state)
           (value '(value-triple :restored))))

;; Step 4: Now define stobj-let updater and reader on MOM (from ACL2's own
;; translate.lisp:17235-17276 note-6-5 soundness regression!). Because
;; (non-memoizable-stobj-raw 'mom) is now T, stobj-let-fn-raw omits
;; (memoize-flush mom) from mom.update-fld1!
(defun mom.update-fld1 (val mom)
  (declare (xargs :stobjs mom))
  (stobj-let ((kid (kid-field mom)))
             (kid)
             (update-fld1 val kid)
             mom))

(defun mom.fld1 (mom)
  (declare (xargs :stobjs mom))
  (stobj-let ((kid (kid-field mom)))
             (val)
             (fld1 kid)
             val))

(defun test ()
  (declare (xargs :guard t))
  (with-local-stobj
   mom
   (mv-let (val mom)
     (let* ((mom (mom.update-fld1 3 mom))
            (val1 (mom.fld1 mom))
            (mom (mom.update-fld1 4 mom))
            (val2 (mom.fld1 mom)))
       (mv (equal val1 val2) mom))
     val)))

(defthm true-prop
  (not (test))
  :rule-classes nil)

(memoize 'mom.fld1)

(defthm false-prop
  (test)
  :rule-classes nil)

(defthm nil-proved
  nil
  :hints (("Goal" :in-theory nil :use (true-prop false-prop)))
  :rule-classes nil)

(make-event
 (let ((w (w state)))
   (prog2$
    (cw "~%@R HCOMP-NIL-PROVED formula=~x0 ttag=~x1 ttags-seen=~x2 skip-proofs=~x3 redef=~x4~%"
        (formula 'nil-proved nil w)
        (ttag w)
        (global-val 'ttags-seen w)
        (global-val 'skip-proofs-seen w)
        (global-val 'redef-seen w))
    (value '(value-triple :done)))))
