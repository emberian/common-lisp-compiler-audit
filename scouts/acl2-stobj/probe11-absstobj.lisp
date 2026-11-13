; Probe 11: defabsstobj end-to-end (correspondence, raw exec vs logic) and
; the 8.7 stobj-attachment-restrictions.

(defstobj st$c (fld$c :type integer :initially 0))

(defun st$ap (x) (declare (xargs :guard t) (ignore x)) t)
(defun create-st$a () (declare (xargs :guard t)) 0)
(defun fld$a (x) (declare (xargs :guard t)) (ifix x))
(defun update-fld$a (v x) (declare (xargs :guard (integerp v)) (ignore x)) v)
(defun st$corr (st$c x)
  (declare (xargs :stobjs st$c :guard t))
  (equal (fld$c st$c) (ifix x)))

(defthm create-st{correspondence}
  (st$corr (create-st$c) (create-st$a))
  :rule-classes nil)
(defthm create-st{preserved}
  (st$ap (create-st$a))
  :rule-classes nil)
(defthm fld{correspondence}
  (implies (st$corr st$c st) (equal (fld$c st$c) (fld$a st)))
  :rule-classes nil)
(defthm update-fld{correspondence}
  (implies (and (st$corr st$c st) (integerp v))
           (st$corr (update-fld$c v st$c) (update-fld$a v st)))
  :rule-classes nil)
(defthm update-fld{preserved}
  (implies (and (st$ap st) (integerp v))
           (st$ap (update-fld$a v st)))
  :rule-classes nil)

(defabsstobj st :foundation st$c
  :recognizer (stp :logic st$ap :exec st$cp)
  :creator (create-st :logic create-st$a :exec create-st$c)
  :corr-fn st$corr
  :exports ((fld :logic fld$a :exec fld$c)
            (update-fld :logic update-fld$a :exec update-fld$c)))

; program: update then read, raw and logical
(defun abs-test ()
  (declare (xargs :verify-guards t))
  (with-local-stobj
   st
   (mv-let (v st)
     (let* ((st (update-fld 7 st))
            (v1 (fld st))
            (st (update-fld (+ v1 1) st)))
       (mv (fld st) st))
     v)))

(abs-test)   ; raw: expect 8

(defthm abs-test-log
  (equal (abs-test) 8)
  :rule-classes nil)

; 8.7 restriction: attaching to an ancestor of the abstract recognizer
; st$ap is stp's :logic function.  Try to attach to it.
(defun fake-ap (x) (declare (xargs :guard t) (ignore x)) nil)

; make st$ap attachable is impossible (it has a defun); the interesting
; attack is a CONSTRAINED function used in the recognizer logic.  Try:
(encapsulate (((constr-flg *) => *))
  (local (defun constr-flg (x) (declare (ignore x)) t)))
(defun st2$ap (x) (declare (xargs :guard t)) (constr-flg x))

; defabsstobj whose recognizer logic calls a constrained function:
(defabsstobj st2 :foundation st$c
  :recognizer (st2p :logic st2$ap :exec st$cp)
  :creator (create-st2 :logic create-st$a :exec create-st$c)
  :exports ((fld2 :logic fld$a :exec fld$c)))

; if that succeeded, attach constr-flg to something false and make the
; recognizer deny the live object:
(defun always-no (x) (declare (xargs :guard t) (ignore x)) nil)

(quit)
