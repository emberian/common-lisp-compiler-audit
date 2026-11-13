(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment warning warning! error)))
(defun-inline i (x) (declare (xargs :guard t)) (list x (quote zz))) (defun ui0 (x) (declare (xargs :guard t)) (i x))
(include-book "book")
(in-package "ACL2")
(cw "@I ~x0 ~x1~%" (len (global-val (quote include-book-alist) (w state))) (let ((a (global-val (quote include-book-alist) (w state)))) (len (remove-assoc-equal nil (pairlis$ (strip-cdrs (strip-cdrs (strip-cdrs (strip-cdrs a)))) nil)))))

(ld "hq.lisp" :ld-error-action :continue)
(cw "@Q ui0 ~x0~%" (ui0 3))
(quit)
