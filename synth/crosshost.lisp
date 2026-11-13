;;; Cross-host residue comparison of already generated program directories:
;;; every query record (@Q index case residue status) must be identical on the
;;; SBCL-hosted and the CCL-hosted ACL2, including which queries are answered.
;;; Usage: sbcl --script crosshost.lisp WORKDIR/ DIR/ [DIR/ ...]
(load (merge-pathnames "lib.lisp" (directory-namestring *load-truename*)))
(in-package :zs)
(let* ((argv (cdr sb-ext:*posix-argv*)) (w (first argv)) (dirs (cdr argv)) (bad 0) (total 0))
  (loop for group on dirs by (lambda (l) (nthcdr 10 l))
        do (let* ((g (subseq group 0 (min 10 (length group))))
                  (h (run-batch-robust g w :host :head :cov nil :timeout 1200 :tag "xh-head"))
                  (c (run-batch-robust g w :host :ccl :cov nil :timeout 1800 :tag "xh-ccl")))
             (loop for rh in h for rc in c
                   do (incf total)
                      (unless (and (res-valid rh) (res-valid rc) (equal (q-lines rh) (q-lines rc)))
                        (incf bad)
                        (format t "DIFFERENT ~A head ~A/~A ~A ccl ~A/~A ~A~%" (res-dir rh)
                                (res-answered rh) (res-queries rh) (res-reason rh)
                                (res-answered rc) (res-queries rc) (res-reason rc))
                        (let ((only-h (set-difference (q-lines rh) (q-lines rc) :test #'string=))
                              (only-c (set-difference (q-lines rc) (q-lines rh) :test #'string=)))
                          (format t "  only head: ~{~A~^ | ~}~%  only ccl: ~{~A~^ | ~}~%"
                                  (subseq only-h 0 (min 4 (length only-h)))
                                  (subseq only-c 0 (min 4 (length only-c)))))))))
  (format t "cross-host: ~D programs, ~D with different records~%" total bad))
