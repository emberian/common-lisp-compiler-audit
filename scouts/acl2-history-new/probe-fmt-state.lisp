(in-package "ACL2")
; NOTE-8-4 original local evisc-table exploit.
(encapsulate
  ()
  (local (table evisc-table '(a b c) "<my-abc-list>"))
  (defconst *c*
    (mv-let (col s)
      (fmt1-to-string "~x0" (list (cons #\0 '(a b c))) 0)
      (declare (ignore s))
      col))
  (defthm it-is-7 (equal *c* 7) :rule-classes nil))
(defthm c-is-13 (equal *c* 13) :rule-classes nil)
; Newer make-event route: expansion must not preserve a state-dependent value.
(encapsulate
  ()
  (local (table evisc-table '(a b c) "<my-abc-list>"))
  (make-event
   '(defconst *c-me*
      (mv-let (col s)
        (fmt1-to-string "~x0" (list (cons #\0 '(a b c))) 0)
        (declare (ignore s))
        col)))
  (defthm me-is-7 (equal *c-me* 7) :rule-classes nil))
(defthm me-is-13 (equal *c-me* 13) :rule-classes nil)
(quit)
