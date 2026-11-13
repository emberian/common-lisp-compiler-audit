;;; Emit every program of a fuzz corpus to its own directory (to replay the
;;; corpus on another host, through measure.lisp or run-matrix.sh PREGEN=1).
;;; Usage: sbcl --script emit-corpus.lisp CORPUS-DIR/ OUTROOT/     prints the directories
(load (merge-pathnames "lib.lisp" (directory-namestring *load-truename*)))
(in-package :zs)
(let* ((argv (cdr sb-ext:*posix-argv*)) (corpus (first argv)) (out (second argv)))
  (dolist (f (sort (directory (format nil "~A*.sexp" corpus)) #'string< :key #'namestring))
    (let ((dir (format nil "~A~A/" out (pathname-name f))))
      (ensure-directories-exist dir)
      (emit-prog (load-prog f) dir)
      (format t "~A~%" dir))))
