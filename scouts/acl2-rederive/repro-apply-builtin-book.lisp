(in-package "ACL2")
(defun apply-builtin-car (x) (apply$ 'car (list x)))
(defun apply-builtin-lambda (x)
  (collect$ (lambda$ (y) (+ y 1)) x))
