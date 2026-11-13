;;; Compiler-table coverage measured INSIDE a CCL-hosted ACL2 image.
;;;
;;; Load in raw mode (:q, (load ...), (lp)).  ccl-cov.lisp counts every use of
;;; the compiler tables; here the counts are kept only for compilations of the
;;; generated -OPT twins and the generated stobj's raw accessors and updaters:
;;; COMPILE-NAMED-FUNCTION is wrapped, and when the
;;; function being compiled is not an -OPT twin (a -REF twin, a *1* function, a
;;; helper, an anonymous top-level form) the counters are restored afterwards.
;;; Anonymous LAMBDA compilations (loop$ / lambda$ objects) are therefore NOT
;;; counted on this host, unlike acl2-sbcl-cov.lisp; the numbers undercount.
;;; (ccov:reset) clears, (ccov2:dump path) writes (:ccl (table (names...) ...)).
(load "/Users/ember/dev/compiler-audit/coverage/ccl-cov.lisp")
(defpackage :ccov2 (:use :cl) (:export #:dump #:dump-tables))
(in-package :ccov2)

(defun opt-name-p (name)
  (and (symbolp name) name (symbol-package name)
       (not (search "ACL2_*1*" (package-name (symbol-package name))))
       (let ((s (symbol-name name)))
         (or (search "-OPT" s) (eql 0 (search "ZSC" s)) (eql 0 (search "ZAR" s))
             (eql 0 (search "UPDATE-ZSC" s)) (eql 0 (search "UPDATE-ZAR" s))))))

(defun snapshot ()
  (flet ((h (tab) (let ((c (make-hash-table :test (hash-table-test tab))))
                    (maphash (lambda (k v) (setf (gethash k c) v)) tab) c)))
    (list (h ccov::*cm-tried*) (h ccov::*cm-won*) (h ccov::*folded*) (h ccov::*nx1*)
          (h ccov::*vinsns*) (copy-seq ccov::*op-seen*) (copy-seq ccov::*rewrite*)
          (copy-seq ccov::*p2*))))

(defun restore (s)
  (destructuring-bind (a b c d e f g h) s
    (setf ccov::*cm-tried* a ccov::*cm-won* b ccov::*folded* c ccov::*nx1* d ccov::*vinsns* e)
    (replace ccov::*op-seen* f) (replace ccov::*rewrite* g) (replace ccov::*p2* h)))

(defvar *in-opt* nil)
(defvar *opt-compiles* 0)
(let ((orig #'ccl::compile-named-function) (ccl:*warn-if-redefine-kernel* nil))
  (setf (fdefinition 'ccl::compile-named-function)
        (lambda (def &rest args)
          (let ((name (getf args :name)))
            (cond (*in-opt* (apply orig def args))
                  ((opt-name-p name)
                   (incf *opt-compiles*)
                   (let ((*in-opt* t)) (apply orig def args)))
                  (t (let ((s (snapshot)))
                       (multiple-value-prog1 (apply orig def args) (restore s)))))))))

(defun dump (path)
  (let ((r (ccov::reached)))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (let ((*package* (find-package :cl)) (*print-pretty* nil) (*print-readably* nil)
            (*print-length* nil) (*print-level* nil))
        (flet ((keys (k) (mapcar (lambda (x) (princ-to-string (car x))) (getf r k))))
          (prin1 (list :ccl (list :compiler-macros (keys :cm-won) :nx1 (keys :nx1)
                                  :acode-ops (keys :ops-seen) :rewrite (keys :rewrite)
                                  :p2 (keys :p2) :vinsns (keys :vinsns))
                       :opt-compiles *opt-compiles*)
                 s)
          (terpri s))))))

(defun dump-tables (path)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (let ((*package* (find-package :cl)) (*print-pretty* nil))
      (flet ((names (l) (mapcar (lambda (x) (princ-to-string (if (consp x) (car x) x))) l)))
        (prin1 (list :compiler-macros (names (ccov::all-compiler-macros)) :nx1 (names (ccov::all-nx1))
                     :acode-ops (names (ccov::all-acode-ops)) :rewrite (names (ccov::all-rewrite))
                     :p2 (names (ccov::all-p2)) :vinsns (names (ccov::all-vinsns)))
               s)))))
