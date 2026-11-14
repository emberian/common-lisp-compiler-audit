; XDS-S4: FOR loop$ permits of-type double-float (translate.lisp:18601, 24621), adding the
; iteration variable to known-dfs while compiling (loop for x of-type double-float in lst ...)
; at (safety 0) over a list of boxed ACL2 rationals/bignums.

(defun df-loop-read (k)
  (declare (xargs :guard (equal k 100)))
  (let ((lst (list (expt 2 k))))
    (loop$ for x of-type double-float in lst
           collect (from-df (df+ x (to-df 0))))))

(cw "@CLASS ~x0~%" (symbol-class 'df-loop-read (w state)))
(cw "@RAW-EVAL ~x0~%" (df-loop-read 100))

(memoize 'df-loop-read)
(make-event (let ((ign (df-loop-read 100)))
              (declare (ignore ign))
              '(value-triple :warmed)))

(defthm df-loop-read-logic
  (equal (df-loop-read 100) (list (expt 2 100)))
  :hints (("Goal" :in-theory (e/d (collect$ apply$)
                                  ((df-loop-read) (:e df-loop-read))))))

(defthm nil-proved
  nil
  :hints (("Goal" :use df-loop-read-logic
                  :in-theory (disable df-loop-read df-loop-read-logic)))
  :rule-classes nil)

(cw "@NIL-FORMULA ~x0~%" (formula 'nil-proved t (w state)))
(cw "@TTAG ~x0~%" (ttag (w state)))
(cw "@TTAGS-SEEN ~x0~%" (global-val 'ttags-seen (w state)))
(cw "@SKIP-PROOFS-SEEN ~x0~%" (global-val 'skip-proofs-seen (w state)))
(cw "@END~%")
:q
