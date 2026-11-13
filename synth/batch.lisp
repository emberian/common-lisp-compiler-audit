;;;; Run a batch of emitted programs in ONE ACL2 process and collect, per program,
;;;; its query records and (SBCL host) the compiler-table coverage of its raw code.

(defparameter *acl2-head* "/Users/ember/dev/acl2-fix/head-worktree/saved_acl2")
(defparameter *acl2-ccl* "/Users/ember/dev/acl2-fix/ccl-worktree/saved_acl2")
(defparameter *cov-hooks* "/Users/ember/dev/compiler-audit/coverage/acl2-sbcl-cov.lisp")
(defparameter *ccl-cov-hooks* "/Users/ember/dev/compiler-audit/coverage/acl2-ccl-cov.lisp")

(defstruct res dir recs valid reason diffs queries answered cov)

(defun sh (fmt &rest args)
  (sb-ext:process-exit-code
   (sb-ext:run-program "/bin/sh" (list "-c" (apply #'format nil fmt args)) :output nil :error nil)))

(defun write-batch-script (path dirs host cov)
  "ACL2 input: each program is admitted, queried, measured and undone."
  (with-open-file (s path :direction :output :if-exists :supersede)
    (when cov
      (format s ":q~%(load ~S)~%(lp)~%" (if (eq host :ccl) *ccl-cov-hooks* *cov-hooks*)))
    (format s "(set-inhibit-output-lst (remove1 'comment *valid-output-names*))~%")
    (loop for d in dirs for i from 0
          do (format s "(deflabel zprog-start)~%(set-cbd ~S)~%" d)
             (when cov (format s ":q~%(ccov:reset)~%(lp)~%"))
             (format s "(cw \"@PROG ~D~~%\")~%" i)
             (when (probe-file (format nil "~Aportcullis.lisp" d))
               (format s "(ld \"portcullis.lisp\")~%"))
             (format s "(ld \"book.lisp\")~%(ld \"queries.lisp\" :ld-error-action :continue)~%")
             (when cov (format s ":q~%(~A ~S)~%(lp)~%" (if (eq host :ccl) "ccov2:dump" "ccov:dump") (format nil "~Acov.~(~A~).sexp" d host)))
             (format s "(cw \"@DONE ~D~~%\")~%(ubt! 'zprog-start)~%" i))
    (format s "(cw \"@BATCHEND~~%\")~%(quit)~%")))

(defun read-cov (path)
  "Coverage keys as strings: T:<transform key> and V:<vop name> (C:<table>:<name> on CCL)."
  (when (probe-file path)
    (let ((d (loop
               (handler-case
                   (return (with-open-file (s path)
                             (let ((*package* (find-package :cl))) (read s))))
                 (sb-int:simple-reader-package-error (c)
                   (make-package (package-error-package c) :use nil))))))
      (let ((*package* (find-package :cl)) (*print-pretty* nil))
        (if (getf d :ccl)
            (loop for (table names) on (getf d :ccl) by #'cddr
                  append (loop for n in names collect (format nil "C:~A:~A" table n)))
            (append (loop for k in (getf d :fired) collect (format nil "T:~S" k))
                    (loop for k in (getf d :emitted) collect (format nil "V:~S" k))))))))

(defun judge (r expected-queries)
  "Fill R's verdict from its records."
  (let* ((recs (res-recs r))
         (g (find-if (lambda (l) (eql 0 (search "@G " l))) recs))
         (c (find-if (lambda (l) (eql 0 (search "@C " l))) recs))
         (qs (remove-if-not (lambda (l) (eql 0 (search "@Q " l))) recs))
         (diffs (remove-if-not (lambda (l) (search ":DIFF" l)) qs)))
    (setf (res-queries r) expected-queries (res-answered r) (length qs) (res-diffs r) diffs
          (res-reason r)
          (cond ((not (member "@END" recs :test #'string=)) :no-end)
                ((not (and g (string= g "@G 0"))) :unverified-or-not-admitted)
                ((not (and c (search ":DIFF" c))) :control-silent)
                (diffs :diff)
                (t nil))
          (res-valid r) (null (res-reason r)))
    r))

(defun run-batch (dirs workdir &key (host :head) (cov t) (timeout 900) (tag "batch"))
  "Run the programs in DIRS (absolute, with trailing slash).  Returns a list of RES,
or :TIMEOUT if the ACL2 process did not reach the end of the batch."
  (let ((script (format nil "~A~A.lisp" workdir tag)) (out (format nil "~A~A.out" workdir tag)))
    (write-batch-script script dirs host cov)
    (sh "nice -n 15 timeout -k 20 ~D ~A < ~A > ~A 2>&1" timeout
        (if (eq host :ccl) *acl2-ccl* *acl2-head*) script out)
    (let ((results (loop for d in dirs collect (make-res :dir d)))
          (cur nil) (ended nil))
      (with-open-file (s out :external-format :latin-1)
        (loop for line = (read-line s nil) while line
              do (let ((at (search "@" line)))
                   (when at
                     (let ((l (string-right-trim '(#\Space #\Return) (subseq line at))))
                       (cond ((eql 0 (search "@PROG " l))
                              (setf cur (nth (parse-integer l :start 6) results)))
                             ((eql 0 (search "@DONE " l)) (setf cur nil))
                             ((eql 0 (search "@BATCHEND" l)) (setf ended t))
                             ((and cur (member (subseq l 0 (min 3 (length l)))
                                               '("@Q " "@G " "@C " "@U " "@EN") :test #'string=))
                              (push l (res-recs cur)))))))))
      (if (not ended)
          :timeout
          (dolist (r results results)
            (setf (res-recs r) (nreverse (res-recs r)))
            (judge r (with-open-file (s (format nil "~Aqueries.lisp" (res-dir r)))
                       (loop for line = (read-line s nil) while line count (search "\"@Q " line))))
            (when cov
              (setf (res-cov r)
                    (read-cov (format nil "~Acov.~(~A~).sexp" (res-dir r) host)))))))))

(defun mentions-df-p (dir)
  (with-open-file (s (format nil "~Abook.lisp" dir))
    (loop for line = (read-line s nil) while line thereis (search "double-float" line))))

(defun run-batch-robust (dirs workdir &rest keys &key (timeout 900) (host :head) &allow-other-keys)
  "As RUN-BATCH; after a timeout or crash each program is rerun alone, and one that
still does not finish is returned with reason :HANG-OR-CRASH.
Known-failure exclusion (finding F13): on CCL a df ftype proclamation outlives
undo, so a program with df functions or df stobj fields poisons the names it
used for every later program of the process.  On CCL such programs get a
process of their own."
  (if (and (eq host :ccl) (cdr dirs) (some #'mentions-df-p dirs))
      (let* ((plain (remove-if #'mentions-df-p dirs))
             (rp (and plain (apply #'run-batch-robust plain workdir keys))))
        (loop for d in dirs
              collect (if (mentions-df-p d)
                          (first (apply #'run-batch-robust (list d) workdir keys))
                          (pop rp))))
      (let ((r (apply #'run-batch dirs workdir keys)))
        (if (listp r)
            r
            (loop for d in dirs
                  collect (let ((one (apply #'run-batch (list d) workdir
                                            :timeout (max 120 (floor timeout 4)) :tag "single" keys)))
                            (if (listp one)
                                (first one)
                                (make-res :dir d :valid nil :reason :hang-or-crash))))))))

(defun q-lines (r) (remove-if-not (lambda (l) (eql 0 (search "@Q " l))) (res-recs r)))
