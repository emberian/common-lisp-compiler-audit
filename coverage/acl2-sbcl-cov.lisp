;;; Compiler-table coverage measured INSIDE an SBCL-hosted ACL2 image.
;;;
;;; Load in raw mode (:q, (load ...), (lp)).  Every deftransform that fires and
;;; every VOP template that is emitted is attributed to the component being
;;; compiled.  ACL2 names its components (DEFUN name); the classes are
;;;   :opt     raw definition of a generated -OPT twin (the code under test),
;;;            the raw accessors and updaters of the generated stobj ZST (the
;;;            -OPT twins call them, or inline them under defstobj :inline t),
;;;            plus the anonymous LAMBDA components ACL2 compiles for the
;;;            loop$ / lambda$ objects (they run raw under apply$)
;;;   :ref     raw definition of a -REF twin (never run: REF is evaluated in the logic)
;;;   :other   *1* functions, helpers, the top-level forms of the session
;;; (ccov:reset) clears, (ccov:dump path) writes the :opt sets and class totals.
(defpackage :ccov (:use :cl) (:export #:reset #:dump #:dump-tables))
(in-package :ccov)

(defvar *fired* (make-hash-table :test 'equal))    ; class -> (key -> count)
(defvar *emitted* (make-hash-table :test 'equal))
(defvar *unknown* 0)

(defun tab (top class)
  (or (gethash class top) (setf (gethash class top) (make-hash-table :test 'equal))))

(defun transform-key (fun-name transform)
  (list fun-name
        (let ((*print-pretty* nil) (*package* (find-package :cl)))
          (prin1-to-string (sb-kernel:type-specifier (sb-c::transform-type transform))))
        (sb-c::transform-note transform)))

(defun class-of-node (node)
  (let ((name (ignore-errors (sb-c::component-name (sb-c::node-component node)))))
    (cond ((and (consp name) (eq (car name) 'defun) (symbolp (second name)))
           (let ((s (symbol-name (second name)))
                 (p (package-name (symbol-package (second name)))))
             (cond ((search "ACL2_*1*" p) :other)
                   ((search "-OPT" s) :opt)
                   ((or (eql 0 (search "ZSC" s)) (eql 0 (search "ZAR" s))
                        (eql 0 (search "UPDATE-ZSC" s)) (eql 0 (search "UPDATE-ZAR" s)))
                    :opt)
                   ((search "-REF" s) :ref)
                   (t :other))))
          ((and (consp name) (eq (car name) 'lambda)) :opt)
          ((null name) (incf *unknown*) :other)
          (t :other))))

(defun all-transforms ()
  (let ((out '()))
    (do-all-symbols (s)
      (let ((info (ignore-errors (sb-int:info :function :info s))))
        (when info
          (dolist (tr (sb-c::fun-info-transforms info))
            (pushnew (transform-key s tr) out :test #'equal)))))
    out))

(defun all-vops ()
  (let ((out '()))
    (maphash (lambda (name template) (declare (ignore template)) (push name out))
             sb-c::*backend-template-names*)
    out))

(sb-ext:without-package-locks
  (setf sb-c::*show-transforms-p* t)
  (sb-int:encapsulate 'sb-c::show-transform 'ccov
    (lambda (f kind name new-form &optional combination transform)
      (declare (ignore f new-form kind))
      (when transform
        (incf (gethash (transform-key name transform)
                       (tab *fired* (if combination (class-of-node combination) :other))
                       0)))))
  (sb-int:encapsulate 'sb-c::emit-vop 'ccov
    (lambda (f node block template &rest rest)
      (incf (gethash (sb-c::template-name template) (tab *emitted* (class-of-node node)) 0))
      (apply f node block template rest))))

(defun reset () (clrhash *fired*) (clrhash *emitted*) (setf *unknown* 0))

(defun keys (h) (and h (loop for k being the hash-keys of h collect k)))

(defun dump (path)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (let ((*package* (find-package :cl)) (*print-pretty* nil) (*print-readably* nil)
          (*print-length* nil) (*print-level* nil))
      (prin1 (list :fired (keys (gethash :opt *fired*))
                   :emitted (keys (gethash :opt *emitted*))
                   :ref-fired (length (keys (gethash :ref *fired*)))
                   :other-fired (length (keys (gethash :other *fired*)))
                   :other-emitted (length (keys (gethash :other *emitted*)))
                   :unknown *unknown*)
             s)
      (terpri s))))

(defun dump-tables (path)
  (with-open-file (s path :direction :output :if-exists :supersede)
    (let ((*package* (find-package :cl)) (*print-pretty* nil))
      (prin1 (list :all-transforms (all-transforms) :all-vops (all-vops)) s))))
