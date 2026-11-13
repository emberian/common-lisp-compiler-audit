(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment warning warning! error)))

(include-book "ltop")
(in-package "ACL2")
(cw "@I ~x0 ~x1~%" (len (global-val (quote include-book-alist) (w state))) (let ((a (global-val (quote include-book-alist) (w state)))) (len (remove-assoc-equal nil (pairlis$ (strip-cdrs (strip-cdrs (strip-cdrs (strip-cdrs a)))) nil)))))
(defconst *lqc* 5) (defmacro lqm (x) (list (quote list) x 77)) (defun q (x) (declare (xargs :guard t)) (cons x (quote mine))) (defun q2 (x) (declare (xargs :guard t)) (cons x (quote mine2))) (defun q3 (x) (declare (xargs :guard t)) (cons x (quote mine3))) (defun-inline qi (x) (declare (xargs :guard t)) (cons x (quote mine-inline)))
(ld "lqq.lisp" :ld-error-action :continue)

(quit)
