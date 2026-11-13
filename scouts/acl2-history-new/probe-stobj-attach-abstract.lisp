(in-package "ACL2")
; NOTE-8-7 abstract-stobj route: correlation depends on an attachable predicate.
(defstub pa (x) nil)
(defstobj ast$c (fld$c :initially nil))
(defun update-fld-restr$c (val ast$c)
  (declare (xargs :stobjs ast$c))
  (if (or (not val) (pa val)) (update-fld$c val ast$c) ast$c))
(defun update-fld$a (val ast$a)
  (declare (xargs :guard t))
  (if (or (not val) (pa val)) val ast$a))
(defun fld$a (ast$a)
  (declare (xargs :guard t))
  (if (pa ast$a) ast$a nil))
(defun corra (ast$c x)
  (declare (xargs :stobjs ast$c))
  (and (or (not x) (pa x)) (equal x (fld$c ast$c))))
(defun ast$ap (x) (declare (xargs :guard t) (ignore x)) t)
(defun create-ast$a () (declare (xargs :guard t)) nil)
(in-theory (disable (:e fld$a)))
(defthm create-ast{correspondence}
  (corra (create-ast$c) (create-ast$a)) :rule-classes nil)
(defthm create-ast{preserved}
  (ast$ap (create-ast$a)) :rule-classes nil)
(defthm fld{correspondence}
  (implies (corra ast$c ast)
           (equal (fld$c ast$c) (fld$a ast)))
  :rule-classes nil)
(defthm update-fld{correspondence}
  (implies (corra ast$c ast)
           (corra (update-fld-restr$c val ast$c)
                  (update-fld$a val ast)))
  :rule-classes nil)
(defthm update-fld{preserved}
  (implies (ast$ap ast) (ast$ap (update-fld$a val ast)))
  :rule-classes nil)
(defabsstobj ast
  :foundation ast$c
  :recognizer (astp :logic ast$ap :exec ast$cp)
  :creator (create-ast :logic create-ast$a :exec create-ast$c)
  :corr-fn corra
  :exports ((fld :logic fld$a :exec fld$c)
            (update-fld :logic update-fld$a :exec update-fld-restr$c)))
(defattach pa integerp)
(quit)
