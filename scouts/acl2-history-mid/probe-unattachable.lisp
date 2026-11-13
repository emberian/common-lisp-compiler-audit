(in-package "ACL2")

(cw "~%=== H35R CANONICAL-PATHNAME ATTACHMENT, SYSTEM-OK ===~%")
(defun cp35-impl (fname dirp state)
  (declare (xargs :stobjs state :guard t)
           (ignore fname dirp state))
  nil)
(defattach (canonical-pathname cp35-impl) :system-ok t)

(cw "~%=== H36 APPLY$-USERFN ATTACHMENT, SYSTEM-OK ===~%")
(defun apply-user36-impl (fn args)
  (declare (xargs :guard t) (ignore fn args))
  nil)
(defattach (apply$-userfn apply-user36-impl) :system-ok t)

(cw "~%=== H37 BADGE-USERFN ATTACHMENT, SYSTEM-OK ===~%")
(defun badge-user37-impl (fn)
  (declare (xargs :guard t) (ignore fn))
  nil)
(defattach (badge-userfn badge-user37-impl) :system-ok t)

(quit)
