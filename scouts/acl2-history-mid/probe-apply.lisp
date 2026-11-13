(in-package "ACL2")
(include-book "projects/apply/top" :dir :system)

(cw "~%=== H31 NONEXECUTABLE FUNCTION THROUGH APPLY$/DEFWARRANT ===~%")
(defun-nx nx31 (x) (if x nil t))
(defwarrant nx31)
(value-triple (apply$ 'nx31 '(nil)))

(cw "~%=== H32 MV FUNCTION THROUGH APPLY$/DEFWARRANT ===~%")
(defun mv32 (x) (mv x (not x)))
(defwarrant mv32)
(value-triple (apply$ 'mv32 '(nil)))

(cw "~%=== H33 ATTACHMENT TO WARRANT ITSELF ===~%")
(defun id33 (x) x)
(defwarrant id33)
(defun false33 () nil)
(defattach apply$-warrant-id33 false33)

(cw "~%=== H34 ATTACHMENT TO FUNCTION SUPPORTING A LATER WARRANT ===~%")
(encapsulate (((c34 *) => * :guard t))
  (local (defun c34 (x) (declare (xargs :guard t)) x)))
(defun f34 (x) (declare (xargs :guard t)) (c34 x))
(defwarrant f34)
(defun c34-impl (x) (declare (xargs :guard t) (ignore x)) t)
(defattach c34 c34-impl)
(value-triple (list (f34 nil) (apply$ 'f34 '(nil))))
(defthm f34-apply-h34
  (implies (apply$-warrant-f34)
           (equal (apply$ 'f34 (list x)) (f34 x)))
  :rule-classes nil)

(cw "~%=== H35 UNATTACHABLE PRIMITIVE VARIANT ===~%")
(defattach canonical-pathname c34-impl)

(quit)
