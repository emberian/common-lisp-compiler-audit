; SCR-S1 standalone session: loads book.lisp events directly in a fresh session
; and checks that (defthm nil-proved nil) is admitted with zero ttags/skip-proofs.

(ld "book.lisp" :ld-error-action :return)

(cw "@CALLER-STALE ~x0~%" (my-caller 10))
(cw "@MY-H-NOW ~x0~%" (my-h 10))
(cw "@NIL-FORMULA ~x0~%" (formula 'nil-proved t (w state)))
(cw "@TTAG ~x0~%" (ttag (w state)))
(cw "@TTAGS-SEEN ~x0~%" (global-val 'ttags-seen (w state)))
(cw "@SKIP-PROOFS-SEEN ~x0~%" (global-val 'skip-proofs-seen (w state)))
(cw "@REDEF-SEEN ~x0~%" (global-val 'redef-seen (w state)))
(cw "@END~%")
:q
