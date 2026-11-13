(in-package "ACL2")
; NOTE-8-7 stobj/defattach: concrete original, both event orders.
(defstub p-before (x) nil)
(defattach p-before integerp)
(defstobj st-before
  (fld-before :type (or null (satisfies p-before)) :initially nil))

(defstub p-after (x) nil)
(defstobj st-after
  (fld-after :type (or null (satisfies p-after)) :initially nil))
(defattach p-after integerp)
(quit)
