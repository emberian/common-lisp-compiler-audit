(in-package "ACL2")

(defstobj kid fld)
(defstobj mom$c (kid-c :type kid))

(defun mom$ap (x) (declare (xargs :guard t)) (mom$cp x))
(defun create-mom$a () (declare (xargs :guard t)) '((nil)))
(defun get-kid$a (mom) (declare (xargs :guard (mom$ap mom))) (nth 0 mom))
(defun set-kid$a (kid mom) (declare (xargs :guard (and (kidp kid) (mom$ap mom)))) (update-nth 0 kid mom))
(defun-nx mom$corr (mom$c mom) (and (mom$cp mom$c) (equal mom$c mom)))

(defthm create-mom-corr
  (mom$corr (create-mom$c) (create-mom$a))
  :rule-classes nil)
(defthm create-mom-pres
  (mom$ap (create-mom$a))
  :rule-classes nil)
(defthm get-kid-corr
  (implies (and (mom$corr mom$c mom) (mom$ap mom))
           (equal (kid-c mom$c) (get-kid$a mom)))
  :rule-classes nil)
(defthm set-kid-corr
  (implies (and (mom$corr mom$c mom)
                (kidp kid)
                (mom$ap mom))
           (mom$corr (update-kid-c kid mom$c)
                     (set-kid$a kid mom)))
  :rule-classes nil)
(defthm set-kid-pres
  (implies (and (kidp kid) (mom$ap mom))
           (mom$ap (set-kid$a kid mom)))
  :rule-classes nil)

(defabsstobj mom
  :foundation mom$c
  :recognizer (momp :logic mom$ap :exec mom$cp)
  :creator (create-mom :logic create-mom$a :exec create-mom$c
                       :correspondence create-mom-corr
                       :preserved create-mom-pres)
  :corr-fn mom$corr
  :exports ((mom-kid :logic get-kid$a :exec kid-c
                     :updater update-mom-kid
                     :correspondence get-kid-corr)
            (update-mom-kid :logic set-kid$a :exec update-kid-c
                            :correspondence set-kid-corr
                            :preserved set-kid-pres)))

(defun mom-set-fld (val mom)
  (declare (xargs :stobjs mom :guard t))
  (stobj-let ((kid (mom-kid mom)))
             (kid)
             (update-fld val kid)
             mom))

(mom-set-fld 42 mom)
