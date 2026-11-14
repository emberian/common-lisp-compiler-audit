(in-package "ACL2")

;; BOGUS-ST's raw creator CREATE-BOGUS-ST returns #(99).
(defstobj bogus-st (bogus-fld :type integer :initially 99))

;; KID logically initializes FLD to 0 (CREATE-KID returns #(0)).
(defstobj kid (fld :type integer :initially 0))

;; Temporarily remove KID from *user-stobj-alist* so old-pair is NIL during
;; early compiled-file loading of bad_kid_book.
(make-event
 (er-progn (remove-global-stobj 'kid state)
           (value '(value-triple :removed-kid))))

;; Attempt to include bad_kid_book. Its compiled file overwrites
;; (get '*the-live-kid* 'redundant-raw-lisp-discriminator) with
;; :creator CREATE-BOGUS-ST, then include-book fails cleanly on KID
;; redefinition, and hcomp-restore-defs restores CREATE-BOGUS-ST's function
;; binding to #(99) while leaving *the-live-kid*'s discriminator poisoned!
(make-event
 (mv-let (erp val state)
   (include-book "bad_kid_book")
   (declare (ignore val))
   (prog2$
    (cw "~%@R FAILED-INCLUDE erp=~x0~%" erp)
    (value '(value-triple :poisoned-kid-discriminator)))))

;; Restore KID to *user-stobj-alist*.
(make-event
 (er-progn (add-global-stobj 'kid state)
           (value '(value-triple :restored-kid))))

;; Now define parent stobj MOM with nested stobj field (K :TYPE KID).
;; Logically (CREATE-MOM) = ((0)); in raw Lisp defstobj-raw-init-fields calls
;; (get-stobj-creator 'kid nil) -> CREATE-BOGUS-ST -> #(#(99))!
(defstobj mom (k :type kid))

(defun read-mom-k (mom)
  (declare (xargs :stobjs mom))
  (stobj-let ((kid (k mom)))
             (v)
             (fld kid)
             v))

(defun read-fresh-mom ()
  (declare (xargs :guard t))
  (with-local-stobj
   mom
   (mv-let (v mom)
     (mv (read-mom-k mom) mom)
     v)))

;; Proof 1 (by definitional unfolding, disabling executable counterpart):
;; Logically (read-fresh-mom) = 0!
(defthm read-fresh-mom-is-0
  (equal (read-fresh-mom) 0)
  :hints (("Goal" :in-theory (disable (:executable-counterpart read-fresh-mom))))
  :rule-classes nil)

;; Proof 2 (by executable counterpart):
;; At runtime (read-fresh-mom) evaluates to 99!
(defthm read-fresh-mom-is-99
  (equal (read-fresh-mom) 99)
  :hints (("Goal" :in-theory (e/d ((:executable-counterpart read-fresh-mom))
                                  (read-fresh-mom))))
  :rule-classes nil)

(defthm nil-proved
  nil
  :hints (("Goal" :use (read-fresh-mom-is-0 read-fresh-mom-is-99)
                  :in-theory (disable read-fresh-mom
                                      (:executable-counterpart read-fresh-mom))))
  :rule-classes nil)

(make-event
 (let ((w (w state)))
   (prog2$
    (cw "~%@R CREATOR-NIL-PROVED defined=~x0 formula=~x1 ttag=~x2 ttags-seen=~x3 skip-proofs=~x4 redef=~x5~%"
        (not (eq (getpropc 'nil-proved 'theorem :none w) :none))
        (getpropc 'nil-proved 'theorem :none w)
        (ttag w)
        (global-val 'ttags-seen w)
        (global-val 'skip-proofs-seen w)
        (global-val 'redef-seen w))
    (value '(value-triple :done)))))
