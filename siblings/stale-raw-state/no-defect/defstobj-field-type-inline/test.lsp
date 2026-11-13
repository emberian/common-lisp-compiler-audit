; stobj field typed (unsigned-byte 8) with :inline t accessors (raw macros), :u, the same stobj
; with an integer field.  Writes 2^70 and reads it back through guard-verified and non-verified readers.
(defstobj st (fld :type (unsigned-byte 8) :initially 0) :inline t)
:u
(defstobj st (fld :type integer :initially 0) :inline t)
(defun w-gv (x st) (declare (xargs :stobjs st :guard (integerp x))) (update-fld x st))
(defun r-gv (st) (declare (xargs :stobjs st)) (+ 1 (fld st)))
(defun r-nogv (st) (declare (xargs :stobjs st :verify-guards nil)) (+ 1 (fld st)))
(w-gv 1180591620717411303424 st)
(cw "RESULT guard-verified: ~x0~%" (r-gv st))
(cw "RESULT not guard-verified: ~x0~%" (r-nogv st))
