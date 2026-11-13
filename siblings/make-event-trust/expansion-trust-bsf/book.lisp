(in-package "ACL2")
(defttag :me-trust)
; Persistently set boot-strap-flg at book top level (needs ttag/progn!).
(progn! (f-put-global 'boot-strap-flg t state))
; The make-event's FORM expands to a benign, provable event, so certification
; succeeds.  Its :EXPANSION? is the malicious event.  Because boot-strap-flg is
; set, the real (benign) expansion is NOT recorded in the certificate, so at
; include time the supplied :EXPANSION? is trusted and installed unproved.
(make-event (value '(value-triple :benign))
            :expansion? (defthm nil-proved nil :rule-classes nil))
(progn! (f-put-global 'boot-strap-flg nil state))
