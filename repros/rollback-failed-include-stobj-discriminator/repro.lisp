;; WRB-S3: Failed include-book poisons (get '*the-live-kid* 'redundant-raw-lisp-discriminator)
;; because hcomp-restore-defs (interface-raw.lisp:5646-5706) only restores symbols in
;; *hcomp-const-restore-ht* (defconst add-trips) and never restores *the-live-<stobj>*
;; discriminator plists written by raw defstobj (basis-a.lisp:9614) / defabsstobj
;; (other-events.lisp:22629) during early compiled-file loading!
;;
;; Proves (defthm nil-proved nil) with ZERO memoize, ZERO :clause-processor,
;; ZERO apply$, ZERO defattach, and :ttags nil on BOTH SBCL 2.6.10 and CCL 1.14!
(in-package "ACL2")

;; BOGUS-ST's raw creator CREATE-BOGUS-ST returns #(99).
(defstobj bogus-st (bogus-fld :type integer :initially 99))

;; KID logically initializes FLD to 0 (CREATE-KID returns #(0)).
(defstobj kid (fld :type integer :initially 0))

;; Temporarily remove KID from *user-stobj-alist* so old-pair is NIL during
;; early compiled-file loading of bad_kid_book (basis-a.lisp:9591).
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
   (declare (ignore erp val))
   (value '(value-triple :poisoned-kid-discriminator))))

;; Restore KID to *user-stobj-alist*.
(make-event
 (er-progn (add-global-stobj 'kid state)
           (value '(value-triple :restored-kid))))

;; Define parent stobj MOM with nested stobj field (K :TYPE KID).
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
(defthm read-fresh-mom-is-0
  (equal (read-fresh-mom) 0)
  :hints (("Goal" :in-theory (disable (:executable-counterpart read-fresh-mom))))
  :rule-classes nil)

;; Proof 2 (by executable counterpart):
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
    (cw "@WRB-S3 ~x0 def=~x1 thm=~x2 ttag=~x3 seen=~x4 skip=~x5 redef=~x6~%"
        (@ host-lisp)
        (not (eq (getpropc 'nil-proved 'theorem :none w) :none))
        (getpropc 'nil-proved 'theorem :none w)
        (ttag w)
        (global-val 'ttags-seen w)
        (global-val 'skip-proofs-seen w)
        (global-val 'redef-seen w))
    (value '(value-triple :done)))))
