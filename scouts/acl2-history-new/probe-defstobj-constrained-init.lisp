(in-package "ACL2")
; Minimal isolation of host-dependent defstobj admission seen in the attachment probe.
(defstub p (x) nil)
(defstobj st (fld :type (or null (satisfies p)) :initially nil))
(cw "DEFSTOBJ completed; STP on logical initial object: ~x0~%" (stp '(nil)))
(quit)
