; (integer-length (ash 1 k)) is k+1 for every natural k.
(defun il-ash-gv (k)
  (declare (xargs :guard (natp k)))
  (integer-length (ash 1 k)))
(defun il-ash-nogv (k)
  (declare (xargs :guard (natp k) :verify-guards nil))
  (integer-length (ash 1 k)))
(cw "RESULT guard-verified: ~x0~%" (il-ash-gv 1152921504606846975))
(cw "RESULT not guard-verified: ~x0~%" (il-ash-nogv 1152921504606846975))
