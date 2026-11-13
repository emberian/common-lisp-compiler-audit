;;; Load the synthesizer as a library (no command-line main).
(defpackage :zs (:use :cl))
(defvar cl-user::*zs-library* t)
(load (merge-pathnames "synth.lisp" (directory-namestring *load-truename*)))
