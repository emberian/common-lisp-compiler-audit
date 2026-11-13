; stage1-ccl.lisp -- CCL counterpart of stage1.lisp: every function and macro symbol of the
; ACL2 world, what CCL's compiler knows about it, and the acode operator and inferred type
; of an unconstrained call (lambda formals (f . formals)).
(in-package "ACL2")
(load "/Users/ember/dev/compiler-audit/derived-types/common.lisp")

(defun dt-raw-kind (s)
  (cond ((special-operator-p s) "special")
        ((macro-function s) "macro")
        ((not (fboundp s)) "unbound")
        (t "function")))

(let* ((w (dt-world))
       (fns (dt-all-function-symbols w))
       (macs (dt-all-macro-symbols w)))
  (with-open-file (o (dt-path "results/ccl-enumeration.tsv") :direction :output :if-exists :supersede)
    (format o "symbol	home-package	logic-kind	arity	raw-kind	proclaimed-inline	proclaimed-notinline	nx1-handler	compiler-macro	proclaimed-ftype	acode-operator	acode-type~%")
    (flet ((row (s kind formals)
             (let* ((rk (dt-raw-kind s)) (op :not-attempted) (ty :not-attempted))
               (when (and (listp formals) (equal rk "function")
                          (not (intersection formals lambda-list-keywords)))
                 (multiple-value-bind (f o2 ty2)
                     (dt-ccl-probe `(lambda ,formals (declare (ignorable ,@formals)) (,s ,@formals)))
                   (if (functionp f) (setq op o2 ty ty2) (setq op :error ty f))))
               (format o "~A	~A	~A	~A	~A	~A	~A	~A	~A	~A	~A	~A~%"
                       (dt-1line s) (package-name (symbol-package s)) kind
                       (if (listp formals) (length formals) "-") rk
                       (if (ccl::proclaimed-inline-p s) "yes" "no")
                       (if (ccl::proclaimed-notinline-p s) "yes" "no")
                       (if (gethash s ccl::*nx1-alphatizers*) "yes" "no")
                       (if (compiler-macro-function s) "yes" "no")
                       (dt-1line (ccl::proclaimed-ftype s))
                       (dt-1line op) (dt-1line ty)))))
      (dolist (s fns) (row s "function" (getpropc s 'formals nil w)))
      (dolist (s macs) (row s "macro" :macro))))
  ; the static tables themselves
  (with-open-file (o (dt-path "results/ccl-acode-operator-types.tsv") :direction :output :if-exists :supersede)
    (format o "acode-operator	static-result-type	has-inferrer	has-rewriter~%")
    (loop for i from 0 below (length ccl::*acode-operator-types*)
          for nm = (ignore-errors (ccl::acode-operator-name i))
          when nm
          do (format o "~A	~A	~A	~A~%" (dt-1line nm) (dt-1line (svref ccl::*acode-operator-types* i))
                     (if (svref ccl::*acode-simple-type-inferrers* i) "yes" "no")
                     (if (and (< i (length ccl::*acode-rewrite-functions*))
                              (svref ccl::*acode-rewrite-functions* i)) "yes" "no"))))
  (format t "~&STAGE1-CCL functions ~D macros ~D~%" (length fns) (length macs)))
