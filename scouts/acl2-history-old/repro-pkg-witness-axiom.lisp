; PKG-WITNESS axiom control: use the axiom rather than guard-violating execution.
(defthm pkg-witness-empty-control
  (equal (symbol-package-name (pkg-witness "")) "ACL2")
  :hints (("Goal" :use symbol-package-name-pkg-witness-name))
  :rule-classes nil)
(defpkg "" nil)
(quit)
