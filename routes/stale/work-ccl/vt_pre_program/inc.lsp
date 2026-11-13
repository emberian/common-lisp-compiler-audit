(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment warning warning! error)))
(defun vh (x) (declare (xargs :mode :program :guard t)) (list x 'va)) (cw "@Q pre ~x0~%" (vh 3))
(include-book "vt2")
(in-package "ACL2")
(cw "@I ~x0 ~x1~%" (len (global-val (quote include-book-alist) (w state))) (let ((a (global-val (quote include-book-alist) (w state)))) (len (remove-assoc-equal nil (pairlis$ (strip-cdrs (strip-cdrs (strip-cdrs (strip-cdrs a)))) nil)))))

(ld "vq.lisp" :ld-error-action :continue)

(quit)
