(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment warning warning! error)))
(defstub cst (x) t) (defun impl-old (x) (declare (xargs :guard t)) (list x (quote old))) (defattach cst impl-old) (cw "@Q pre ~x0~%" (cst 3)) (defun call-cst (x) (declare (xargs :guard t)) (list (cst x) (quote ca))) (memoize (quote call-cst) :aokp t) (cw "@Q pre2 ~x0~%" (call-cst 3))
(include-book "book")
(in-package "ACL2")
(cw "@I ~x0 ~x1~%" (len (global-val (quote include-book-alist) (w state))) (let ((a (global-val (quote include-book-alist) (w state)))) (len (remove-assoc-equal nil (pairlis$ (strip-cdrs (strip-cdrs (strip-cdrs (strip-cdrs a)))) nil)))))

(ld "aq.lisp" :ld-error-action :continue)

(quit)
