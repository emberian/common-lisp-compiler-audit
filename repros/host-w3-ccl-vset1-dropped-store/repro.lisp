;;;; Repro: CCL 1.14 x86-64 x862-vset1 (compiler/X86/x862.lisp:3018-3024)
;;;; Misplaced closing paren on line 3019 places misc-set-{double-float,s64,u64} inside
;;;; the false branch of (if index-known-fixnum ...). Any constant-index store with
;;;; idx >= #x10000000 silently omits the memory store instruction, even at (safety 3).

(in-package :cl-user)

(format t "Impl: ~a ~a (~a)~%" (lisp-implementation-type) (lisp-implementation-version) (machine-type))

(dolist (spec `((double-float 42.5d0)
                ((unsigned-byte 64) #x123456789abcdef0)
                ((signed-byte 64) #x-123456789abcdef)))
  (destructuring-bind (etype newval) spec
    (let* ((v (make-array #x10000001 :element-type etype))
           (f (compile nil `(lambda (vec val)
                              (declare (type (simple-array ,etype (*)) vec)
                                       (type ,etype val)
                                       (optimize (speed 1) (safety 3)))
                              (setf (aref vec #x10000000) val)))))
      (funcall f v newval)
      (let ((got (aref v #x10000000)))
        (format t "  ~s (safety 3): wrote ~s, read back ~s (pass=~s)~%"
                etype newval got (eql got newval))))
    #+ccl (ccl:gc)))

#+ccl (ccl:quit 0)
#+sbcl (sb-ext:exit :code 0)
