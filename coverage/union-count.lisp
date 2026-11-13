;;; Union of coverage key files (lists of strings) and counts per key prefix.
;;; Usage: sbcl --script union-count.lisp FILE.sexp ...
(let ((seen (make-hash-table :test 'equal)) (counts (make-hash-table :test 'equal)))
  (dolist (f (cdr sb-ext:*posix-argv*))
    (dolist (k (with-open-file (s f) (read s))) (setf (gethash k seen) t)))
  (maphash (lambda (k v) (declare (ignore v))
             (let ((p (if (eql 0 (search "C:" k)) (subseq k 0 (1+ (position #\: k :start 2))) (subseq k 0 2))))
               (incf (gethash p counts 0))))
           seen)
  (let ((l nil)) (maphash (lambda (k v) (push (format nil "~A ~D" k v) l)) counts)
    (format t "~{~A~^  ~}~%" (sort l #'string<))))
