(in-package "ACL2")

; Can a signature (constrained) function be referenced inside a quoted lambda
; that is apply$'d?  Explore badge/warrant requirements.

; --- A: plain apply$ of a quoted lambda calling constrained g, verify-guards nil
(value-triple :probeA-apply-lambda-g)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g *) => *))
     (local (defun g (x) (declare (xargs :guard t) (ignore x)) t))
     (defun fa (x) (declare (xargs :guard t :verify-guards nil))
       (apply$ '(lambda (y) (g y)) (list x))))
   (declare (ignore val))
   (value `(value-triple (list :probeA-erp ,(if erp t nil))))))

; --- B: give the signature a badge via defbadge, then apply$
(value-triple :probeB-defbadge)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g *) => *))
     (local (defun g (x) (declare (xargs :guard t) (ignore x)) t))
     (defbadge g)
     (defun fb (x) (declare (xargs :guard t :verify-guards nil))
       (apply$ '(lambda (y) (g y)) (list x))))
   (declare (ignore val))
   (value `(value-triple (list :probeB-erp ,(if erp t nil))))))

; --- C: warrant the signature function via defwarrant
(value-triple :probeC-defwarrant)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g *) => *))
     (local (defun g (x) (declare (xargs :guard t) (ignore x)) t))
     (defwarrant g)
     (defun fc (x) (declare (xargs :guard t :verify-guards nil))
       (apply$ '(lambda (y) (g y)) (list x))))
   (declare (ignore val))
   (value `(value-triple (list :probeC-erp ,(if erp t nil))))))
(quit)
