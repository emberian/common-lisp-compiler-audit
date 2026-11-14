;;; cross_sbcl_extra.lisp — SBCL 2.6.10 Cross-Oracle for fuzz_extra.lisp
(defpackage :ccl-codegen-fuzz-extra
  (:use :cl))
(in-package :ccl-codegen-fuzz-extra)

(defun canon (val)
  (cond
    ((floatp val)
     (let ((bits (etypecase val
                   (single-float (logand (sb-kernel:single-float-bits val) #xffffffff))
                   (double-float (logior (ash (logand (sb-kernel:double-float-high-bits val) #xffffffff) 32)
                                         (logand (sb-kernel:double-float-low-bits val) #xffffffff))))))
       (list :float (type-of val) bits)))
    ((complexp val)
     (list :complex (canon (realpart val)) (canon (imagpart val))))
    ((consp val)
     (cons (canon (car val)) (canon (cdr val))))
    ((and (vectorp val) (not (stringp val)))
     (cons :vec (map 'list #'canon val)))
    (t val)))

(defun safe-call (fn args)
  (handler-case
      (cons :ok (mapcar #'canon (multiple-value-list (apply fn args))))
    (error (c)
      (list :err (type-of c)))))

(let ((cases (with-open-file (in "/Users/ember/dev/compiler-audit/hunts/ccl-codegen/sbcl_extra_vectors.sexp")
               (read in)))
      (total 0)
      (diffs 0))
  (dolist (c cases)
    (let* ((desc (getf c :desc))
           (params (getf c :params))
           (body (getf c :body))
           (rows (getf c :rows))
           (fn (handler-bind ((warning #'muffle-warning)
                              (sb-ext:compiler-note #'muffle-warning))
                 (compile nil `(lambda ,params
                                 (declare (optimize (speed 1) (safety 3)))
                                 ,body)))))
      (dolist (row rows)
        (incf total)
        (destructuring-bind (args ccl-res) row
          (let ((sbcl-res (safe-call fn args)))
            (unless (equal ccl-res sbcl-res)
              ;; Note: signed single-float bits on CCL single-float-bits can be signed 32-bit
              (incf diffs)
              (format t "~%[SBCL-EXTRA-DIFF] ~A~%  args=~S~%  ccl=~S~%  sbcl=~S~%"
                      desc args ccl-res sbcl-res)))))))
  (format t "~%========================================~%")
  (format t "SBCL 2.6.10 extra checks:    ~D~%" total)
  (format t "SBCL vs CCL-ref diffs:       ~D~%" diffs)
  (format t "========================================~%"))
