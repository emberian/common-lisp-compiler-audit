; XDS-S2: translate11-flet (translate.lisp:22336) and translate11-macrolet (translate.lisp:22425, 22471)
; pass nil for known-dfs when translating the body of an flet or macrolet, letting unboxed raw
; Common Lisp double-floats escape into ordinary polymorphic ACL2 positions without from-df.

(defun macrolet-df-nil ()
  (declare (xargs :guard t))
  (let ((x (to-df 1)))
    (declare (type double-float x))
    (macrolet ((m (y) y))
      (and (m t) (equal x 1)))))

(cw "@MACROLET-CLASS ~x0~%" (symbol-class 'macrolet-df-nil (w state)))
(cw "@MACROLET-RAW ~x0~%" (macrolet-df-nil))

(defun flet-df-nil ()
  (declare (xargs :guard t))
  (let ((x (to-df 1)))
    (declare (type double-float x))
    (flet ((id (y) y))
      (and (id t) (equal x 1)))))

(cw "@FLET-CLASS ~x0~%" (symbol-class 'flet-df-nil (w state)))
(cw "@FLET-RAW ~x0~%" (flet-df-nil))

(defthm nil-proved
  nil
  :hints (("Goal" :in-theory (disable flet-df-nil (:type-prescription flet-df-nil))
                  :use ((:instance (:type-prescription flet-df-nil)))))
  :rule-classes nil)

(cw "@NIL-FORMULA ~x0~%" (formula 'nil-proved t (w state)))
(cw "@TTAG ~x0~%" (ttag (w state)))
(cw "@TTAGS-SEEN ~x0~%" (global-val 'ttags-seen (w state)))
(cw "@SKIP-PROOFS-SEEN ~x0~%" (global-val 'skip-proofs-seen (w state)))
(cw "@END~%")
:q
