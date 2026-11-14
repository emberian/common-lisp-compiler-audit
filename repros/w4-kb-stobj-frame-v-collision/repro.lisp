(in-package "ACL2")
(ld "std/package.lsp" :dir :system)
(include-book "tools/stobj-frame" :dir :system :ttags nil)

(defstobj my-stobj slot0 slot1)

(defun set-slot0-v (v my-stobj)
  (declare (xargs :stobjs my-stobj))
  (update-slot0 v my-stobj))

;; tools/stobj-frame.lisp:316 searches (position 'n formals) instead of
;; (position 'v formals), leaving V unrenamed in formals and colliding with
;; the generated DEFTHM's own V variable.
(def-stobj-frame set-slot0-v my-stobj)
(quit)
