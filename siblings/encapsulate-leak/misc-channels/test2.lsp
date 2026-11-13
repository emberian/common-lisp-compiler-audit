(in-package "ACL2")

; ---------- Probe T2: type-prescription recompute (isolated, verify-guards nil) ----------
(value-triple :probe-T2-type-prescription)
(encapsulate (((g2 *) => *))
  (local (defun g2 (x) (declare (xargs :guard t) (ignore x)) 5))
  (local (defthm g2-natp (natp (g2 x)) :rule-classes :type-prescription))
  (defun fT (x) (declare (xargs :guard t :verify-guards nil)) (g2 x)))
(value-triple
 (list :probe-T2-fT-tps (getpropc 'fT 'type-prescriptions :none (w state))))
; (natp (fT x)) must NOT be provable: g2 has no exported natp constraint.
(make-event
 (mv-let (erp val state)
   (thm-fn '(natp (fT x)) state '(("Goal" :in-theory (enable fT))) nil nil nil)
   (declare (ignore val))
   (value `(value-triple (list :probe-T2-natp-fT-provable ,(if erp nil t))))))

; ---------- Probe M: positive control for bogus-exported-measures ----------
; Non-subversive recursion (tests & measured args free of g3) but the MEASURE
; mentions signature fn g3.  bogus-exported-measures MUST reject.
(value-triple :probe-M-measure-mentions-sig)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g3 *) => *))
     (local (defun g3 (x) (declare (xargs :guard t) (ignore x)) 0))
     (defun fM (x)
       (declare (xargs :measure (+ (nfix (g3 x)) (acl2-count x))
                       :guard t :verify-guards nil))
       (if (consp x) (fM (cdr x)) x)))
   (declare (ignore val))
   (value `(value-triple (list :probe-M-encapsulate-erp ,(if erp t nil))))))
(quit)
