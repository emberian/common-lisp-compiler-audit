;;;; Cross-Oracle Verifier on SBCL 2.6.10
;;;; Reads sbcl_vectors.sexp exported by fuzz.lisp on CCL 1.14 and checks every case!

(defpackage #:ccl-codegen-fuzz (:use #:cl))
(in-package #:ccl-codegen-fuzz)

(defun norm-val (v)
  (cond
    ((floatp v)
     (cond ((/= v v) (list :nan (type-of v)))
           ((= v 0) (list :zero (type-of v) (if (< (float-sign v) 0) -1 +1)))
           ((> (abs v) most-positive-double-float)
            (list :inf (type-of v) (if (> v 0) +1 -1)))
           (t v)))
    ((complexp v)
     (list :complex (norm-val (realpart v)) (norm-val (imagpart v))))
    ((consp v)
     (cons (norm-val (car v)) (norm-val (cdr v))))
    ((and (vectorp v) (not (stringp v)))
     (map 'list #'norm-val v))
    (t v)))

(defun safe-call (fn &rest args)
  (handler-case
      (cons :ok (mapcar #'norm-val (multiple-value-list (apply fn args))))
    (error (c)
      (list :err (type-of c)))))

(defun verify-vectors (path)
  (let ((suites (with-open-file (in path :direction :input)
                  (with-standard-io-syntax
                    (read in))))
        (checked 0)
        (diffs 0))
    (dolist (s suites)
      (let* ((desc   (getf s :desc))
             (params (getf s :params))
             (decls  (getf s :decls))
             (body   (getf s :body))
             (cases  (getf s :cases))
             (fn     (handler-bind ((warning #'muffle-warning)
                                    (sb-ext:compiler-note #'muffle-warning))
                       (compile nil `(lambda ,params (declare ,@decls) ,body)))))
        (dolist (c cases)
          (destructuring-bind (args ccl-res) c
            (incf checked)
            (let ((sbcl-res (apply #'safe-call fn args)))
              (unless (or (equal ccl-res sbcl-res)
                          (and (eq (car ccl-res) :err) (eq (car sbcl-res) :err)))
                (incf diffs)
                (format t "~%[SBCL-DIFF] ~A~%  args=~S~%  ccl-notinline=~S~%  sbcl=~S~%"
                        desc args ccl-res sbcl-res)))))))
    (format t "~%========================================~%")
    (format t "SBCL 2.6.10 cross-oracle checks: ~D~%" checked)
    (format t "SBCL vs CCL-notinline diffs:     ~D~%" diffs)
    (format t "========================================~%")))

(verify-vectors "/Users/ember/dev/compiler-audit/hunts/ccl-codegen/sbcl_vectors.sexp")
