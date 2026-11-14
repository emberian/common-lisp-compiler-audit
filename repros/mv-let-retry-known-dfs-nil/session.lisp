; XDS-S3: translate11-collecting-known-dfs (translate.lisp:23020-23022) retry branch
; (entered when stobjs-out-val is still a function symbol on a recursive call in the first branch
; of a defun) omits (set-difference-eq top-known-dfs bound-vars), dropping all outer :df bindings
; inside the mv-let body.

(defun rec-mv-df (n d)
  (declare (type double-float d)
           (xargs :guard (natp n)))
  (if (not (zp n))
      (mv-let (a b)
        (rec-mv-df (- n 1) d)
        (mv a (or b (equal d 1))))
    (mv 0 nil)))

(defun trigger-mv-df ()
  (declare (xargs :guard t))
  (mv-let (a b)
    (rec-mv-df 1 (to-df 1))
    (declare (ignore a))
    b))

(cw "@TRIGGER-CLASS ~x0~%" (symbol-class 'trigger-mv-df (w state)))
(cw "@TRIGGER-RAW ~x0~%" (trigger-mv-df))

(defthm nil-proved
  nil
  :hints (("Goal" :in-theory (disable trigger-mv-df (:e rec-mv-df))
                  :use ((:instance (:definition trigger-mv-df)))
                  :expand ((rec-mv-df 1 1) (rec-mv-df 0 1))))
  :rule-classes nil)

(cw "@NIL-FORMULA ~x0~%" (formula 'nil-proved t (w state)))
(cw "@TTAG ~x0~%" (ttag (w state)))
(cw "@TTAGS-SEEN ~x0~%" (global-val 'ttags-seen (w state)))
(cw "@SKIP-PROOFS-SEEN ~x0~%" (global-val 'skip-proofs-seen (w state)))
(cw "@END~%")
:q
