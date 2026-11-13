; saved_acl2 < defun-ground-call-assert.lisp
; A legal definition is rejected with "HARD ACL2 ERROR in ASSERT$" because the
; measure conjecture contains the ground call (F '(3)) of the function being
; admitted.  F has no body yet, so ev-fncall-rec-logical reaches its null-body
; case, which passes (car arg-values) and (cadr arg-values) to
; ev-fncall-null-body-er where fn and arg-values are meant (translate.lisp,
; the last ev-fncall-null-body-er call in ev-fncall-rec-logical).  The first
; ARGUMENT, here the cons (3), is then taken for the function "name".
(defun f (n)                       ; fails: hard error, "Evaluation aborted"
  (declare (xargs :measure (nfix n)))
  (if (and (integerp n) (< 5 n))
      (if (f '(3)) (f (- n 1)) 0)
    0))
(defun g (n)                       ; control: same shape, atom argument; admitted
  (declare (xargs :measure (nfix n)))
  (if (and (integerp n) (< 5 n))
      (if (g 3) (g (- n 1)) 0)
    0))
(g 7)
