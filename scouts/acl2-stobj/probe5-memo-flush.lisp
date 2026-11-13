; Probe 5: memoize + stobj-let with a DESTRUCTIVE child update whose stobj
; result is DISCARDED (kid not a producer var).
;
; The note-6-5 fix (translate.lisp stobj-let-fn-raw flush-form) lays down
; (memoize-flush <rep>) only when (intersection-eq producer-vars bound-vars),
; i.e. when the child stobj is returned by the producer.  A destructive
; update via update-kfld discards its stobj result; the raw updater flushes
; only memo tables of functions taking KID, not of functions taking MOM.
; So a memoized MOM-level reader may go stale.

(defstobj kid (kfld :type integer :initially 5))

(defstobj mom (k1 :type kid) (sc :type integer :initially 0))

; mom-level reader through stobj-let
(defun mom-r (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((kid (k1 mom)))
   (v)
   (kfld kid)
   v))

; canonical writer (kid IS a producer var) -- flush-form fires (control)
(defun mom-w1 (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((kid (k1 mom)))
   (kid)
   (update-kfld 3 kid)
   mom))

; sibling writer: destructive update, stobj result DISCARDED
(defun mom-w2 (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((kid (k1 mom)))
   (v)
   (prog2$ (update-kfld 3 kid) v)
   mom))

; logical sanity first (no memoize): both writers give the same logical result
(defthm logic-same
  (equal (mom-r (mom-w2 (create-mom)))
         (mom-r (mom-w1 (create-mom))))
  :rule-classes nil)

; full program with local stobj, runnable raw and provable logically
(defun test2 ()
  (declare (xargs :verify-guards t))
  (with-local-stobj
   mom
   (mv-let (v mom)
     (let* ((mom (mom-w2 mom)))
       (mv (mom-r mom) mom))
     v)))

(defthm logic-test2
  (equal (test2) 3)
  :rule-classes nil)

; now memoize and check raw execution
(memoize 'mom-r)

; raw: fresh image-local live mom has kfld=5; run canonical writer, read
(mom-w1 mom)
(mom-r mom)   ; expect 3 (after canonical write; flush should have fired)

(mom-w2 mom)  ; destructive write, discarded result: set kfld back to 3
(mom-r mom)   ; expect 3 -- if stale memo returns 5, DIVERGENCE

(unmemoize 'mom-r)

; same experiment but starting from 5: write 7 via w2 after reading
(memoize 'mom-r)
(defun mom-w3 (mom)
  (declare (xargs :stobjs mom :verify-guards t))
  (stobj-let
   ((kid (k1 mom)))
   (v)
   (prog2$ (update-kfld 7 kid) v)
   mom))
(mom-w3 mom)
(mom-r mom)   ; expect 7

(quit)
