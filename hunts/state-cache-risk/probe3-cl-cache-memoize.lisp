(in-package "ACL2")

(defun my-caller (x)
  (declare (xargs :guard t))
  (apply$ (cons 'LAMBDA '((Z) (MY-U Z))) (list x)))

(memoize 'my-caller)

(encapsulate ()
  (local (defun my-u (z) (declare (xargs :guard t) (ignore z)) 42))
  (local
   (make-event
    (let ((badge '(APPLY$-BADGE 1 1 . T)))
      `(encapsulate ()
         ,@(defwarrant-events 'my-u '(z) badge)
         (table badge-table
                :badge-userfn-structure
                (put-badge-userfn-structure-tuple-in-alist
                 (make-badge-userfn-structure-tuple 'my-u T ',badge)
                 (cdr (assoc :badge-userfn-structure
                             (table-alist 'badge-table world)))
                 'defwarrant)
                :put)
         (defattach ,(warrant-name 'my-u) true-apply$-warrant)))))
  (local
   (make-event
    (let* ((v1 (my-caller 10))
           (v2 (my-caller 10)))
      (declare (ignore v1 v2))
      '(value-triple nil))))
  (defthm thm-42
    (equal (my-caller 10) 42)
    :hints (("Goal" :in-theory (disable my-caller)))))

(value-triple (clear-memoize-tables))

(encapsulate ()
  (local (defun my-u (z) (declare (xargs :guard t) (ignore z)) 99))
  (local
   (make-event
    (let ((badge '(APPLY$-BADGE 1 1 . T)))
      `(encapsulate ()
         ,@(defwarrant-events 'my-u '(z) badge)
         (table badge-table
                :badge-userfn-structure
                (put-badge-userfn-structure-tuple-in-alist
                 (make-badge-userfn-structure-tuple 'my-u T ',badge)
                 (cdr (assoc :badge-userfn-structure
                             (table-alist 'badge-table world)))
                 'defwarrant)
                :put)
         (defattach ,(warrant-name 'my-u) true-apply$-warrant)))))
  (local
   (make-event
    (let* ((v1 (my-caller 10))
           (v2 (my-caller 10)))
      (declare (ignore v1 v2))
      '(value-triple nil))))
  (defthm thm-99
    (equal (my-caller 10) 99)
    :hints (("Goal" :in-theory (disable my-caller)))))

(defthm nil-proved
  nil
  :hints (("Goal" :in-theory (disable my-caller (my-caller))
                  :use (thm-42 thm-99)))
  :rule-classes nil)
