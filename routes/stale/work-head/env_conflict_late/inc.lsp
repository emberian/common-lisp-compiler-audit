(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment warning warning! error)))
(defun lm (x) (declare (xargs :guard t)) (list x 77))
(include-book "book")
(in-package "ACL2")
(cw "@I ~x0 ~x1~%" (len (global-val (quote include-book-alist) (w state))) (let ((a (global-val (quote include-book-alist) (w state)))) (len (remove-assoc-equal nil (pairlis$ (strip-cdrs (strip-cdrs (strip-cdrs (strip-cdrs a)))) nil)))))
(defconst *k* 5) (defun f (x) (declare (xargs :guard (integerp x))) (- x *k*)) (defun g (x) (declare (xargs :guard t)) (list x 78)) (defun e (x) (declare (xargs :guard t)) (list x 79)) (defmacro m (x) (list (quote list) x 80)) (defun um (x) (declare (xargs :guard t)) (m x)) (defun h (x) (declare (xargs :mode :program)) (list x 81))
(ld "hq.lisp" :ld-error-action :continue)

(quit)
