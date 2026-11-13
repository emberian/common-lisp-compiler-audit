(in-package "ACL2")
(include-book "projects/apply/top" :dir :system)

; Can a constrained signature function be badged/warranted?
(value-triple :probeB2-defbadge-on-sig)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g *) => *))
     (local (defun g (x) (declare (xargs :guard t) (ignore x)) t))
     (defbadge g))
   (declare (ignore val))
   (value `(value-triple (list :probeB2-defbadge-erp ,(if erp t nil))))))

(value-triple :probeC2-defwarrant-on-sig)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g *) => *))
     (local (defun g (x) (declare (xargs :guard t) (ignore x)) t))
     (defwarrant g))
   (declare (ignore val))
   (value `(value-triple (list :probeC2-defwarrant-erp ,(if erp t nil))))))

; Signature that declares the badge directly (if supported)?
(value-triple :probeD2-sig-badge)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g *) => * :badge (apply$-badge 1 1 . t)))
     (local (defun g (x) (declare (xargs :guard t) (ignore x)) t)))
   (declare (ignore val))
   (value `(value-triple (list :probeD2-sig-badge-erp ,(if erp t nil))))))
(quit)
