;; Find a shape where then=else reaches move-if/word (both constant 1 / -1)
;; but IR1 does not fold the if.
(defun try-shape (name src)
  (format t "=== ~a ===~%" name)
  (handler-case
      (let ((f (compile nil src)))
        (declare (ignorable f))
        (let ((*standard-output* (make-broadcast-stream))) (disassemble f))
        ;; also print disasm to a string we can grep
        (with-output-to-string (s)
          (let ((*standard-output* s)) (disassemble f))
          (with-input-from-string (in (get-output-stream-string s))
            (loop for line = (read-line in nil nil)
                  while line
                  when (search "CNEG" line) do (format t "  >>> ~a~%" line)
                  when (search "CSEL" line) do (format t "  csel: ~a~%" line)))))
    (error (e) (format t "  ERROR: ~a~%" e))))

(try-shape 'let-else
  '(lambda (a b)
    (declare (type (unsigned-byte 64) a b) (optimize (speed 3) (safety 0)))
    (let ((x 1))
      (logand (if (< a b) 1 x) a))))
(try-shape 'let-else-neg
  '(lambda (a b)
    (declare (type (unsigned-byte 64) a b) (optimize (speed 3) (safety 0)))
    (let ((x -1))
      (logand (if (< a b) -1 x) a))))
(try-shape 'eql-type
  '(lambda (a b)
    (declare (type (unsigned-byte 64) a b) (optimize (speed 3) (safety 0)))
    (logand (if (< a b) 1 (the (eql 1) b)) a)))
(try-shape 'and-shape
  '(lambda (a b)
    (declare (type (unsigned-byte 64) a b) (optimize (speed 3) (safety 0)))
    (logand (if (< a b) (logior 0 1) 1) a)))
(try-shape 'signed-store
  '(lambda (a b v)
    (declare (type (signed-byte 64) a b)
             (type (simple-array (signed-byte 64) (1)) v)
             (optimize (speed 3) (safety 0)))
    (let ((x -1))
      (setf (aref v 0) (if (< a b) -1 x))
      (aref v 0))))
(try-shape 'if-if
  '(lambda (a b c)
    (declare (type (unsigned-byte 64) a b c) (optimize (speed 3) (safety 0)))
    (logand (if (< a b) 1 (if (< b c) 1 1)) a)))
