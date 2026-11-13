; Probe 6: stobj-let with TWO bindings on the SAME stobj-table key.
;
; chk-stobj-let/accessors rejects duplicate accessors; the array index
; anti-aliasing check skips stobj-table accesses entirely (translate.lisp
; no-duplicate-indices-checks-for-stobj-let-actuals-1: ((car creators) alist)).
; Question: can two bindings alias on the same table key, and do raw and
; logic then disagree (destructive sharing vs. sequential write-back)?

(defstobj kid (kfld :type integer :initially 5))
(defstobj mom (tb :type (stobj-table)) (sc :type integer :initially 0))

; seed the table with 'kid -> kid (kfld = 6)
(defun seed (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((kid (tb-get 'kid mom (create-kid))))
   (kid)
   (update-kfld 6 kid)
   mom))

; double binding on the same key; update through the FIRST only
(defun dbl-first (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((k1b (tb-get 'kid mom (create-kid)))
    (k2b (tb-get 'kid mom (create-kid))))
   (k1b)
   (update-kfld 42 k1b)
   mom))

(defun rd (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((kid (tb-get 'kid mom (create-kid))))
   (v)
   (kfld kid)
   v))

; double binding, update through BOTH (last write-back vs shared object)
(defun dbl-both (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((k1b (tb-get 'kid mom (create-kid)))
    (k2b (tb-get 'kid mom (create-kid))))
   (k1b k2b)
   (mv-let (k1b k2b)
     (let* ((k1b (update-kfld 42 k1b)))
       (mv k1b (update-kfld 99 k2b)))
     (mv k1b k2b))
   mom))

; ---------------- RAW ----------------
(seed mom)
(rd mom)          ; expect 6
(dbl-first mom)
(rd mom)          ; raw expect? logical expect?  watch this
(dbl-both mom)
(rd mom)          ; watch this

; ---------------- LOGICAL ----------------
(defthm log-dbl-first
  (equal (rd (dbl-first (seed (create-mom))))
         6)   ; second write-back (unchanged k2b) overwrites 42
  :rule-classes nil)

(defthm log-dbl-both
  (equal (rd (dbl-both (seed (create-mom))))
         6)   ; k2b's write-back is the un-updated original
  :rule-classes nil)

(quit)
