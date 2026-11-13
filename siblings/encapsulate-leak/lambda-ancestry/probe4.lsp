(in-package "ACL2")

; --- E: signature fn inside a quoted lambda's :GUARD (not body) ---
(value-triple :probeE-lambda-guard)
(make-event
 (mv-let (erp val state)
   (encapsulate (((g *) => *))
     (local (defun g (x) (declare (xargs :guard t) (ignore x)) t))
     (defun fe (x) (declare (xargs :guard t :verify-guards nil))
       (apply$ '(lambda (y) (declare (xargs :guard (g y))) y) (list x))))
   (declare (ignore val))
   (value `(value-triple (list :probeE-erp ,(if erp t nil))))))

; --- defchoose: does a sig-fn dependence fold into g's constraint? ---
(value-triple :probe-defchoose)
(encapsulate (((g *) => *))
  (local (defun g (x) (declare (xargs :guard t) (ignore x)) nil))
  (defchoose fch w (x) (and (g x) (equal w x))))
(value-triple
 (list :defchoose-g-constraint (getpropc 'g 'constraint-lst-etc :none (w state))
       :defchoose-fch-constraint (and (getpropc 'fch 'constraint-lst-etc nil (w state)) t)))
; Try to prove (g x) (should FAIL: the choice axiom is g's only constraint and
; does not entail (g x) for all x).
(make-event
 (mv-let (erp val state)
   (thm-fn '(g x) state nil nil nil nil)
   (declare (ignore val))
   (value `(value-triple (list :defchoose-g-x-provable ,(if erp nil t))))))

; --- defun-sk: sig-fn under a quantifier ---
(value-triple :probe-defun-sk)
(encapsulate (((g2 *) => *))
  (local (defun g2 (x) (declare (xargs :guard t) (ignore x)) nil))
  (defun-sk all-g2 () (forall x (g2 x))))
(value-triple
 (list :defun-sk-g2-constraint (getpropc 'g2 'constraint-lst-etc :none (w state))))
(quit)
