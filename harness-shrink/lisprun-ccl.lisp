(declaim (inline mask-signed))
(defun mask-signed (width value)
  (declare (type (unsigned-byte 16) width) (type integer value))
  (if (zerop width)
      0
      (if (logbitp (1- width) value)
          (dpb value (byte width 0) -1)
          (ldb (byte width 0) value))))

(handler-case
    (format t "~a	~s~%" "unary-division-31"
            (multiple-value-list
             (funcall (compile nil
                       '(lambda (x count)
             (declare (type fixnum x) (type fixnum count))
             (ceiling x)))
                      0 0)))
  (error ()
    (format t "~a	(:error)~%" "unary-division-31")))
