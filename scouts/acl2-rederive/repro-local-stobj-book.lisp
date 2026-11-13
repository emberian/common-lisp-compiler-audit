(in-package "ACL2")
(defstobj local-st fld)
(defun local-st-value (x)
  (declare (xargs :verify-guards nil))
  (with-local-stobj
   local-st
   (mv-let (ans local-st)
           (let ((local-st (update-fld (1+ x) local-st)))
             (mv (fld local-st) local-st))
           ans)))
