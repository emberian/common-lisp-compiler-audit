; Probe 4: nested stobjs, stobj-let, stobj-table, with-local-stobj,
; congruent stobjs.  Method: single function, called raw at the top level
; (live stobjs) and proved logically via ec (logical defs on creator).

(defstobj kid (kfld :type integer :initially 5))

(defstobj mom
  (k1 :type kid)                                     ; child stobj field
  (ka :type (array kid (3)))                         ; array of child stobjs
  (kar :type (array kid (2)) :resizable t)           ; resizable array of kids
  (tb :type (stobj-table)))                          ; stobj-table

; --- child scalar field via stobj-let ---
(defun t1 (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((kid (k1 mom)))
   (kid)
   (update-kfld 42 kid)
   mom))

(defun t1-read (mom)
  (declare (xargs :stobjs mom))
  (stobj-let
   ((kid (k1 mom)))
   (v)
   (kfld kid)
   v))

; --- child in array via stobj-let ---
(defun t2 (i mom)
  (declare (xargs :stobjs mom :verify-guards t
                  :guard (and (integerp i) (<= 0 i) (< i 3))))
  (stobj-let
   ((kid (kai i mom)))
   (kid)
   (update-kfld (+ i 100) kid)
   mom))

(defun t2-read (i mom)
  (declare (xargs :stobjs mom :verify-guards t
                  :guard (and (integerp i) (<= 0 i) (< i 3))))
  (stobj-let
   ((kid (kai i mom)))
   (v)
   (kfld kid)
   v))

; --- resizable array of kids: resize up, write new child, read ---
(defun t3-resize (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (resize-kar 4 mom))

(defun t3 (mom)
  (declare (xargs :stobjs mom :verify-guards t
                  :guard (< 3 (kar-length mom))))
  (stobj-let
   ((kid (kari 3 mom)))
   (kid)
   (update-kfld 77 kid)
   mom))

(defun t3-read (mom)
  (declare (xargs :stobjs mom :verify-guards t
                  :guard (< 3 (kar-length mom))))
  (stobj-let
   ((kid (kari 3 mom)))
   (v)
   (kfld kid)
   v))

; fresh slot 2 (created by resize, never written) should read 5 (kid default)
(defun t3-read-fresh (mom)
  (declare (xargs :stobjs mom :verify-guards t
                  :guard (< 2 (kar-length mom))))
  (stobj-let
   ((kid (kari 2 mom)))
   (v)
   (kfld kid)
   v))

; --- stobj-table ---
(defun t4 (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((kid (tb-get 'kid mom (create-kid))))
   (kid)
   (update-kfld 99 kid)
   mom))

(defun t4-read (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((kid (tb-get 'kid mom (create-kid))))
   (v)
   (kfld kid)
   v))

(defun t4-count (mom) (declare (xargs :stobjs mom)) (tb-count mom))
(defun t4-keys  (mom) (declare (xargs :stobjs mom)) (tb-keys mom))

; --- with-local-stobj full program ---
(defun t5 ()
  (declare (xargs :verify-guards t))
  (with-local-stobj
   kid
   (mv-let (v kid)
     (let ((kid (update-kfld 123 kid)))
       (mv (kfld kid) kid))
     v)))

; --- congruent stobj: simple shape to avoid name collisions ---
(defstobj s1 (fld :type integer :initially 1))
(defstobj s2 (fld :type integer :initially 1)
  :renaming ((fldp fldp2) (fld fld2) (update-fld update-fld2))
  :congruent-to s1)

(defun t6 (s2)
  (declare (xargs :stobjs s2 :verify-guards t))
  (update-fld2 55 s2))

(defun t6-read (s2)
  (declare (xargs :stobjs s2))
  (fld2 s2))

; ---------------- RAW ----------------
(t1 mom)
(t1-read mom)                 ; expect 42
(t2 0 mom)
(t2 1 mom)
(t2-read 0 mom)               ; expect 100
(t2-read 1 mom)               ; expect 101
(t2-read 2 mom)               ; expect 5 (untouched child default)
(t3-resize mom)               ; live kar is now length 4
(t3 mom)                      ; write kari 3 = 77
(t3-read mom)                 ; expect 77
(t3-read-fresh mom)           ; expect 5
(t4 mom)
(t4-read mom)                 ; expect 99
(t4-count mom)                ; expect 1
(t4-keys mom)                 ; expect (KID)
(t5)                          ; expect 123
(t6 s2)
(t6-read s2)                  ; expect 55
(fld s1)                      ; expect 1 still (s1 is separate live stobj)

; ---------------- LOGICAL ----------------
(defthm t1-log
  (equal (t1-read (t1 (create-mom))) 42)
  :rule-classes nil)

(defthm t2-log
  (equal (list (t2-read 0 (t2 0 (create-mom)))
               (t2-read 1 (t2 1 (create-mom)))
               (t2-read 2 (t2 0 (create-mom))))
         '(100 101 5))
  :rule-classes nil)

(defthm t3-log
  (equal (list (t3-read (t3 (t3-resize (create-mom))))
               (t3-read-fresh (t3-resize (create-mom))))
         '(77 5))
  :rule-classes nil)

(defthm t4-log
  (equal (list (t4-read (t4 (create-mom)))
               (t4-count (t4 (create-mom)))
               (t4-keys (t4 (create-mom))))
         '(99 1 (kid)))
  :rule-classes nil)

(defthm t5-log
  (equal (t5) 123)
  :rule-classes nil)

(quit)
