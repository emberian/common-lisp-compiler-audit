;;; N: overflow-ash-unsigned constant negative counts.
(setq *compile-print* nil *compile-verbose* nil)
(defparameter *n-vals*
  '(0 1 2 3 4 5 7 8 15 16 63 64 65
    4611686018427387903 4611686018427387904
    9223372036854775807 9223372036854775808
    18446744073709551614 18446744073709551615))
(defun n-compile (form)
  (let ((result nil))
    (with-output-to-string (*standard-output*)
      (with-output-to-string (*error-output*)
        (setf result (compile nil form))))
    result))
(defun n-result (thunk)
  (handler-case (multiple-value-list (funcall thunk))
    (error (e) (list :error (type-of e) (princ-to-string e)))))
(defparameter *n-fails* 0)
(dolist (shift '(-1 -2 -3 -4 -31 -32 -62 -63 -64 -65))
  ;; Restrict the input for -1 so the result declaration is true; for <=-2
  ;; every u64 input has a fixnum result.
  (let* ((type (if (= shift -1)
                   '(integer 0 4611686018427387903)
                   '(unsigned-byte 64)))
         (body `(the fixnum (ash x ,shift)))
         (f (n-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0))) ,body)))
         (g (n-compile `(lambda (x) (declare (type ,type x) (optimize (speed 3) (safety 0)))
                          (locally (declare (notinline ash)) ,body)))))
    (format t "N case shift=~d type=~s~%" shift type)
    (dolist (x *n-vals*)
      (when (typep x type)
        (let ((a (n-result (lambda () (funcall f x))))
              (b (n-result (lambda () (funcall g x)))))
          (unless (equal a b)
            (incf *n-fails*)
            (format t "NDIVERGE shift=~d x=~s inline=~s ref=~s~%" shift x a b)))))))

;;; Variable negative counts whose entire declared range preserves fixnumness.
(let* ((body '(the fixnum (ash x n)))
       (f (n-compile `(lambda (x n)
                        (declare (type (unsigned-byte 64) x) (type (integer -64 -2) n)
                                 (optimize (speed 3) (safety 0))) ,body)))
       (g (n-compile `(lambda (x n)
                        (declare (type (unsigned-byte 64) x) (type (integer -64 -2) n)
                                 (optimize (speed 3) (safety 0)))
                        (locally (declare (notinline ash)) ,body)))))
  (dolist (x *n-vals*)
    (dolist (n '(-64 -63 -62 -32 -4 -3 -2))
      (let ((a (n-result (lambda () (funcall f x n))))
            (b (n-result (lambda () (funcall g x n)))))
        (unless (equal a b)
          (incf *n-fails*)
          (format t "NDIVERGE variable x=~s n=~s inline=~s ref=~s~%" x n a b))))))

(format t "=== disassembly constant -2 ===~%")
(disassemble
 (compile nil '(lambda (x)
                (declare (type (unsigned-byte 64) x) (optimize (speed 3) (safety 0)))
                (the fixnum (ash x -2)))))
(format t "probe N done, fails=~d~%" *n-fails*)
