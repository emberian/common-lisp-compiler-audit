(in-package "ACL2")

(cw "~%=== H28 ABSTRACT STOBJ INTERRUPTED UPDATE ORIGINAL ===~%")
(defstobj const28$c (const28-fld$c :type bit :initially 0))
(defstub stop28 () nil)
(defun change28-fld$c (const28$c)
  (declare (xargs :stobjs const28$c))
  (let ((const28$c (update-const28-fld$c 1 const28$c)))
    (prog2$ (stop28)
            (update-const28-fld$c 0 const28$c))))
(defun get28-fld$c (const28$c)
  (declare (xargs :stobjs const28$c))
  (const28-fld$c const28$c))
(defun const28$ap (const28$a)
  (declare (xargs :guard t))
  (equal const28$a 0))
(defun change28-fld$a (const28$a)
  (declare (xargs :guard t) (ignore const28$a))
  0)
(defun get28-fld$a (const28$a)
  (declare (xargs :guard t) (ignore const28$a))
  0)
(defun create28-const$a ()
  (declare (xargs :guard t))
  0)
(defun-nx const28-corr (const28$c const28$a)
  (and (equal const28$a 0) (equal const28$c '(0))))
(in-theory (disable (const28-corr) (change28-fld$c)))
(defthm create28{correspondence}
  (const28-corr (create-const28$c) (create28-const$a))
  :rule-classes nil)
(defthm create28{preserved}
  (const28$ap (create28-const$a))
  :rule-classes nil)
(defthm get28{correspondence}
  (implies (const28-corr const28$c const28)
           (equal (get28-fld$c const28$c) (get28-fld$a const28)))
  :rule-classes nil)
(defthm change28{correspondence}
  (implies (const28-corr const28$c const28)
           (const28-corr (change28-fld$c const28$c)
                         (change28-fld$a const28)))
  :rule-classes nil)
(defthm change28{preserved}
  (implies (const28$ap const28)
           (const28$ap (change28-fld$a const28)))
  :rule-classes nil)
(defabsstobj const28
  :foundation const28$c
  :recognizer (const28p :logic const28$ap :exec const28$cp)
  :creator (create28 :logic create28-const$a :exec create-const28$c)
  :corr-fn const28-corr
  :exports ((get28 :logic get28-fld$a :exec get28-fld$c)
            (change28 :logic change28-fld$a :exec change28-fld$c)))
(cw "~%=== H28 CONTROL: SAME NONATOMIC EXPORT WITH :PROTECT T ===~%")
(defabsstobj const28
  :foundation const28$c
  :recognizer (const28p :logic const28$ap :exec const28$cp)
  :creator (create28 :logic create28-const$a :exec create-const28$c)
  :corr-fn const28-corr
  :exports ((get28 :logic get28-fld$a :exec get28-fld$c)
            (change28 :logic change28-fld$a :exec change28-fld$c
                      :protect t)))

(cw "~%=== H29 EXPORTED UPDATER IN DERIVED GUARD ===~%")
(defstobj const29$c (const29-fld$c :type bit :initially 0))
(defun change29-fld$c (const29$c)
  (declare (xargs :stobjs const29$c))
  (update-const29-fld$c 0 const29$c))
(defun get29-fld$c (const29$c)
  (declare (xargs :stobjs const29$c))
  (const29-fld$c const29$c))
(defun const29$ap (x) (declare (xargs :guard t)) (equal x 0))
(defun change29-fld$a (x) (declare (xargs :guard t) (ignore x)) 0)
(defun create29$a () (declare (xargs :guard t)) 0)
(defun-nx const29-corr (const29$c const29$a)
  (and (equal const29$a 0) (equal const29$c '(0))))
(defun get29-fld$a (const29$a)
  (declare (xargs :guard (equal (change29-fld$a const29$a) 0)))
  (declare (ignore const29$a))
  0)
(defthm create29{correspondence}
  (const29-corr (create-const29$c) (create29$a)) :rule-classes nil)
(defthm create29{preserved} (const29$ap (create29$a)) :rule-classes nil)
(defthm change29{correspondence}
  (implies (const29-corr const29$c const29)
           (const29-corr (change29-fld$c const29$c)
                         (change29-fld$a const29)))
  :rule-classes nil)
(defthm change29{preserved}
  (implies (const29$ap const29) (const29$ap (change29-fld$a const29)))
  :rule-classes nil)
(defthm get29{correspondence}
  (implies (and (const29-corr const29$c const29)
                (equal (change29-fld$a const29) 0))
           (equal (get29-fld$c const29$c) (get29-fld$a const29)))
  :rule-classes nil)
(defabsstobj const29
  :foundation const29$c
  :recognizer (const29p :logic const29$ap :exec const29$cp)
  :creator (create29 :logic create29$a :exec create-const29$c)
  :corr-fn const29-corr
  :exports ((change29 :logic change29-fld$a :exec change29-fld$c)
            (get29 :logic get29-fld$a :exec get29-fld$c)))

(cw "~%=== H30 NONATOMIC UPDATES THROUGH CONGRUENT UPDATER ===~%")
(defstobj const30$c2 (const30-fld$c2 :type bit :initially 0)
  :congruent-to const28$c)
(defstub stop30 () nil)
(defun change30-fld$c (const28$c)
  (declare (xargs :stobjs const28$c))
  (let ((const28$c (update-const30-fld$c2 1 const28$c)))
    (prog2$ (stop30)
            (update-const30-fld$c2 0 const28$c))))
(value-triple
 (list (fn-stobj-updates-p 'const28$c 'change30-fld$c (w state))
       (unprotected-export-p 'const28$c 'change30-fld$c (w state))))

(quit)
