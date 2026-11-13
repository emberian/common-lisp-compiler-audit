(defun presave-fn (x) (+ x 1))
(defvar *u8* (make-array 4 :element-type '(unsigned-byte 8) :initial-element 0))
(defun set-u8-safe (a i v) (declare (type (simple-array (unsigned-byte 8) (*)) a) (fixnum i v)) (setf (aref a i) v))
(ccl:save-application "img" :prepend-kernel t :purify nil)
