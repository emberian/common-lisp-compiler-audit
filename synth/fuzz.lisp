;;; Coverage-guided synthesis loop.
;;;
;;; Feedback is the set of SBCL deftransforms fired and VOPs emitted while the
;;; SBCL-hosted ACL2 image compiles a program's -OPT twins (and loop$/lambda$
;;; objects), measured by coverage/acl2-sbcl-cov.lisp inside that image.
;;; Each round builds a batch of candidates (fresh programs with swarm-selected
;;; kinds, features and context, or IR mutants of corpus members), runs the
;;; batch in one ACL2 process (admit, query REF against OPT, dump coverage,
;;; undo), and keeps every valid candidate that reached a table entry not seen
;;; before.  A candidate that is not admitted, has an unverified OPT twin, a
;;; :DIFF, a silent control or does not finish is saved under findings/.
;;;
;;; Usage: sbcl --script fuzz.lisp WORKDIR/ ROUNDS BATCH NFNS SEED
;;; State: WORKDIR/corpus/*.sexp, WORKDIR/seen.sexp, WORKDIR/log.txt (resumable).
(load (merge-pathnames "lib.lisp" (directory-namestring *load-truename*)))
(in-package :zs)

(defvar *seen* (make-hash-table :test 'equal))
(defvar *corpus* nil)

(defun load-state (w)
  (let ((seen (format nil "~Aseen.sexp" w)))
    (when (probe-file seen)
      (with-open-file (s seen) (dolist (k (read s)) (setf (gethash k *seen*) t)))))
  (dolist (f (directory (format nil "~Acorpus/*.sexp" w)))
    (push (load-prog f) *corpus*)))

(defun save-seen (w)
  (with-open-file (s (format nil "~Aseen.sexp" w) :direction :output :if-exists :supersede)
    (prin1 (loop for k being the hash-keys of *seen* collect k) s)))

(defun count-seen (prefix)
  (loop for k being the hash-keys of *seen* count (eql 0 (search prefix k))))

(let* ((args (last sb-ext:*posix-argv* 5))
       (w (first args)) (rounds (parse-integer (second args))) (batch (parse-integer (third args)))
       (nfns (parse-integer (fourth args))) (seed (parse-integer (fifth args)))
       (master (sb-ext:seed-random-state seed))
       (serial 0))
  (ensure-directories-exist (format nil "~Acorpus/" w))
  (ensure-directories-exist (format nil "~Afindings/" w))
  (load-state w)
  (setf serial (length *corpus*))
  (dotimes (round rounds)
    (let ((cands nil) (dirs nil) (fresh 0))
      (dotimes (i batch)
        (let* ((sub (random (ash 1 40) master))
               (p (or (and *corpus* (< (random 100 master) 70)
                           (progn (setf *rs* (sb-ext:seed-random-state sub))
                                  (loop repeat 12
                                        thereis (handler-case (mutate-prog (pick *corpus*) *corpus*)
                                                  (error () nil)))))
                      (progn (incf fresh) (make-prog sub nfns))))
               (dir (format nil "~Ab/~D/" w i)))
          (ensure-directories-exist dir)
          (dolist (f (directory (format nil "~A*.*" dir))) (delete-file f))
          (emit-prog p dir)
          (push p cands) (push dir dirs)))
      (setf cands (nreverse cands) dirs (nreverse dirs))
      (let ((results (run-batch-robust dirs w :host :head :cov t :timeout (* 45 batch)))
            (kept 0) (bad 0) (answered 0) (asked 0))
        (loop for r in results for p in cands
              do (incf answered (or (res-answered r) 0)) (incf asked (or (res-queries r) 0))
                 (cond ((not (res-valid r))
                        (incf bad)
                        (let ((fd (format nil "~Afindings/r~D-~D-~(~A~)/" w round (position r results)
                                          (res-reason r))))
                          (ensure-directories-exist fd)
                          (sh "cp ~A*.lisp ~Aprog.sexp ~Amanifest.txt ~A" (res-dir r) (res-dir r)
                              (res-dir r) fd)))
                       (t (let ((new (remove-if (lambda (k) (gethash k *seen*)) (res-cov r))))
                            (when new
                              (dolist (k new) (setf (gethash k *seen*) t))
                              (incf kept) (push p *corpus*)
                              (save-prog p (format nil "~Acorpus/~5,'0D.sexp" w (incf serial))))))))
        (save-seen w)
        (with-open-file (s (format nil "~Alog.txt" w) :direction :output :if-exists :append
                                                       :if-does-not-exist :create)
          (format s "round ~D batch ~D fresh ~D kept ~D invalid ~D queries ~D/~D corpus ~D transforms ~D vops ~D~%"
                  round batch fresh kept bad answered asked (length *corpus*)
                  (count-seen "T:") (count-seen "V:")))))))
