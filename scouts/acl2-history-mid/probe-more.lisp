(in-package "ACL2")

(cw "~%=== H4C EXPLICIT SAFE-MODE VALUE-TRIPLE ===~%")
(value-triple (list (mbe :logic nil :exec t)) :safe-mode t)
(defmacro mbe-list-mac-h4c () '(list (mbe :logic nil :exec t)))
(value-triple (mbe-list-mac-h4c) :safe-mode t)

(cw "~%=== H15R MV-LET DROPS UPDATED STOBJ, CORRECTED ===~%")
(defstobj s15r fld15r)
(defun drop-mv-let-h15r (s15r)
  (declare (xargs :stobjs s15r))
  (let ((s15r (update-fld15r 1 s15r)))
    (mv-let (v s15r)
            (mv 0 s15r)
            (declare (ignore v))
            nil)))

(cw "~%=== H16R NON-CHILD PRODUCER NOT RETURNED, CORRECTED ===~%")
(defstobj kid16r fld16r)
(defstobj other16r ofld16r)
(defstobj other16cr ofld16cr :congruent-to other16r)
(defstobj mom16r (kid16r-field :type kid16r))
(defun bad-nonchild-h16r (mom16r other16r)
  (declare (xargs :stobjs (mom16r other16r)))
  (stobj-let
   ((kid16r (kid16r-field mom16r)))
   (kid16r other16r)
   (let* ((kid16r (update-fld16r 1 kid16r))
          (other16r (update-ofld16r 2 other16r)))
     (mv kid16r other16r))
   mom16r))
(defun bad-nonchild-congruent-h16r (mom16r other16cr)
  (declare (xargs :stobjs (mom16r other16cr)))
  (stobj-let
   ((kid16r (kid16r-field mom16r)))
   (kid16r other16cr)
   (let* ((kid16r (update-fld16r 1 kid16r))
          (other16cr (update-ofld16cr 2 other16cr)))
     (mv kid16r other16cr))
   mom16r))

(cw "~%=== H20 MBE INSIDE FOR LOOP$ IN AN UNVERIFIED LOGIC FUNCTION ===~%")
(defun f-loop-mbe-h20 ()
  (loop$ for x in '(nil) collect (mbe :logic nil :exec t)))
(value-triple (f-loop-mbe-h20))
(value-triple (f-loop-mbe-h20) :safe-mode t)
(defthm f-loop-mbe-logical-h20
  (equal (f-loop-mbe-h20) '(nil))
  :rule-classes nil)
(defthm f-loop-mbe-exec-h20
  (equal (f-loop-mbe-h20) '(t))
  :rule-classes nil)

(cw "~%=== H21 MBE INSIDE DO LOOP$ ===~%")
(defun f-do-loop-mbe-h21 ()
  (loop$ with ans = nil
         for x in '(nil)
         do (progn (setq ans (mbe :logic nil :exec t))
                   (return ans))))
(value-triple (f-do-loop-mbe-h21))
(value-triple (f-do-loop-mbe-h21) :safe-mode t)

(cw "~%=== H22 ORDINARY LAMBDA IN PATTERNED CONGRUENCE ===~%")
(defun e-h22 (x y) (equal (fix x) (fix y)))
(defequiv e-h22)
(defun f-h22 (x) (if (consp x) 1 0))
(defthm same-var-lambda-congruence-h22
  (implies (e-h22 x x)
           (equal ((lambda (u) (f-h22 u)) x)
                  ((lambda (u) (f-h22 u)) x)))
  :rule-classes :congruence)

(cw "~%=== H23 CURRENT ELIM HITTABILITY REGRESSION FROM SOURCE COMMENT ===~%")
(defun d1-h23 (x) x)
(defun mk-h23 (y) (if y t nil))
(defthm gen-rule-h23
  (implies (equal x t) (equal (d1-h23 x) t))
  :rule-classes :generalize)
(defthm mk-elim-h23
  (iff (mk-h23 (d1-h23 x)) x)
  :rule-classes :elim)
(defthm bad-h23
  (implies (d1-h23 x) (equal (d1-h23 x) t))
  :hints (("Goal" :in-theory (disable d1-h23)))
  :rule-classes nil)
(defthm nil-proved-h23
  nil
  :hints (("Goal" :use ((:instance bad-h23 (x 5)))))
  :rule-classes nil)

(quit)
