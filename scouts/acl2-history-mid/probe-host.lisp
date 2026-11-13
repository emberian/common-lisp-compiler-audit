(in-package "ACL2")

(cw "~%=== H43 HOST-LISP IS NOT IN INITIAL GLOBAL CONSTANT ===~%")
(value-triple (assoc 'host-lisp *initial-global-table*))
(value-triple (check-sum-obj *initial-global-table*))
(defthm host-lisp-is-ccl-h43
  (equal (cdr (assoc 'host-lisp *initial-global-table*)) :ccl)
  :rule-classes nil)
(defthm host-lisp-is-sbcl-h43
  (equal (cdr (assoc 'host-lisp *initial-global-table*)) :sbcl)
  :rule-classes nil)

(quit)
