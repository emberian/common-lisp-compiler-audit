;; Reproducer for SATlink parser prefix / exit-status / unsat-claim soundness gap
;; Source: books/centaur/satlink/top.lisp:528-623, 751, 885-907
(in-package "ACL2")

;; Exact prefix matching logic from satlink-handle-line (top.lisp:550-555)
(defun strprefixp (prefix str)
  (declare (xargs :guard (and (stringp prefix) (stringp str))))
  (let ((plen (length prefix))
        (slen (length str)))
    (and (<= plen slen)
         (equal (subseq str 0 plen) prefix))))

(defun satlink-parse-lines-mini (lines saw-sat saw-unsat saw-unk saw-zero)
  (declare (xargs :guard (string-listp lines)))
  (if (atom lines)
      (cond ((and saw-unsat (not saw-sat) (not saw-unk) (not saw-zero)) :unsat)
            ((and saw-sat (not saw-unsat) (not saw-unk) saw-zero) :sat)
            (t :failed))
    (let* ((line (car lines))
           (len (length line)))
      (if (and (>= len 2) (eql (char line 0) #\s) (eql (char line 1) #\Space))
          (cond ((strprefixp "s SATISFIABLE" line)
                 (satlink-parse-lines-mini (cdr lines) t saw-unsat saw-unk saw-zero))
                ((strprefixp "s UNSATISFIABLE" line)
                 (satlink-parse-lines-mini (cdr lines) saw-sat t saw-unk saw-zero))
                ((strprefixp "s UNKNOWN" line)
                 (satlink-parse-lines-mini (cdr lines) saw-sat saw-unsat t saw-zero))
                (t (satlink-parse-lines-mini (cdr lines) saw-sat saw-unsat saw-unk saw-zero)))
        (satlink-parse-lines-mini (cdr lines) saw-sat saw-unsat saw-unk saw-zero)))))

;; Exact exit-code check from top.lisp:751: ONLY status == 127 fails!
(defun satlink-run-check (exit-status lines)
  (declare (xargs :guard (and (natp exit-status) (string-listp lines))))
  (if (eql exit-status 127)
      :failed
    (satlink-parse-lines-mini lines nil nil nil nil)))

;; Both corrupted prefix and segfault exit code 139 parse as :unsat
(defthm parser-and-exitcode-bugs
  (and (equal (satlink-run-check 0 '("s UNSATISFIABLE_ERROR_OR_NOT")) :unsat)
       (equal (satlink-run-check 139 '("s UNSATISFIABLE")) :unsat)
       (equal (satlink-run-check 1 '("s UNSATISFIABLE usage error" "s TIMEOUT")) :unsat))
  :rule-classes nil)

;; Mirror of satlink-run-fn-unsat-claim (top.lisp:885-907) with custom cmdline
;; Notice the axiom quantifies over ALL configs where (not lrat-check), including
;; untrusted cmdline strings like "echo s UNSATISFIABLE #".
(partial-encapsulate
 (((sat-run-fn-model * * *) => (mv * * *)))
 nil
 (local (defun sat-run-fn-model (cfg formula env)
          (declare (ignore cfg formula))
          (mv :failed env nil)))
 (defthm sat-run-fn-model-unsat-claim
   (implies (and (not (equal cfg :lrat))
                 (equal formula '((1 . 1))))
            ;; In top.lisp:897-907: (implies (equal (eval-formula formula env) 1)
            ;;                                (not (equal status :unsat)))
            (not (equal (mv-nth 0 (sat-run-fn-model cfg formula env)) :unsat)))))

;; Under raw/tshell execution with cmdline="echo s UNSATISFIABLE #",
;; the solver returns :unsat on the satisfiable formula '((1 . 1)), contradicting the axiom.
(value-triple
 (cw "~%@CHECK corrupted-prefix=~x0 segfault-139=~x1~%"
     (satlink-run-check 0 '("s UNSATISFIABLE_ERROR_OR_NOT"))
     (satlink-run-check 139 '("s UNSATISFIABLE"))))
