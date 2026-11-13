;;; Compiler-table coverage for SBCL: which deftransforms fire and which VOP
;;; templates are emitted while compiling a form, against the full tables.
(defpackage :ccov (:use :cl) (:export #:with-coverage #:*fired* #:*emitted*
                                      #:all-transforms #:all-vops #:transform-key))
(in-package :ccov)

(defvar *fired* (make-hash-table :test 'equal))    ; transform key -> count
(defvar *emitted* (make-hash-table :test 'eq))     ; vop name -> count

(defun transform-key (fun-name transform)
  (list fun-name
        (let ((*print-pretty* nil) (*package* (find-package :cl)))
          (prin1-to-string (sb-kernel:type-specifier (sb-c::transform-type transform))))
        (sb-c::transform-note transform)))

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

(defvar *source-fired* (make-hash-table :test 'equal)) ; (kind name) -> count

;;; SHOW-TRANSFORM is called on every successful transform when
;;; *SHOW-TRANSFORMS-P* is true.  Record instead of printing.
(sb-ext:without-package-locks
  (setf sb-c::*show-transforms-p* t)
  (sb-int:encapsulate 'sb-c::show-transform 'ccov
    (lambda (f kind name new-form &optional combination transform)
      (declare (ignore f new-form combination))
      (if transform
          (incf (gethash (transform-key name transform) *fired* 0))
          (incf (gethash (list kind name) *source-fired* 0))))))

(sb-ext:without-package-locks
  (sb-int:encapsulate 'sb-c::emit-vop 'ccov
    (lambda (f node block template &rest rest)
      (incf (gethash (sb-c::template-name template) *emitted* 0))
      (apply f node block template rest))))

(defun reset ()
  (clrhash *fired*) (clrhash *emitted*) (clrhash *source-fired*))

(defun dump (path)
  "Write the fired-transform and emitted-VOP sets, plus the full tables."
  (let ((fired (loop for k being the hash-keys of *fired* collect k))
        (emitted (loop for k being the hash-keys of *emitted* collect k))
        (src (loop for k being the hash-keys of *source-fired* collect k)))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (let ((*package* (find-package :cl)) (*print-pretty* nil))
        (print (list :fired fired :emitted emitted :source src
                     :all-transforms (all-transforms) :all-vops (all-vops))
               s)))
    (format t "~&CCOV transforms ~D/~D  vops ~D/~D  source-level ~D~%"
            (length fired) (length (all-transforms))
            (length emitted) (length (all-vops)) (length src))))
(export '(reset dump))
