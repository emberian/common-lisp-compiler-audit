(in-package "ACL2")

(defstobj st (fld :type integer :initially 42))

(make-event
 (er-progn (remove-global-stobj 'st state)
           (value '(value-triple :removed-st))))

(encapsulate ()
  (local (defstobj tmp dummy))
  (local
   (make-event
    (er-progn (add-global-stobj 'st state)
              (value '(value-triple :readded-st))))))

;; Now st is in NEITHER *user-stobj-alist* NOR *non-executable-user-stobj-lst*!
;; 1) What does top-level (fld st) do?
(fld st)

;; 2) What does (add-global-stobj 'st state) do?
(add-global-stobj 'st state)
