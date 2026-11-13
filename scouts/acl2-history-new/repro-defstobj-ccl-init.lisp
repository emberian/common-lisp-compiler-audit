; Reproduce with:
;   ../lisp-run.sh acl2-sbcl repro-defstobj-ccl-init.lisp
;   ../lisp-run.sh acl2-ccl repro-defstobj-ccl-init.lisp
; Expected from the regression's event shape: admission on both hosts.
; Observed: admission on SBCL; non-executable P evaluation error on CCL.
(in-package "ACL2")
(defstub p (x) nil)
(defstobj st (fld :type (or null (satisfies p)) :initially nil))
(cw "DEFSTOBJ completed; STP on logical initial object: ~x0~%" (stp '(nil)))
(quit)
