(in-package "ACL2")
(defun warrant-sq (x) (* x x))
(defwarrant warrant-sq)
(defun apply-warrant-sq (x) (apply$ 'warrant-sq (list x)))
