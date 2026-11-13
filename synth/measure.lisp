;;; Compiler-table coverage of already generated program directories, measured
;;; inside the ACL2 image of HOST while it compiles their -OPT twins.
;;; Usage: sbcl --script measure.lisp HOST OUT.sexp DIR/ [DIR/ ...]
;;; Prints exact counts and writes the union of coverage keys to OUT.sexp.
(load (merge-pathnames "lib.lisp" (directory-namestring *load-truename*)))
(in-package :zs)
(let* ((argv (cdr sb-ext:*posix-argv*))
       (host (if (equal (first argv) "ccl") :ccl :head)) (out (second argv)) (dirs (cddr argv))
       (w (directory-namestring out))
       (seen (make-hash-table :test 'equal)) (valid 0) (answered 0) (asked 0) (diffs 0))
  (loop for group on dirs by (lambda (l) (nthcdr 10 l))
        do (dolist (r (run-batch-robust (subseq group 0 (min 10 (length group))) w :host host :cov t
                                        :timeout 1800 :tag (format nil "measure-~(~A~)" host)))
             (when (res-valid r) (incf valid))
             (incf answered (or (res-answered r) 0)) (incf asked (or (res-queries r) 0))
             (incf diffs (length (res-diffs r)))
             (unless (res-valid r) (format t "NOT VALID ~A ~A~%" (res-dir r) (res-reason r)))
             (dolist (k (res-cov r)) (setf (gethash k seen) t))))
  (with-open-file (s out :direction :output :if-exists :supersede)
    (prin1 (loop for k being the hash-keys of seen collect k) s))
  (format t "~(~A~): ~D/~D programs valid, queries answered ~D/~D, diffs ~D~%" host valid (length dirs)
          answered asked diffs)
  (let ((prefixes (if (eq host :ccl)
                      '("C:COMPILER-MACROS:" "C:NX1:" "C:ACODE-OPS:" "C:REWRITE:" "C:P2:" "C:VINSNS:")
                      '("T:" "V:"))))
    (dolist (p prefixes)
      (format t "  ~A ~D~%" p (loop for k being the hash-keys of seen count (eql 0 (search p k)))))))
