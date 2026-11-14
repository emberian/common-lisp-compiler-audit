(in-package "ACL2")
(ld "std/package.lsp" :dir :system)
(include-book "std/util/define" :dir :system)
(ld "std/stobjs/2d-arr.lisp" :dir :system :ld-skip-proofsp t)
(in-package "ACL2")
(defun any-p (x)
  (declare (xargs :guard t) (ignore x))
  t)
(skip-proofs (stobjs::def-2d-arr any2d :pred any-p))
;; Guard (natp nrows) is satisfied by (expt 2 60), yet exec branch calls
;; (ec-call (any2d-resize-rows$g ...)) on a live stobj, failing ACL2's stobj
;; ec-call restriction.
(any2d-resize-rows (expt 2 60) any2d)
(quit)
