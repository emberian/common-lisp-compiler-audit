; Probe 7: swap-stobjs (both live), :inline t stobj accessors (DEFABBREV raw
; path), two-level nested stobjs with two simultaneous child bindings.

(defstobj s1 (f1 :type integer :initially 11) (g1 :type integer :initially 12))
(defstobj s2 (f1 :type integer :initially 11) (g1 :type integer :initially 12)
  :renaming ((f1p f1p2) (f1 f1b) (update-f1 update-f1b)
             (g1p g1p2) (g1 g1b) (update-g1 update-g1b))
  :congruent-to s1)

; --- swap both live (documented pattern) ---
(defun do-swap (s1 s2)
  (declare (xargs :stobjs (s1 s2) :verify-guards t))
  (swap-stobjs s1 s2))

(defun rd-swap (s1 s2)
  (declare (xargs :stobjs (s1 s2) :verify-guards t))
  (list (f1 s1) (g1 s1) (f1b s2) (g1b s2)))

(defun swap-test (s1)
  (declare (xargs :stobjs s1 :verify-guards t))
  (with-local-stobj
   s2
   (mv-let (r s1 s2)
     (let* ((s2 (update-f1b 99 s2))
            (s1 (update-f1 55 s1)))
       (mv-let (s1 s2)
           (do-swap s1 s2)
         (mv (rd-swap s1 s2) s1 s2)))
     (mv r s1))))

; --- :inline t stobj ---
(defstobj inl (a :type (integer 0 100) :initially 3)
               (b :type (array (unsigned-byte 16) (4)) :initially 65535)
          :inline t)

(defun inl-test ()
  (declare (xargs :verify-guards t))
  (with-local-stobj
   inl
   (mv-let (v inl)
     (let* ((inl (update-a 77 inl))
            (inl (update-bi 2 5 inl)))
       (mv (list (a inl) (bi 2 inl) (bi 0 inl) (b-length inl)) inl))
     v)))

; --- two-level nesting + two children at once ---
(defstobj gk (gfld :type integer :initially 1000))
(defstobj kid (kfld :type integer :initially 5) (gkf :type gk))
(defstobj mom2 (c1 :type kid) (carr :type (array kid (2))))

(defun upd-gk-of (kid)
  (declare (xargs :stobjs kid :verify-guards t))
  (stobj-let ((gk (gkf kid))) (gk) (update-gfld 2000 gk) kid))

(defun two-kids (mom2)
  (declare (xargs :stobjs mom2 :verify-guards t))
  (stobj-let
   ((kid (carri 1 mom2)))
   (kid)
   (upd-gk-of kid)
   mom2))

(defun rd-c1 (mom2)
  (declare (xargs :stobjs mom2))
  (stobj-let ((kid (c1 mom2))) (v) (kfld kid) v))

(defun rd-carr-gk (mom2)
  (declare (xargs :stobjs mom2))
  (stobj-let ((kid (carri 1 mom2))) (v)
    (stobj-let ((gk (gkf kid))) (v2) (gfld gk) v2)
    v))

; ---------------- RAW ----------------
(swap-test s1)  ; expect (99 22 55 12); note: swaps the global s1 too
(inl-test)      ; expect (77 5 65535 4)
(two-kids mom2)
(rd-c1 mom2)            ; expect 5 (c1 untouched)
(rd-carr-gk mom2)       ; expect 2000

; ---------------- LOGICAL ----------------
(defthm swap-log
  (equal (mv-nth 0 (swap-test (create-s1))) '(99 12 55 12))
  :hints (("Goal" :in-theory (disable (:executable-counterpart swap-test))))
  :rule-classes nil)

(defthm inl-log
  (equal (inl-test) '(77 5 65535 4))
  :rule-classes nil)

(defthm two-kids-log
  (equal (rd-carr-gk (two-kids (create-mom2)))
         2000)
  :rule-classes nil)

(quit)
