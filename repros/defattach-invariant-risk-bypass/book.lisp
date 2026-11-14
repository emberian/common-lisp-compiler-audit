(in-package "ACL2")

; SCR-S3: defattach fails to propagate or enforce 'invariant-risk when attaching
; a stobj/array updater implementation with 'invariant-risk and a non-trivial
; guard to a constrained function (which always has 'invariant-risk = nil),
; letting :program-mode code corrupt the live stobj in raw Lisp without any
; invariant-risk check and proving (defthm nil-proved nil) via a verified
; stobj-taking :clause-processor.
;
; Root cause:
; 1. Constrained functions introduced by encapsulate always have
;    (getpropc 'my-st-fn 'invariant-risk nil wrld) = nil.
; 2. (defattach my-st-fn my-st-impl) installs raw Lisp dispatch from my-st-fn
;    to my-st-impl (axioms.lisp:5341-5344) without propagating 'invariant-risk
;    from my-st-impl (update-fld) or checking 'invariant-risk at dispatch time.
; 3. :program-mode (defun corrupt (st) ... (my-st-fn 'not-an-integer st))
;    computes 'invariant-risk = nil (defuns.lisp:5994-6010), compiles directly
;    to raw Lisp without *1* guard checking, and writes 'not-an-integer into
;    st's integer field!

(defstobj st (fld :type integer :initially 0))

(encapsulate
  (((my-st-fn * st) => st
    :formals (x st)
    :guard (and (integerp x) (stp st))))
  (local (defun my-st-fn (x st)
           (declare (xargs :stobjs st :guard (integerp x)))
           (update-fld x st))))

(defun my-st-impl (x st)
  (declare (xargs :stobjs st :guard (integerp x)))
  (update-fld x st))

(defattach my-st-fn my-st-impl)

(defun corrupt (st)
  (declare (xargs :mode :program :stobjs st))
  (my-st-fn 'not-an-integer st))

(defevaluator my-ev my-ev-lst ((if x y z)))

(defun my-cp (clause hint st)
  (declare (xargs :stobjs st :guard t) (ignore hint))
  (if (or (not (stp st)) (integerp (fld st)))
      (mv nil (list clause))
    (mv nil nil)))

(defthm my-cp-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (my-ev (conjoin-clauses (clauses-result (my-cp clause hint st))) a))
           (my-ev (disjoin clause) a))
  :rule-classes :clause-processor)

(make-event
 (let ((st (corrupt st)))
   (mv nil '(value-triple :corrupted) state st)))

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (my-cp clause nil st)))
  :rule-classes nil)
