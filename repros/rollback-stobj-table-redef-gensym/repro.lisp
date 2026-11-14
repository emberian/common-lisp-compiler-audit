;; WRB-R3: maybe-push-undo-stack (interface-raw.lisp:3651) unconditionally pushes
;; `(remhash ',name *current-stobj-gensym-ht*)` when installing a defstobj/defabsstobj,
;; instead of saving and restoring any prior gensym for `name`.
;;
;; Redefining KID under (redef!) and undoing via :u reverts (w state) to the
;; pre-redefinition world where KID was NEVER undone, yet deletes KID from
;; *current-stobj-gensym-ht* — silently wiping live stobj-table entries for KID!
(in-package "ACL2")

(defstobj parent (tbl :type (stobj-table)))
(defstobj kid (fld :type integer :initially 0))

(defun put-kid (val parent)
  (declare (xargs :stobjs parent :guard (integerp val)))
  (stobj-let ((kid (tbl-get 'kid parent (create-kid))))
             (kid)
             (update-fld val kid)
             parent))

(defun get-kid (parent)
  (declare (xargs :stobjs parent :guard t))
  (stobj-let ((kid (tbl-get 'kid parent (create-kid))))
             (val)
             (fld kid)
             val))

(put-kid 99 parent)

(make-event
 (mv-let (erp val state)
   (trans-eval '(list (tbl-keys parent) (get-kid parent) (tbl-count parent))
               'before state t)
   (declare (ignore erp))
   (prog2$
    (cw "@WRB-R3-BEFORE host=~x0 keys-val-count=~x1~%" (@ host-lisp) val)
    (value '(value-triple :before)))))

(redef!)
(defstobj kid (fld :type integer :initially 5))
:u
(redef-)

(make-event
 (mv-let (erp val state)
   (trans-eval '(list (tbl-keys parent) (get-kid parent) (tbl-count parent))
               'after state t)
   (declare (ignore erp))
   (prog2$
    (cw "@WRB-R3-AFTER  host=~x0 keys-val-count=~x1~%" (@ host-lisp) val)
    (value '(value-triple :after)))))

(quit)
