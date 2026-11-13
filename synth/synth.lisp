;;; Typed ACL2 program synthesizer for route-equivalence testing.
;;;
;;;   base.lisp     randomness, abstract types, transfer functions
;;;   infer.lisp    abstract interpreter with branch refinement; annotation
;;;   gen.lisp      expression generation, optional operator groups (swarm features)
;;;   fns.lisp      function kinds, stobj layout
;;;   program.lisp  programs as data: creation, validation, (de)serialization
;;;   context.lisp  context envelope (events around the definitions)
;;;   emit.lisp     program -> book.lisp, queries.lisp, memo.lisp, unmemo.lisp, manifest.txt
;;;
;;; Each function is emitted as a -REF twin (:verify-guards nil, evaluated in the
;;; logic under guard checking :all, which checks every THE and guard) and an
;;; -OPT twin (guard-verified under skip-proofs, run raw).  If INFER is wrong, REF
;;; aborts and the query is discarded; it cannot produce a false divergence.
;;;
;;; Usage: sbcl --script synth.lisp SEED NFUNCTIONS OUTDIR/
(defpackage :zs (:use :cl))
(in-package :zs)
(defparameter *here* (directory-namestring (or *load-truename* *default-pathname-defaults*)))
(defun load-part (name) (load (concatenate 'string *here* name)))
(dolist (f '("base.lisp" "infer.lisp" "gen.lisp" "fns.lisp" "program.lisp" "context.lisp" "emit.lisp" "batch.lisp" "mutate.lisp"))
  (load-part f))

(defun main ()
  (let ((args (last sb-ext:*posix-argv* 3)))
    (emit-prog (make-prog (parse-integer (first args)) (parse-integer (second args)))
               (third args))))
(unless (boundp 'cl-user::*zs-library*) (main))
