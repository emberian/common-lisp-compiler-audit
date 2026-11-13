(in-package "ACL2")
(set-state-ok t)
(defmacro world-sensitive-macro (state)
  (if (getpropc '*include-marker* 'const nil (w state))
      ''rich
    ''base))
(defun world-sensitive-fn (state)
  (declare (xargs :stobjs state :verify-guards nil))
  (world-sensitive-macro state))
(defthm world-sensitive-fn-base
  (equal (world-sensitive-fn state) 'base)
  :rule-classes nil)
