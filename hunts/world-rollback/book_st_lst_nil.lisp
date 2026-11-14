(in-package "ACL2")

(defevaluator ev-cp ev-cp-lst ((if x y z) (not x)))

(defstobj st (fld :type integer :initially 0))

(defun read-st (st)
  (declare (xargs :stobjs st :guard t))
  (fld st))

(memoize 'read-st)

;; Including st_lst_helper_book locally inside encapsulate (and rolling it back!)
;; loads st_lst_helper_book's compiled file, whose raw defstobj expansion begins with:
;;   (defg *st-lst-for-st* nil)   [basis-a.lisp:9567]
;; Unlike interface-raw.lisp:7337-7339, which guards with (or (boundp var) ...),
;; raw defg expands to defparameter / ccl::defstatic and UNCONDITIONALLY resets
;; (st-lst 'st) to NIL, erasing 'READ-ST from st's memoize-flush list!
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
