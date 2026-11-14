(in-package "ACL2")
(defstub my-h (x) t)
(defun my-h1 (x) (declare (xargs :guard t)) (cons 1 x))
(defun my-h2 (x) (declare (xargs :guard t)) (cons 2 x))
(defun my-u (x) (declare (xargs :guard t)) (my-h x))

(make-event
 (let ((badge '(APPLY$-BADGE 1 1 . T)))
   `(encapsulate ()
      ,@(defwarrant-events 'my-u '(x) badge)
      (table badge-table
             :badge-userfn-structure
             (put-badge-userfn-structure-tuple-in-alist
              (make-badge-userfn-structure-tuple 'my-u T ',badge)
              (cdr (assoc :badge-userfn-structure
                          (table-alist 'badge-table world)))
              'defwarrant)
             :put)
      (defattach ,(warrant-name 'my-u) true-apply$-warrant))))

(defun my-caller (x) (declare (xargs :guard t)) (apply$ 'my-u (list x)))
(defattach my-h my-h1)
(memoize 'my-caller :aokp t)
(my-caller 10)
(defattach my-h my-h2)
(my-caller 10)
(my-u 10)
