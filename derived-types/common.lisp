; common.lisp -- shared by the SBCL derived-type oracle stages.  Raw Lisp, package ACL2.
(in-package "ACL2")

(defvar *dt-dir* "/Users/ember/dev/compiler-audit/derived-types/")
(defun dt-path (name) (concatenate 'string *dt-dir* name))

(defun dt-world () (w *the-live-state*))

(defun dt-all-function-symbols (w)
  ; every symbol with a FORMALS property in world w (same rule as primitives/sweep.lisp)
  (let ((seen (make-hash-table :test 'eq)) (acc nil))
    (dolist (trip w)
      (when (and (eq (cadr trip) 'formals) (not (gethash (car trip) seen)))
        (setf (gethash (car trip) seen) t)
        (unless (eq (getpropc (car trip) 'formals t w) t) (push (car trip) acc))))
    (nreverse acc)))

(defun dt-all-macro-symbols (w)
  (let ((seen (make-hash-table :test 'eq)) (acc nil))
    (dolist (trip w)
      (when (and (eq (cadr trip) 'macro-body) (not (gethash (car trip) seen)))
        (setf (gethash (car trip) seen) t)
        (unless (eq (getpropc (car trip) 'macro-body t w) t) (push (car trip) acc))))
    (nreverse acc)))

(defun dt-compile (form)
  ; Compile FORM (a lambda expression) under the global policy of the image, which is
  ; ACL2's own *acl2-optimize-form* as proclaimed in acl2.lisp.  Returns the function
  ; or (:err text).
  (handler-case
      (let ((*error-output* (make-broadcast-stream))
            (*standard-output* (make-broadcast-stream)))
        (multiple-value-bind (f warn fail)
            (handler-bind ((warning #'muffle-warning)) (compile nil form))
          (declare (ignore warn fail))
          (or f (list :err "compile returned nil"))))
    (error (c) (list :err (remove #\Newline (princ-to-string c))))))

#+sbcl
(defun dt-derived (form)
  ; The derived function type of the compiled lambda, as SBCL stores it in the
  ; simple-fun header: (FUNCTION (argtypes) result).
  (let ((f (dt-compile form)))
    (if (functionp f) (sb-kernel:%simple-fun-type f) f)))

; ---- CCL: the acode of the lambda as the back end receives it ------------------------
; compile-named-function (compiler/nx.lisp) runs nx1-compile-lambda, then
; (rewrite-acode-form (afunc-acode afunc) t), then the back end.  We wrap
; rewrite-acode-form to keep the outermost form it was given, after rewriting.
#+ccl (defvar *dt-ccl-top* nil)
#+ccl (defvar *dt-ccl-depth* 0)
#+ccl (defvar *dt-ccl-orig-rewrite* nil)
#+ccl
(defun dt-ccl-install ()
  (unless *dt-ccl-orig-rewrite*
    (setq *dt-ccl-orig-rewrite* #'ccl::rewrite-acode-form)
    (let ((ccl::*warn-if-redefine-kernel* nil) (orig *dt-ccl-orig-rewrite*))
      (setf (symbol-function 'ccl::rewrite-acode-form)
            (lambda (form &optional (type t))
              (if (zerop *dt-ccl-depth*)
                  (let ((*dt-ccl-depth* 1))
                    (prog1 (funcall orig form type) (setq *dt-ccl-top* form)))
                  (funcall orig form type)))))))
#+ccl
(defun dt-ccl-body (top)
  ; TOP is a LAMBDA-LIST acode with operands (req opt rest keys auxen body p2decls)
  (and (ccl::acode-p top) (nth 5 (ccl::acode-operands top))))
#+ccl
(defun dt-ccl-probe (form)
  ; => (values function-or-err operator-name type) for the body of lambda FORM
  (dt-ccl-install)
  (setq *dt-ccl-top* nil)
  (let* ((f (dt-compile form))
         (b (dt-ccl-body *dt-ccl-top*)))
    (if (and (functionp f) b)
        (values f (ccl::acode-operator-name (ccl::acode-operator b))
                (ccl::acode-form-type b t))
        (values f nil :unknown))))

(defun dt-result-types (ftype)
  ; (function args (values a b &optional)) => (a b); * => :unknown
  (let ((r (and (consp ftype) (eq (car ftype) 'function) (caddr ftype))))
    (cond ((not (consp ftype)) :unknown)
          ((eq (car ftype) :err) :error)
          ((eq r '*) :unknown)
          ((and (consp r) (eq (car r) 'values))
           (let ((l (cdr r)))
             (if (member '&rest l) :unknown (remove '&optional l))))
          (t (list r)))))

(defun dt-1line (x)
  (let ((*print-pretty* nil) (*print-length* nil) (*print-level* nil)
        (*package* (find-package "ACL2")) (*print-right-margin* 100000))
    (substitute #\Space #\Tab (substitute #\Space #\Newline (prin1-to-string x)))))

; ---- guarded, time-bounded evaluation -----------------------------------------------
(defvar *dt-timeout* 1)
#+ccl (defvar *dt-deadline* nil)
#+ccl (defvar *dt-epoch* 0)
#+ccl (defvar *dt-watchdog* nil)
#+ccl
(defun dt-start-watchdog ()
  (unless *dt-watchdog*
    (let ((main ccl:*current-process*))
      (setq *dt-watchdog*
            (ccl:process-run-function "dt-watchdog"
              (lambda ()
                (loop
                  (sleep 0.05)
                  (let ((d *dt-deadline*) (e *dt-epoch*))
                    (when (and d (> (get-internal-real-time) d))
                      (setq *dt-deadline* nil)
                      (ccl:process-interrupt
                       main (lambda () (when (eql e *dt-epoch*) (throw 'dt-timeout :timeout)))))))))))))

(defmacro dt-bounded (&body body)
  ; value of BODY, or the symbol :TIMEOUT
  #+sbcl `(handler-case (sb-ext:with-timeout *dt-timeout* ,@body)
            (sb-ext:timeout () :timeout))
  #+ccl `(progn
           (dt-start-watchdog)
           (prog1 (catch 'dt-timeout
                    (setq *dt-epoch* (1+ *dt-epoch*))
                    (setq *dt-deadline* (+ (get-internal-real-time)
                                           (* *dt-timeout* internal-time-units-per-second)))
                    (prog1 (progn ,@body) (setq *dt-deadline* nil)))
             (setq *dt-deadline* nil)
             (setq *dt-epoch* (1+ *dt-epoch*)))))

(defmacro dt-guarded (&body body)
  ; value of BODY as (:val . v), or (:err ..) for any ACL2 throw, Lisp condition or timeout
  `(handler-case
       (let ((r (dt-bounded
                 (block dt-b
                   (let ((top (catch 'local-top-level
                                (let ((thrown (catch-raw-ev-fncall
                                               (return-from dt-b (cons :val (progn ,@body))))))
                                  (return-from dt-b
                                    (list :err :throw (if (consp thrown) (car thrown) thrown)))))))
                     (list :err :top-level top))))))
         (if (eq r :timeout) (list :err :timeout) r))
     (serious-condition (c) (list :err :lisp (type-of c)))))

(defun dt-ev (term alist w)
  ; ACL2's evaluator with guard checking on; a guard violation or hard error is (:err ..)
  (dt-guarded
   (let ((*aokp* nil))
     (multiple-value-bind (erp val) (ev-w term alist w nil nil nil nil nil)
       (if erp (throw 'local-top-level :erp) val)))))
