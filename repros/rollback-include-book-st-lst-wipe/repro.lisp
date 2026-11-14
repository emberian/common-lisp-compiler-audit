;; WRB-S4: Raw defstobj (basis-a.lisp:9567) emits (defg ,(st-lst name) nil)
;; at the top of every compiled book's defstobj form, whereas session-level
;; defstobj (interface-raw.lisp:7337-7339) guards with (or (boundp var) ...).
;; Because defg expands to defparameter (#-ccl) / ccl::defstatic (#+ccl),
;; loading ANY compiled book mentioning (defstobj st ...) — even inside a
;; rolled-back (encapsulate () (local (include-book ...))) or a FAILED
;; include-book — unconditionally resets (st-lst 'st) to NIL!
;;
;; Subsequent updates to ST fail to flush previously memoized readers of ST,
;; proving (defthm nil-proved nil) in a :ttags nil certified book on SBCL & CCL!
(in-package "ACL2")

(defevaluator ev-cp ev-cp-lst ((if x y z)))

(defstobj st (fld :type integer :initially 0))

(defun read-st (st)
  (declare (xargs :stobjs st :guard t))
  (fld st))

(memoize 'read-st)

(encapsulate ()
  (local (include-book "st_lst_helper_book")))

(defun leak-cp (clause hint st)
  (declare (xargs :stobjs st :guard t)
           (ignore hint))
  (let* ((st (update-fld 0 st))
         (v0 (read-st st))
         (st (update-fld 1 st))
         (v1 (read-st st))
         (actual (fld st)))
    (declare (ignore v0))
    (if (equal v1 actual)
        (mv nil (list clause) st)
      (mv nil nil st))))

(defthm leak-cp-correct
  (implies (and (pseudo-term-listp clause)
                (alistp a)
                (ev-cp (conjoin-clauses (clauses-result (leak-cp clause hint st))) a))
           (ev-cp (disjoin clause) a))
  :rule-classes :clause-processor)

(defthm nil-proved
  nil
  :hints (("Goal" :clause-processor (leak-cp clause nil st)))
  :rule-classes nil)

(make-event
 (let ((w (w state)))
   (prog2$
    (cw "@WRB-S4 ~x0 def=~x1 thm=~x2 ttag=~x3 seen=~x4 skip=~x5 redef=~x6~%"
        (@ host-lisp)
        (not (eq (getpropc 'nil-proved 'theorem :none w) :none))
        (getpropc 'nil-proved 'theorem :none w)
        (ttag w)
        (global-val 'ttags-seen w)
        (global-val 'skip-proofs-seen w)
        (global-val 'redef-seen w))
    (value '(value-triple :done)))))
