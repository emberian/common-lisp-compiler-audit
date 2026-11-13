; As defstobj-field-type-inline, without :inline (accessors are raw defuns).
(defstobj st (fld :type (unsigned-byte 8) :initially 0))
:u
(defstobj st (fld :type integer :initially 0))
(defun w-gv (x st) (declare (xargs :stobjs st :guard (integerp x))) (update-fld x st))
(defun r-gv (st) (declare (xargs :stobjs st)) (+ 1 (fld st)))
(defun r-nogv (st) (declare (xargs :stobjs st :verify-guards nil)) (+ 1 (fld st)))
(w-gv 1180591620717411303424 st)
(cw "RESULT guard-verified: ~x0~%" (r-gv st))
(cw "RESULT not guard-verified: ~x0~%" (r-nogv st))
