(in-package "ACL2")

; ---------- Probe B: split-types NIL control (the seed's control) ----------
; With :split-types nil the (satisfies g) term is merged INTO the guard, so
; (guard f) mentions g and bogus-exported-compliants MUST reject.
(value-triple :probe-B-split-types-nil)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g *) => *))
     (local (defun g (x) (declare (xargs :guard t) (ignore x)) t))
     (defun fB (x) (declare (type (satisfies g) x) (xargs :guard t :split-types nil)) x))
   (declare (ignore val))
   (value `(value-triple (list :probe-B-encapsulate-erp ,(if erp t nil))))))

; ---------- Probe E: (the (satisfies g) ...) in body, no split-types ----------
; Body mentions g, so fE is in exports-with-sig-ancestors -> rejected.
(value-triple :probe-E-the-in-body)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g *) => *))
     (local (defun g (x) (declare (xargs :guard t) (ignore x)) t))
     (defun fE (x) (declare (xargs :guard t)) (the (satisfies g) x)))
   (declare (ignore val))
   (value `(value-triple (list :probe-E-encapsulate-erp ,(if erp t nil))))))

; ---------- Probe D: redundancy bypass of bogus-exported-compliants ----------
; A local, guard-verified fD (guard (g x), split-types nil) followed by an
; identical EXPORTED fD.  Does redundancy skip the bogus check?
(value-triple :probe-D-redundancy)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g *) => *))
     (local (defun g (x) (declare (xargs :guard t) (ignore x)) t))
     (local (defun fD (x) (declare (type (satisfies g) x) (xargs :guard t :split-types nil)) x))
     (defun fD (x) (declare (type (satisfies g) x) (xargs :guard t :split-types nil)) x))
   (declare (ignore val))
   (value `(value-triple (list :probe-D-encapsulate-erp ,(if erp t nil))))))

; If D admitted fD as compliant, show whether a guard theorem leaked.
(value-triple
 (list :probe-D-fD-class (and (function-symbolp 'fD (w state))
                              (symbol-class 'fD (w state)))))
(quit)
