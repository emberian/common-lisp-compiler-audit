; NOTE-2-8/3-0-2 package-name controls.
(defpkg "" nil)
(defpkg "LISP" nil)
(defpkg "ACL2_*1*_MYPKG" nil)
(defthm pkg-witness-empty-control
  (equal (symbol-package-name (pkg-witness "")) "ACL2")
  :rule-classes nil)
(cw "PKG-WITNESS-EMPTY ~x0~%" (pkg-witness ""))
(quit)
