; saved_acl2 < flush-compress-raw-error.lisp
; flush-compress is :logic, guard-verified, with guard T and logical value NIL
; for every argument, but its raw code is (set-acl2-array-property name nil),
; which needs a symbol.  A guard-satisfying call aborts with a raw Lisp error.
; Same pattern, one form per session (the abort discards pending input on SBCL):
;   (throw-or-attach-call 0 0)   (null-body-er 0 0 t)
(thm (equal (flush-compress x) nil))   ; proved from the logical definition
(flush-compress 'a)                    ; NIL
(flush-compress 0)                     ; raw Lisp error, not NIL
