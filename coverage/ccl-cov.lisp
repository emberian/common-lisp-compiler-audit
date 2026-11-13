;;; Compiler-table coverage for Clozure CL (arm64 backend): which entries of
;;; the compiler's own tables are used while forms are compiled.
;;;
;;; Tables (verified in a running darm64cl 1.14 image; file:line in ccl/compiler):
;;;   ccl::*compiler-macros*          nx0.lisp:185    name -> expander (optimizers.lisp)
;;;   $sym_fbit_constant_fold symbols nx0.lisp:2670   functions NX-CONSTANT-FOLD may fold
;;;   ccl::*nx-synonyms*              nx0.lisp:177    (from . to) rewrites in NX-TRANSFORM
;;;   ccl::*nx1-alphatizers*          nx-basic.lisp:163  symbol -> nx1 handler (DEFNX1)
;;;   ccl::*next-nx-operators*        nxenv.lisp:115  the acode operators, with flags and type
;;;   ccl::*acode-rewrite-functions*  acode-rewrite.lisp:29  operator id -> rewrite handler
;;;   ccl::*arm642-specials*          ARM64/arm64-backend.lisp:8  operator id -> p2 handler
;;;                                   (EQ to (backend-p2-dispatch *target-backend*))
;;;   ccl::*arm64-vinsn-templates*    ARM64/arm64-backend.lisp:18  name -> (name . template)
;;;
;;; Hooks.  The handler tables hold anonymous NFUNCTIONs reachable only through
;;; the table, so each entry is replaced in place by a counting closure; every
;;; dispatch path (arm642-form, arm642-toplevel-form, arm642-use-operator,
;;; backend-use-operator, backend-apply-acode, rewrite-acode-form,
;;; nx1-combination) reads the table at call time.  Named global functions are
;;; wrapped through their function cell.  MAKE-ACODE is a macro expanding to an
;;; inline %ISTRUCT (nxenv.lisp:475), so acode construction itself cannot be
;;; hooked; operators are observed where they enter REWRITE-ACODE-FORM (as nx1
;;; produced them) and where they are dispatched in p2 (after rewriting).
;;; Operators a rewrite handler creates and p2 then skips (ARM642-FORM does not
;;; call the handler of a pure form compiled for no value) are seen by neither.
(defpackage :ccov (:use :cl)
  (:export #:reset #:dump #:summary #:install #:uninstall
           #:all-compiler-macros #:all-constant-fold #:all-synonyms #:all-nx1
           #:all-acode-ops #:all-rewrite #:all-p2 #:all-vinsns))
(in-package :ccov)

(defconstant +nops+ (1+ ccl::operator-id-mask))

(defvar *cm-tried* (make-hash-table :test 'equal))   ; compiler-macro name -> count (expander ran)
(defvar *cm-won* (make-hash-table :test 'equal))     ; ... and returned a new form
(defvar *folded* (make-hash-table :test 'eq))        ; function constant-folded -> count
(defvar *nx1* (make-hash-table :test 'eq))           ; alphatizer symbol -> count
(defvar *vinsns* (make-hash-table :test 'eq))        ; vinsn template name -> count
(defvar *op-seen* (make-array +nops+ :initial-element 0))  ; op id entering rewrite
(defvar *rewrite* (make-array +nops+ :initial-element 0))  ; rewrite handler ran
(defvar *p2* (make-array +nops+ :initial-element 0))       ; p2 handler ran
;;; Raw call counters, used only to show that each hook fires.
(defvar *calls* (list :compiler-macroexpand-1 0 :nx-constant-fold 0 :rewrite-acode-form 0
                      :select-vinsn 0 :make-vinsn 0))

(defun reset ()
  (clrhash *cm-tried*) (clrhash *cm-won*) (clrhash *folded*) (clrhash *nx1*) (clrhash *vinsns*)
  (fill *op-seen* 0) (fill *rewrite* 0) (fill *p2* 0)
  (loop for c on (cdr *calls*) by #'cddr do (setf (car c) 0))
  t)

;;; ---- the tables ---------------------------------------------------------

(defun op-name (id)
  (ccl::acode-operator-name id))

(defun op-entry (id)
  "(name type flag-names) for operator ID, from *next-nx-operators*."
  (let* ((def (nth (- (1- (length ccl::*next-nx-operators*)) id) ccl::*next-nx-operators*)))
    (when def
      (destructuring-bind (name flags &optional (type t)) def
        (list name type
              (loop for (bit . nm) in `((,ccl::operator-acode-subforms-bit . :subforms)
                                        (,ccl::operator-acode-list-bit . :list)
                                        (,ccl::operator-side-effect-free-bit . :pure)
                                        (,ccl::operator-assignment-free-bit . :assignment-free)
                                        (,ccl::operator-single-valued-bit . :single-valued)
                                        (,ccl::operator-cc-invertable-bit . :cc-invertable)
                                        (,ccl::operator-boolean-bit . :boolean)
                                        (,ccl::operator-returns-address-bit . :returns-address))
                    when (logbitp bit flags) collect nm))))))

(defun all-acode-ops ()
  (loop for id from 0 below (length ccl::*next-nx-operators*)
        for e = (op-entry id) when e collect e))

(defvar *orig-rewrite* (make-array +nops+ :initial-element nil))
(defvar *orig-p2* (make-array +nops+ :initial-element nil))
(defvar *orig-nx1* (make-hash-table :test 'eq))
(defvar *orig-fns* '())                 ; (symbol . original definition)

(defun handler-name (f)
  (let ((n (ccl:function-name f))) (if (symbolp n) n (prin1-to-string n))))

(defun table-fn (vec orig id)
  (or (svref orig id) (svref vec id)))

(defun all-rewrite ()
  "((operator handler-name) ...) for every operator with an acode-rewrite handler."
  (loop for id from 0 below (min +nops+ (length ccl::*acode-rewrite-functions*))
        for f = (table-fn ccl::*acode-rewrite-functions* *orig-rewrite* id)
        when f collect (list (op-name id) (handler-name f))))

(defun all-p2 ()
  "((operator handler-name type) ...) for every operator with an arm64 p2 handler."
  (loop for id from 0 below (min +nops+ (length ccl::*arm642-specials*))
        for f = (table-fn ccl::*arm642-specials* *orig-p2* id)
        when f collect (list (op-name id) (handler-name f) (second (op-entry id)))))

(defun all-nx1 ()
  "((symbol handler-name) ...) for every symbol with an nx1 handler."
  (let ((out '()))
    (maphash (lambda (sym f)
               (push (list sym (handler-name (or (gethash sym *orig-nx1*) f))) out))
             ccl::*nx1-alphatizers*)
    out))

(defun all-compiler-macros ()
  (let ((out '()))
    (maphash (lambda (name f) (declare (ignore f)) (push name out)) ccl::*compiler-macros*)
    out))

(defun all-constant-fold ()
  (let ((out '()))
    (do-all-symbols (s)
      (when (and (logbitp ccl::$sym_fbit_constant_fold (ccl::%symbol-bits s)) (fboundp s))
        (pushnew s out :test #'eq)))
    (dolist (p ccl::*nx-can-constant-fold*) (pushnew (car p) out :test #'eq))
    out))

(defun all-synonyms ()
  (mapcar (lambda (p) (list (car p) (cdr p))) ccl::*nx-synonyms*))

(defun all-vinsns ()
  "((name results args temps attribute-names) ...), operand specs as the template carries them."
  (let ((out '()))
    (maphash (lambda (name cell)
               (let ((tm (cdr cell)))
                 (when tm
                   (push (list name
                               (ccl::vinsn-template-result-vreg-specs tm)
                               (ccl::vinsn-template-argument-vreg-specs tm)
                               (ccl::vinsn-template-temp-vreg-specs tm)
                               (let ((bits (ccl::vinsn-template-attributes tm)))
                                 (loop for k in ccl::*known-vinsn-attributes* for i from 0
                                       when (logbitp i bits) collect k)))
                         out))))
             ccl::*arm64-vinsn-templates*)
    out))

;;; ---- hooks --------------------------------------------------------------

(defun wrap-global (sym make-wrapper)
  "Replace SYM's global definition with (funcall MAKE-WRAPPER original), once."
  (unless (assoc sym *orig-fns*)
    (let ((orig (fdefinition sym)))
      (push (cons sym orig) *orig-fns*)
      (let ((ccl:*warn-if-redefine-kernel* nil))
        (setf (fdefinition sym) (funcall make-wrapper orig))))))

(defmacro call-count (key) `(getf *calls* ,key))

(defun install ()
  ;; front end: compiler macros.  Called from NX-TRANSFORM (nx0.lisp:2596).
  (wrap-global 'ccl::compiler-macroexpand-1
    (lambda (orig)
      (lambda (form &optional env)
        (incf (call-count :compiler-macroexpand-1))
        (multiple-value-bind (new win) (funcall orig form env)
          (when (and (consp form) (symbolp (car form))
                     (compiler-macro-function (car form) env))
            (incf (gethash (car form) *cm-tried* 0))
            (when win (incf (gethash (car form) *cm-won* 0))))
          (values new win)))))
  ;; front end: constant folding.  Called from NX-TRANSFORM (nx0.lisp:2590).
  (wrap-global 'ccl::nx-constant-fold
    (lambda (orig)
      (lambda (call &rest rest)
        (declare (dynamic-extent rest))
        (incf (call-count :nx-constant-fold))
        (multiple-value-bind (new win) (apply orig call rest)
          (when (and win (consp call) (symbolp (car call)))
            (incf (gethash (car call) *folded* 0)))
          (values new win)))))
  ;; nx1 handlers: funcalled from NX1-COMBINATION (nx0.lisp:1855) out of the table.
  (maphash (lambda (sym f)
             (unless (gethash sym *orig-nx1*)
               (setf (gethash sym *orig-nx1*) f)
               (setf (gethash sym ccl::*nx1-alphatizers*)
                     (lambda (context form env)
                       (incf (gethash sym *nx1* 0))
                       (funcall f context form env)))))
           ccl::*nx1-alphatizers*)
  ;; acode operators as nx1 produced them, seen entering the rewriter.
  ;; REWRITE-ACODE-FORM (acode-rewrite.lisp:70) recurses into itself for
  ;; operators with no handler, and CCL compiles a self-call as a direct
  ;; branch that never consults the function cell, so a wrapper misses those
  ;; forms (measured: 148 seen against 150 handler runs on one probe).  The
  ;; function is ten lines; it is replaced here by a transcription whose
  ;; recursive call goes through the symbol.
  (wrap-global 'ccl::rewrite-acode-form
    (lambda (orig)
      (declare (ignore orig))
      (lambda (form &optional (type t))
        (incf (call-count :rewrite-acode-form))
        (when (ccl::acode-p form)
          (unless (ccl::acode-walked form)
            (setf (ccl::acode-walked form) t)
            (let* ((op (ccl::acode-operator form))
                   (id (logand op ccl::operator-id-mask))
                   (rewrite (svref ccl::*acode-rewrite-functions* id)))
              (incf (svref *op-seen* id))
              (if rewrite
                  (funcall rewrite form type)
                  (if (logbitp ccl::operator-acode-subforms-bit op)
                      (dolist (operand (ccl::acode-operands form))
                        (funcall 'ccl::rewrite-acode-form operand))
                      (format t "~&can't rewrite ~s : ~s" (ccl::acode-operator-name op) form)))))))))
  ;; acode-rewrite handlers.
  (dotimes (id (min +nops+ (length ccl::*acode-rewrite-functions*)))
    (let ((f (svref ccl::*acode-rewrite-functions* id)) (id id))
      (when (and f (null (svref *orig-rewrite* id)))
        (setf (svref *orig-rewrite* id) f)
        (setf (svref ccl::*acode-rewrite-functions* id)
              (lambda (form &optional (type t))
                (incf (svref *rewrite* id))
                (funcall f form type))))))
  ;; arm64 p2 handlers.
  (dotimes (id (min +nops+ (length ccl::*arm642-specials*)))
    (let ((f (svref ccl::*arm642-specials* id)) (id id))
      (when (and f (null (svref *orig-p2* id)))
        (setf (svref *orig-p2* id) f)
        (setf (svref ccl::*arm642-specials* id)
              (lambda (&rest args)
                (declare (dynamic-extent args))
                (incf (svref *p2* id))
                (apply f args))))))
  ;; vinsn emission: every vinsn instance is built by SELECT-VINSN
  ;; (vinsn.lisp:516), the only caller of MAKE-VINSN.
  (wrap-global 'ccl::select-vinsn
    (lambda (orig)
      (lambda (template-or-name template-hash vregs)
        (incf (call-count :select-vinsn))
        (let ((v (funcall orig template-or-name template-hash vregs)))
          (incf (gethash (ccl::vinsn-template-name (ccl::vinsn-template v)) *vinsns* 0))
          v))))
  (wrap-global 'ccl::make-vinsn
    (lambda (orig)
      (lambda (template)
        (incf (call-count :make-vinsn))
        (funcall orig template))))
  t)

(defun uninstall ()
  (let ((ccl:*warn-if-redefine-kernel* nil))
    (loop for (sym . orig) in *orig-fns* do (setf (fdefinition sym) orig)))
  (setf *orig-fns* '())
  (maphash (lambda (sym f) (setf (gethash sym ccl::*nx1-alphatizers*) f)) *orig-nx1*)
  (clrhash *orig-nx1*)
  (dotimes (id +nops+)
    (when (svref *orig-rewrite* id)
      (setf (svref ccl::*acode-rewrite-functions* id) (svref *orig-rewrite* id)
            (svref *orig-rewrite* id) nil))
    (when (svref *orig-p2* id)
      (setf (svref ccl::*arm642-specials* id) (svref *orig-p2* id)
            (svref *orig-p2* id) nil)))
  t)

;;; ---- reporting ----------------------------------------------------------

(defun hash-alist (h)
  (loop for k being the hash-keys of h using (hash-value v) collect (cons k v)))

(defun vec-alist (v)
  (loop for id from 0 below +nops+
        unless (zerop (svref v id)) collect (cons (op-name id) (svref v id))))

(defun reached ()
  (list :cm-tried (hash-alist *cm-tried*) :cm-won (hash-alist *cm-won*)
        :folded (hash-alist *folded*) :nx1 (hash-alist *nx1*)
        :ops-seen (vec-alist *op-seen*) :rewrite (vec-alist *rewrite*)
        :p2 (vec-alist *p2*) :vinsns (hash-alist *vinsns*)))

(defun summary (&optional (r (reached)))
  (format nil "CCOV compiler-macros ~D/~D (expander ran ~D)  constant-fold ~D/~D  nx1 ~D/~D  ~
               acode-ops ~D/~D  rewrite ~D/~D  p2 ~D/~D  vinsns ~D/~D"
          (length (getf r :cm-won)) (length (all-compiler-macros)) (length (getf r :cm-tried))
          (length (getf r :folded)) (length (all-constant-fold))
          (length (getf r :nx1)) (length (all-nx1))
          (length (union (mapcar #'car (getf r :ops-seen)) (mapcar #'car (getf r :p2))))
          (length (all-acode-ops))
          (length (getf r :rewrite)) (length (all-rewrite))
          (length (getf r :p2)) (length (all-p2))
          (length (getf r :vinsns)) (length (all-vinsns))))

(defun dump (path)
  "Write the reached sets and the full tables as one plist; print the CCOV line."
  (let ((r (reached)))
    (with-open-file (s path :direction :output :if-exists :supersede)
      (let ((*package* (find-package :cl)) (*print-pretty* nil) (*print-readably* nil)
            (*print-length* nil) (*print-level* nil) (*print-circle* nil))
        (flet ((keys (k) (mapcar #'car (getf r k))))
          (print (list :impl (lisp-implementation-type) :version (lisp-implementation-version)
                       :backend (ccl::backend-name ccl::*target-backend*)
                       :compiler-macros (keys :cm-won) :compiler-macros-tried (keys :cm-tried)
                       :constant-folded (keys :folded)
                       :nx1 (keys :nx1)
                       :ops-seen (keys :ops-seen)
                       :rewrite (keys :rewrite)
                       :p2 (keys :p2)
                       :vinsns (keys :vinsns)
                       :counts r
                       :calls (copy-list *calls*)
                       :all-compiler-macros (all-compiler-macros)
                       :all-constant-fold (all-constant-fold)
                       :all-synonyms (all-synonyms)
                       :all-nx1 (all-nx1)
                       :all-acode-ops (all-acode-ops)
                       :all-rewrite (all-rewrite)
                       :all-p2 (all-p2)
                       :all-vinsns (all-vinsns))
                 s))))
    (format t "~&~A~%" (summary r))))

(install)
