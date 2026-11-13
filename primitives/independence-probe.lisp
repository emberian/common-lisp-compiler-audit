; independence-probe.lisp -- which compiled functions run while the logical
; evaluator (ev-fncall-rec-logical with *ev-shortcut-okp* nil) evaluates a call?
;
; SBCL only (uses sb-int:encapsulate).  Run with run-probe.sh.  Every :logic
; function with a body, and its *1* counterpart, is wrapped with a recorder.
; Functions whose symbol lives in the COMMON-LISP package cannot be wrapped
; (package lock) and are listed as such.  The set hit while evaluating four
; fresh baseline functions that call only primitives is the evaluator's own
; infrastructure; anything else hit while a built-in is being evaluated
; logically is compiled code standing in for a logical definition.

(in-package "ACL2")

(defvar *psw-hits* nil)   ; hash table while recording, else nil
(defvar *psw-wrapped* 0)
(defvar *psw-unwrappable* nil)

(defun psw-wrap (sym label)
  (cond ((not (fboundp sym)))
        ((or (macro-function sym) (special-operator-p sym)))
        ((eq (symbol-package sym) (find-package "COMMON-LISP"))
         (push sym *psw-unwrappable*))
        (t (incf *psw-wrapped*)
           (sb-int:encapsulate
            sym 'psw
            (lambda (f &rest args)
              (when *psw-hits* (setf (gethash label *psw-hits*) t))
              (apply f args))))))

(defun psw-probe-tuples (arity u)
  ; arity <= 2 exhaustive; arity 3 a fixed sample of 871 tuples
  (let ((n (length u)) (acc nil))
    (cond ((eql arity 0) (list nil))
          ((eql arity 1) (mapcar #'list u))
          ((eql arity 2) (dolist (x u) (dolist (y u) (push (list x y) acc))) acc)
          (t (loop for k from 0 below (* n n n) by 31
                   do (push (list (nth (floor k (* n n)) u)
                                  (nth (mod (floor k n) n) u)
                                  (nth (mod k n) u))
                            acc))
             acc))))

(defun psw-probe-hits (fn w)
  (let ((h (make-hash-table :test 'equal))
        (u (psw-make-universe)))
    (dolist (args (psw-probe-tuples (length (formals fn w)) u))
      (let ((*psw-hits* h))
        (psw-logical fn args w)))
    (let ((acc nil))
      (maphash (lambda (k v) (declare (ignore v)) (push k acc)) h)
      acc)))

(defun psw-probe-main ()
  (let* ((w (w *the-live-state*))
         (fns (psw-all-function-symbols w))
         (*ld-level* 1)
         (*defeat-slow-alist-action* t)
         (infra (make-hash-table :test 'equal))
         (leaked-by (make-hash-table :test 'equal))
         (nleaky 0) (nprobed 0))
    (psw-install-workarounds)
    (psw-start-watchdog)
    (psw-set-gc :none)
    (dolist (fn fns)
      (when (and (logicp fn w) (not (eq fn 'if)))
        (when (body fn nil w) (psw-wrap fn (list :raw fn)))
        (psw-wrap (*1*-symbol fn) (list :*1* fn))))
    (dolist (b '(psw-b-identity psw-b-let-mv psw-b-rec psw-b-mbe))
      (dolist (k (psw-probe-hits b w)) (setf (gethash k infra) t)))
    (with-open-file (o (psw-path "independence.txt") :direction :output :if-exists :supersede)
      (format o "wrapped ~a functions; not wrappable (COMMON-LISP package): ~a~%"
              *psw-wrapped* (length *psw-unwrappable*))
      (format o "unwrappable: ") (psw-print (sort (copy-list *psw-unwrappable*) #'string<) o)
      (terpri o)
      (format o "evaluator infrastructure (hit while evaluating the baselines): ")
      (let ((acc nil)) (maphash (lambda (k v) (declare (ignore v)) (push k acc)) infra)
        (psw-print acc o))
      (terpri o)
      (dolist (fn fns)
        (when (and (not (psw-exclusion-reason fn w)) (not (psw-exclusion-reason2 fn w))
                   (not (psw-control-p fn))
                   (not (member fn '(psw-b-identity psw-b-let-mv psw-b-rec psw-b-mbe))))
          (incf nprobed)
          (let ((leaks (remove-if (lambda (k) (gethash k infra)) (psw-probe-hits fn w))))
            (when leaks
              (incf nleaky)
              (format o "LEAK ") (psw-print fn o) (format o " ") (psw-print leaks o) (terpri o)
              (dolist (k leaks) (push fn (gethash k leaked-by)))))))
      (format o "probed ~a functions; ~a ran compiled non-infrastructure code during logical evaluation~%"
              nprobed nleaky)
      (let ((acc nil))
        (maphash (lambda (k v) (push (cons (length v) k) acc)) leaked-by)
        (dolist (p (sort acc #'> :key #'car))
          (format o "COMPILED-CODE-RUN ~a callers: " (car p)) (psw-print (cdr p) o) (terpri o))))
    (psw-set-gc t)
    (format t "~&@PSW probe done~%")))
