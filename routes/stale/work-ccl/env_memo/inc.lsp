(set-inhibit-output-lst (set-difference-eq *valid-output-names* '(comment warning warning! error)))
(defconst *k* 1000) (defun f (x) (declare (xargs :guard (integerp x))) (+ x *k* 1)) (memoize (quote f)) (cw "@Q pre ~x0~%" (f 3))
(include-book "book")
(in-package "ACL2")
(cw "@I ~x0 ~x1~%" (len (global-val (quote include-book-alist) (w state))) (let ((a (global-val (quote include-book-alist) (w state)))) (len (remove-assoc-equal nil (pairlis$ (strip-cdrs (strip-cdrs (strip-cdrs (strip-cdrs a)))) nil)))))

(ld "hq.lisp" :ld-error-action :continue)
(cw "@Q memo ~x0~%" (list (f 3) (f 4) (and (getpropc (quote f) (quote memoized) nil (w state)) t)))
(quit)
