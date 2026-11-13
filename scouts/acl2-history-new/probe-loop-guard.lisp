(in-package "ACL2")
; NOTE-8-4 malformed :guard positions and nearby variants.
(thm (equal (loop$ for v in '(1 2) collect :guard) '(:guard :guard)))
(thm (equal (loop$ for v in '(1 2) when :guard collect v) '(1 2)))
(thm (equal (loop$ for v in '(1 2) until :guard collect v) nil))
; Documented quoted-keyword control should be accepted and return keywords.
(thm (equal (loop$ for v in '(1 2) collect ':guard) '(:guard :guard)))
; Newer do loop$ route: :guard as a FINALLY body must not be confused with syntax.
(thm (equal (loop$ for v in '(1 2) do :guard finally (return v)) 1))
(quit)
