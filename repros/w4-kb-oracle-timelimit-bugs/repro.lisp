(in-package "ACL2")
(ld "std/package.lsp" :dir :system)
(include-book "tools/oracle-timelimit" :dir :system :ttags :all)

;; Bug 1: :suppress-lisp-errors nil still catches raw Lisp errors because
;; oracle-timelimit-raw.lsp tests the gensym variable `suppress-lisp-errors`
;; at macroexpansion time instead of its runtime value.
(defun boom ()
  (declare (xargs :mode :program))
  (car 1))

(mv-let (okp secs bytes ans state)
  (oracle-timelimit 5 (boom) :suppress-lisp-errors nil)
  (declare (ignore secs bytes))
  (prog2$ (cw "~%[OTL-SUPPRESS-BUG: okp=~x0 ans=~x1]~%" okp ans)
          state))

;; Bug 2: negative limit (-1) causes the timeout thread to error in (sleep -1),
;; so the computation runs to completion and returns okp=T.
(mv-let (okp secs bytes ans state)
  (oracle-timelimit -1 (+ 1 2))
  (declare (ignore secs bytes))
  (prog2$ (cw "~%[OTL-NEG-LIMIT-BUG: okp=~x0 ans=~x1]~%" okp ans)
          state))

;; Bug 3: :ret (mv ans state) with :onfail (mv :oops state) crashes on failure/timeout
;; because oracle-timelimit-exec-raw returns (values nil nil), binding state to NIL
;; before (oracle-timelimit-extract state) checks (live-state-p state)!
(oracle-timelimit 5 (prog2$ (boom) (mv 0 state))
                  :ret (mv ans state)
                  :onfail (mv :oops state))
(quit)
