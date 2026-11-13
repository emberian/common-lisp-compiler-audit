; stage1.lisp -- enumerate every function and macro symbol of the ACL2 boot-strap world and
; record what the host knows about the same symbol in raw Lisp, plus the derived type of an
; unconstrained call.
(in-package "ACL2")
(load "/Users/ember/dev/compiler-audit/derived-types/common.lisp")

(defun dt-raw-kind (s)
  (cond ((special-operator-p s) "special")
        ((macro-function s) "macro")
        ((not (fboundp s)) "unbound")
        (t "function")))

(defun dt-attrs (s)
  (let ((info (sb-int:info :function :info s)))
    (if info (sb-c::decode-ir1-attributes (sb-c::fun-info-attributes info)) :none)))

(defun dt-info-slots (s)
  (let ((info (sb-int:info :function :info s)))
    (if info
        (remove nil (list (and (sb-c::fun-info-derive-type info) :derive-type)
                          (and (sb-c::fun-info-optimizer info) :optimizer)
                          (and (sb-c::fun-info-transforms info) :transforms)
                          (and (sb-c::fun-info-templates info) :templates)
                          (and (sb-c::fun-info-constraint-propagate info) :constraint-propagate)
                          (and (sb-c::fun-info-constraint-propagate-if info) :constraint-propagate-if)))
        nil)))

(let* ((w (dt-world))
       (fns (dt-all-function-symbols w))
       (macs (dt-all-macro-symbols w)))
  (with-open-file (o (dt-path "results/sbcl-enumeration.tsv") :direction :output :if-exists :supersede)
    (format o "symbol	home-package	logic-kind	arity	raw-kind	inlinep	has-inline-expansion	where-from	source-transform	fun-info-attributes	fun-info-slots	declared-or-recorded-ftype	derived-unconstrained~%")
    (flet ((row (s kind formals)
             (let* ((rk (dt-raw-kind s))
                    (d (if (and (listp formals) (not (equal rk "unbound")) (not (equal rk "special"))
                                (not (intersection formals lambda-list-keywords)))
                           (dt-derived `(lambda ,formals (declare (ignorable ,@formals))
                                          (values (,s ,@formals) ,@formals)))
                           :not-attempted)))
               (format o "~A	~A	~A	~A	~A	~A	~A	~A	~A	~A	~A	~A	~A~%"
                       (dt-1line s) (package-name (symbol-package s)) kind
                       (if (listp formals) (length formals) "-") rk
                       (sb-int:info :function :inlinep s)
                       (if (sb-int:info :function :inlining-data s) "yes" "no")
                       (sb-int:info :function :where-from s)
                       (if (sb-int:info :function :source-transform s) "yes" "no")
                       (dt-1line (dt-attrs s)) (dt-1line (dt-info-slots s))
                       (dt-1line (ignore-errors (sb-kernel:type-specifier (sb-int:info :function :type s))))
                       (dt-1line d)))))
      (dolist (s fns) (row s "function" (getpropc s 'formals nil w)))
      (dolist (s macs) (row s "macro" :macro))))
  (format t "~&STAGE1 functions ~D macros ~D primitive-formals-and-guards ~D~%"
          (length fns) (length macs) (length *primitive-formals-and-guards*)))
