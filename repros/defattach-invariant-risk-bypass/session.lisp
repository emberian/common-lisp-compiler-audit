; SCR-S3 standalone session: loads book.lisp events directly in a fresh session
; and checks that (defthm nil-proved nil) is admitted with zero ttags/skip-proofs.

(ld "book.lisp" :ld-error-action :return)

(cw "@FN-RISK ~x0~%" (getpropc 'my-st-fn 'invariant-risk nil (w state)))
(cw "@IMPL-RISK ~x0~%" (getpropc 'my-st-impl 'invariant-risk nil (w state)))
(cw "@CORRUPT-RISK ~x0~%" (getpropc 'corrupt 'invariant-risk nil (w state)))
(cw "@ST-FLD-RAW ~x0~%" (fld st))
(cw "@NIL-FORMULA ~x0~%" (formula 'nil-proved t (w state)))
(cw "@TTAG ~x0~%" (ttag (w state)))
(cw "@TTAGS-SEEN ~x0~%" (global-val 'ttags-seen (w state)))
(cw "@SKIP-PROOFS-SEEN ~x0~%" (global-val 'skip-proofs-seen (w state)))
(cw "@REDEF-SEEN ~x0~%" (global-val 'redef-seen (w state)))
(cw "@END~%")
:q
