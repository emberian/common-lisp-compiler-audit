(in-package "ACL2-PC")
; NOTE-8-4 current-package dependence of printing-to-string.
#!acl2
(defconst *c*
  (mv-let (col str)
    (fmt1-to-string "~x0" (list (cons #\0 'abc)) 0)
    (declare (ignore str)) col))
#!acl2
(thm (equal *c* 3))
#!acl2
(defconst *c2*
  (mv-let (col str)
    (fmt1-to-string "~x0" (list (cons #\0 'abc)) 0
                    :fmt-control-alist '((current-package . "ACL2-PC")))
    (declare (ignore str)) col))
#!acl2
(thm (equal *c2* 9))
; make-event variant in the non-default current package.
#!acl2
(make-event
 '(defconst *c-me*
    (mv-let (col str)
      (fmt1-to-string "~x0" (list (cons #\0 'abc)) 0)
      (declare (ignore str)) col)))
#!acl2
(thm (equal *c-me* 3))
(acl2::quit)
