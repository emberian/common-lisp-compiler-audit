(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment warning warning! error)))
(set-ld-skip-proofsp t state)
(include-book "book")
(in-package "ACL2")
(cw "@I ~x0 ~x1~%" (len (global-val (quote include-book-alist) (w state))) (let ((a (global-val (quote include-book-alist) (w state)))) (len (remove-assoc-equal nil (pairlis$ (strip-cdrs (strip-cdrs (strip-cdrs (strip-cdrs a)))) nil)))))
(set-ld-skip-proofsp nil state)
(ld "hq.lisp" :ld-error-action :continue)

(quit)
