(in-package "ACL2")
; NOTE-8-3: program-mode names must yield only the trivial meta-extract formula.
(defun prog-nil (x)
  (declare (xargs :mode :program) (ignore x))
  nil)
(assert-event (equal (meta-extract-formula 'prog-nil state) ''t))
(assert-event (equal (fncall-term 'prog-nil '(nil) state) ''t))
; A logic-mode non-executable function is different: its logical definition is
; available and fncall-term may return a real equality; print both as controls.
(defun-nx nx-nil (x) nil)
(cw "NX formula: ~x0~%" (meta-extract-formula 'nx-nil state))
(cw "NX fncall: ~x0~%" (fncall-term 'nx-nil '(nil) state))
(quit)
