; SCR-S2 standalone session: loads book.lisp events directly in a fresh session
; and checks that (defthm nil-proved nil) is admitted with zero ttags/skip-proofs.

(ld "book.lisp" :ld-error-action :return)

(cw "@THM-42 ~x0~%" (formula 'thm-42 t (w state)))
(cw "@THM-99 ~x0~%" (formula 'thm-99 t (w state)))
(cw "@NIL-FORMULA ~x0~%" (formula 'nil-proved t (w state)))
(cw "@TTAG ~x0~%" (ttag (w state)))
(cw "@TTAGS-SEEN ~x0~%" (global-val 'ttags-seen (w state)))
(cw "@SKIP-PROOFS-SEEN ~x0~%" (global-val 'skip-proofs-seen (w state)))
(cw "@REDEF-SEEN ~x0~%" (global-val 'redef-seen (w state)))
(cw "@END~%")
:q
