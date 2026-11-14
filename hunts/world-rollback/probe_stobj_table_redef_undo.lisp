(in-package "ACL2")

(defstobj parent (tbl :type (stobj-table)))
(defstobj kid fld)

(defun put-kid (val parent)
  (declare (xargs :stobjs parent))
  (stobj-let ((kid (tbl-get 'kid parent (create-kid))))
             (kid)
             (update-fld val kid)
             parent))

(defun get-kid (parent)
  (declare (xargs :stobjs parent))
  (stobj-let ((kid (tbl-get 'kid parent (create-kid))))
             (val)
             (fld kid)
             val))

;; Populate 'kid -> #(99) in parent's stobj-table:
(put-kid 99 parent)

(make-event
 (mv-let (erp val state)
   (trans-eval '(list (tbl-keys parent) (get-kid parent)) 'before state t)
   (prog2$
    (cw "~%@R BEFORE-REDEF keys-and-val=~x0 (erp=~x1)~%" val erp)
    (value '(value-triple :before)))))

;; Redefine KID under redef! and then undo the redefinition via :u.
;; Logically we are back in the exact world after (put-kid 99 parent), where
;; KID was NEVER undone! Yet undo-trip ran (remhash 'kid *current-stobj-gensym-ht*),
;; wiping KID's gensym and orphaning #(99) in parent's hash-table!
(redef!)
(defstobj kid fld2)
:u
(redef-)

(make-event
 (mv-let (erp val state)
   (trans-eval '(list (tbl-keys parent) (get-kid parent) (tbl-count parent))
               'after state t)
   (prog2$
    (cw "~%@R AFTER-REDEF-UNDO keys-val-count=~x0 (erp=~x1)~%" val erp)
    (value '(value-triple :after)))))
