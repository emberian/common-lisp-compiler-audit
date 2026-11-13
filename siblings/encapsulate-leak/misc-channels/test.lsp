(in-package "ACL2")

; ---------- Probe C: local defattach leaking into exported evaluation ----------
(value-triple :probe-C-local-defattach)
(encapsulate (((g *) => *))
  (local (defun g (x) (declare (xargs :guard t) (ignore x)) t))
  (defun hh (x) (declare (xargs :guard t) (ignore x)) t)
  (local (defattach g hh)))
; After the encapsulate the local defattach should be gone: g has no attachment.
(value-triple
 (list :probe-C-attachment (attachment-pair 'g (w state))))
; Try to evaluate (g 3): with no attachment this should be an error, caught here.
(make-event
 (mv-let (erp val state)
   (trans-eval-default-warning '(g 3) 'probe-C state t)
   (declare (ignore val))
   (value `(value-triple (list :probe-C-eval-g-erp ,(if erp t nil))))))

; ---------- Probe T: local type-prescription rule strengthening exported fn ----------
(value-triple :probe-T-type-prescription)
(encapsulate (((g2 *) => *))
  (local (defun g2 (x) (declare (xargs :guard t) (ignore x)) 5))
  (local (defthm g2-natp (natp (g2 x)) :rule-classes :type-prescription))
  (defun fT (x) (declare (xargs :guard t)) (g2 x)))
; In pass 1 fT's auto type-prescription could use the LOCAL g2-natp; in the
; exported world g2 has no natp constraint.  Print fT's stored type-prescriptions
; and test whether (natp (fT x)) is provable (it must NOT be, if sound).
(value-triple
 (list :probe-T-fT-tps (getpropc 'fT 'type-prescriptions :none (w state))))
(make-event
 (mv-let (erp val state)
   (thm-fn '(natp (fT x)) state '(("Goal" :in-theory (enable fT))) nil nil nil)
   (declare (ignore val))
   (value `(value-triple (list :probe-T-natp-fT-provable ,(if erp nil t))))))
(quit)
