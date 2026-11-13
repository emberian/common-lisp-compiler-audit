(in-package "ACL2")
; NOTE-7-2 state under with-guard-checking, plus newer global-stobj nesting.
(defun foo-direct (state)
  (declare (xargs :stobjs state
                  :guard (f-boundp-global 'guard-checking-on state)))
  (with-guard-checking :all (f-get-global 'guard-checking-on state)))
(defmacro my-with-guard-checking (val form)
  `(with-guard-checking1 (chk-with-guard-checking-arg ,val) ,form))
(defun foo-macro (state)
  (declare (xargs :stobjs state
                  :guard (f-boundp-global 'guard-checking-on state)))
  (my-with-guard-checking :all (f-get-global 'guard-checking-on state)))
(defstobj gs (gs-fld))
(defun foo-global (state)
  (declare (xargs :stobjs state))
  (with-guard-checking :all
    (with-global-stobj gs (gs-fld gs))))
; Supported stateful alternative, expected to execute successfully.
(with-guard-checking-error-triple :none (value 3))
(quit)
