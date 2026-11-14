;; WRB-R2: Rolling back a defstobj/defabsstobj restores *user-stobj-alist*
;; (interface-raw.lisp:7330) WITHOUT restoring *non-executable-user-stobj-lst*
;; (and remove-global-stobj / add-global-stobj mutate both globals with zero
;; *undo-stack* entries).
;;
;; After (encapsulate () (local (defstobj tmp dummy)) (local (add-global-stobj 'st state))),
;; ST is in NEITHER *user-stobj-alist* NOR *non-executable-user-stobj-lst*,
;; triggering a raw Common Lisp CL:ASSERT failure in add-global-stobj!
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
              (value '(value-triple :readded-st-locally))))))

(cw "@WRB-R2-CALLING-ADD-GLOBAL-STOBJ host=~x0~%" (@ host-lisp))
(add-global-stobj 'st state)
(quit)
