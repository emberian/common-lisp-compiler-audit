(in-package "ACL2")

(defstobj kid  (fld  :type integer :initially 0))
(defstobj kid2 (fld2 :type integer :initially 0) :congruent-to kid)
(defstobj parent (k1 :type kid) (k2 :type kid))

(defun swap-k1 (parent kid)
  (declare (xargs :stobjs (parent kid)))
  (stobj-let ((kid2 (k1 parent)))
             (kid2 kid)
             (swap-stobjs kid2 kid)
             (mv parent kid)))

(defun swap-k2 (parent kid)
  (declare (xargs :stobjs (parent kid)))
  (stobj-let ((kid2 (k2 parent)))
             (kid2 kid)
             (swap-stobjs kid2 kid)
             (mv parent kid)))

(defun set-k1 (v parent)
  (declare (xargs :stobjs parent :guard (integerp v)))
  (stobj-let ((kid (k1 parent)))
             (kid)
             (update-fld v kid)
             parent))

(defun set-k2 (v parent)
  (declare (xargs :stobjs parent :guard (integerp v)))
  (stobj-let ((kid (k2 parent)))
             (kid)
             (update-fld v kid)
             parent))

(defun get-k1 (parent)
  (declare (xargs :stobjs parent))
  (stobj-let ((kid (k1 parent)))
             (v)
             (fld kid)
             v))

(defstobj tmp dummy)
(swap-k1 parent kid)
:u
(swap-k2 parent kid)

(set-k1 1 parent)
(set-k2 2 parent)
(get-k1 parent)
