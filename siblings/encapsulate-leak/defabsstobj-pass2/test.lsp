(in-package "ACL2")

; ISSUE B18 (ACL2 developers, fixed before v8.8): a signature function used as
; the :EXEC of a defabsstobj export, with LOCAL supporting {correspondence}/
; {preserved} theorems.  defabsstobj-fn1 (other-events.lisp ~24993) skips the
; "missing events" check when ld-skip-proofsp = include-book, which is exactly
; encapsulate pass 2 -- so the export used to be installed in pass 2 without the
; (now-absent, local) theorems, and a later (defattach h ...) made raw execution
; of the export diverge from its :LOGIC, provable to NIL via a metafunction.
; This is the coordinator's quoted-lambda hypothesis realized for defabsstobj:
; the leak routes through the :EXEC slot, which bogus-exported-compliants does
; not inspect.  This TREE is post-fix, so pass 2 MUST reject the encapsulate.
;
; Source of the reproducer: books/system/tests/defabsstobj-pass2-constrained-exec.lisp
; (verbatim encapsulate; the must-fail wrapper and std/testing book removed so it
; runs under a bare image).

(defstobj st$c (fld$c :type integer :initially 0))
(defun st$ap (x) (declare (xargs :guard t) (ignore x)) t)
(defun create-st$a () (declare (xargs :guard t)) 0)
(defun fld$a (x) (declare (xargs :guard t)) (ifix x))
(defun update-fld$a (v x) (declare (xargs :guard (integerp v)) (ignore x)) v)
(defun st$corr (st$c x) (declare (xargs :stobjs st$c :guard t)) (equal (fld$c st$c) (ifix x)))

(make-event
 (mv-let (erp val state)
   (encapsulate (((h st$c) => * :formals (st$c) :guard t))
     (local (defun h (st$c) (declare (xargs :stobjs st$c :guard t)) (fld$c st$c)))
     (local (defthm create-st{correspondence} (st$corr (create-st$c) (create-st$a)) :rule-classes nil))
     (local (defthm create-st{preserved} (st$ap (create-st$a)) :rule-classes nil))
     (local (defthm fld{correspondence} (implies (st$corr st$c st) (equal (h st$c) (fld$a st))) :rule-classes nil))
     (local (defthm update-fld{correspondence}
              (implies (and (st$corr st$c st) (integerp v)) (st$corr (update-fld$c v st$c) (update-fld$a v st)))
              :rule-classes nil))
     (local (defthm update-fld{preserved} (implies (and (st$ap st) (integerp v)) (st$ap (update-fld$a v st))) :rule-classes nil))
     (defabsstobj st :foundation st$c
       :recognizer (stp :logic st$ap :exec st$cp)
       :creator (create-st :logic create-st$a :exec create-st$c)
       :corr-fn st$corr
       :exports ((fld :logic fld$a :exec h) (update-fld :logic update-fld$a :exec update-fld$c))))
   (declare (ignore val))
   (value `(value-triple (list :b18a-encapsulate-erp ,(if erp t nil))))))

; The defabsstobj export must NOT have been installed (fix rejects in pass 2).
(value-triple
 (list :stp-is-function (and (function-symbolp 'stp (w state)) t)
       :fld-is-function (and (function-symbolp 'fld (w state)) t)
       :h-is-function   (and (function-symbolp 'h (w state)) t)))
(quit)
