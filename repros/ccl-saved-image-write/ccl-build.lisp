;;; Minimal plain-CCL reproducer, build half.  Run in a fresh darm64cl:
;;;   darm64cl --batch --no-init --load ccl-build.lisp
;;; Two 3-page byte vectors bracket one ordinary compiled function, so that after
;;; purify the function's code vector shares a 16K page with part of one of them.
(defvar *before* (make-array 40000 :element-type '(unsigned-byte 8) :initial-element 0))
(defun set-u8 (a i v)                      ; default optimize policy, safe code
  (declare (type (simple-array (unsigned-byte 8) (*)) a) (fixnum i v))
  (setf (aref a i) v))
(defvar *after* (make-array 40000 :element-type '(unsigned-byte 8) :initial-element 0))
(ccl:save-application "img" :prepend-kernel t)   ; :purify defaults to T
