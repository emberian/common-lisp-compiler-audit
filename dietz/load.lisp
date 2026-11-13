;;; Loads Paul Dietz's random typed-integer-form tester (ansi-test).
;;; Run from the ansi-test checkout directory.
(in-package :cl-user)
(defun env (name default)
  (let ((v #+sbcl (sb-ext:posix-getenv name) #+ccl (ccl:getenv name)))
    (if (and v (plusp (length v))) v default)))
(let (*load-verbose* *load-print* *compile-verbose* *compile-print*)
  (handler-bind ((warning #'muffle-warning))
    (load "gclload1.lsp")
    ;; random-int-form.lsp re-includes random-aux.lsp by a path relative to
    ;; itself, where it does not live; gclload1 has already loaded it.
    (let ((orig (fdefinition (intern "COMPILE-AND-LOAD" :cl-user))))
      (setf (fdefinition (intern "COMPILE-AND-LOAD" :cl-user))
            (lambda (pathspec &rest rest)
              (unless (equal (file-namestring (pathname pathspec)) "random-aux.lsp")
                (apply orig pathspec rest)))))
    (funcall (intern "COMPILE-AND-LOAD" :cl-user)
             (merge-pathnames "random/random-int-form.lsp" (truename ".")))))
