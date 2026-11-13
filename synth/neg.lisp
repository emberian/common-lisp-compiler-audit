;;; Known-outcome tests of ACL2's guard-obligation generation.
;;;
;;; Everywhere else in this harness guard verification is replaced by
;;; skip-proofs, so ACL2's own obligation generator (THE, TYPE declarations, MBE)
;;; is never exercised.  Here it is, with the outcome known by construction:
;;;
;;;   1. generate a valid integer function (primitives only, so its IR runs in
;;;      the host Lisp) and run it on its query inputs with one subterm S probed;
;;;      an input that reaches S with value V is a witness;
;;;   2. BAD twin: S is re-declared with a type that excludes V (THE, a LET type
;;;      declaration, or an MBE whose :EXEC differs from :LOGIC at the witness);
;;;      GOOD twin: S is declared with the range INFER derived;
;;;   3. in ACL2, with no skip-proofs anywhere:
;;;      @NV  (verify-guards BAD) must fail: symbol-class stays :IDEAL
;;;      @NO  BAD's guard obligation (guard-obligation, :limited simplification), evaluated
;;;           at the witness, must be NIL
;;;      @NX  calling BAD on the witness under guard checking :ALL must not
;;;           return (THE and LET variants; MBE is not checked at run time)
;;;      @PO  GOOD's guard obligation must evaluate to T at every query input
;;;           (the positive control: the evaluator does not just answer NIL)
;;;      @PV  whether the prover verified GOOD's guards (informational)
;;;
;;; Usage: sbcl --script neg.lisp SEED COUNT OUTDIR/     writes neg.lisp there
(load (merge-pathnames "lib.lisp" (directory-namestring *load-truename*)))
(in-package :zs)

;;;; Host definitions of the ACL2 operators that are not Common Lisp
(defun zp (x) (or (not (integerp x)) (<= x 0)))
(defun zip (x) (or (not (integerp x)) (= x 0)))
(defun len (x) (if (consp x) (1+ (len (cdr x))) 0))
(defun signed-byte-p (n x) (and (integerp x) (<= (- (ash 1 (1- n))) x) (< x (ash 1 (1- n)))))
(defun unsigned-byte-p (n x) (and (integerp x) (<= 0 x) (< x (ash 1 n))))
(defmacro zm-id (x) x)
(defmacro zm-inc (x) `(+ 1 ,x))
(defmacro zm-sel (c a b) `(if ,c ,a ,b))
(defmacro mv (&rest xs) `(values ,@xs))
(defmacro mv-let (vars e &rest body) `(multiple-value-bind ,vars ,e ,@body))
(defvar *probe* nil)
(defun zprobe (v) (setf *probe* (list v)) v)

(defun run-probed (f site args)
  "Value of SITE when F's IR is run on ARGS, as a one-element list, or NIL if not reached."
  (setf *probe* nil)
  (let ((form `(let ,(mapcar #'list (fn-params f) args)
                 (declare (ignorable ,@(fn-params f)))
                 ,(subst `(zprobe ,site) site (fn-ir f) :test #'eq))))
    (handler-case (let ((*error-output* (make-broadcast-stream))) (eval form))
      (error () (setf *probe* nil))))
  *probe*)

(defun bad-specs (v lo hi)
  "Type specifiers that exclude the integer V (the site's inferred range is [LO,HI])."
  (remove nil
          (list `(integer ,(1+ v) ,(max hi (1+ v)))
                `(integer ,(min lo (1- v)) ,(1- v))
                `(integer * ,(1- v))
                `(integer ,(1+ v) *)
                `(or (integer * ,(1- v)) (integer ,(1+ v) *))
                `(and integer (not (integer ,v ,v)))
                `(member ,(1- v) ,(1+ v) ,(+ v 2))
                (and (>= v 1) `(mod ,v))
                (and (not (member v '(0 1))) 'bit)
                `(satisfies ,(if (evenp v) 'oddp 'evenp))
                (and (not (member v '(0 -1))) `(signed-byte ,(integer-length v)))
                (and (>= v 2) `(unsigned-byte ,(1- (integer-length v))))
                `(or (member ,(1- v)) (and (integer ,(1+ v) *) (satisfies integerp))))))

(defun plant (f site kind spec witness)
  "F's IR with SITE re-declared."
  (subst (ecase kind
           (:the `(the ,spec ,site))
           (:let `(let ((zb ,site)) (declare (type ,spec zb)) zb))
           (:mbe `(mbe :logic ,site
                       :exec (+ ,site (if (and ,@(loop for p in (fn-params f) for a in witness
                                                       for ty in (fn-ptypes f)
                                                       when (intp* ty) collect `(= ,p ,a)))
                                          1 0)))))
         site (fn-ir f) :test #'eq))

(defun neg-defun (name f body)
  (multiple-value-bind (decls conj) (param-decls f)
    `(defun ,name ,(fn-params f)
       (declare ,@decls (ignorable ,@(fn-params f))
                (xargs ,@(when conj `(:guard ,(if (cdr conj) `(and ,@conj) (car conj))))
                       :verify-guards nil))
       ,body)))

(defun obligation-form (tag i name f args)
  "Evaluate NAME's unsimplified guard obligation with the formals bound to ARGS."
  `(mv-let (erp val) (guard-obligation ',name nil nil :limited 'top state)
     (if erp
         (prog2$ (cw ,(format nil "~A ~D :GO-ERROR~~%" tag i)) (value nil))
         ;; The TRANSLATED clauses are evaluated: the untranslated form is not always
         ;; re-translatable (a constant (MV a b) prints as a quoted list).
         (mv-let (e2 v2 state)
           (trans-eval (list 'let (list ,@(mapcar (lambda (p a) `(list ',p (list 'quote ,a)))
                                                  (fn-params f) args))
                             '(declare (ignorable ,@(fn-params f)))
                             (termify-clause-set (cadr val)))
                       'top state t)
           (prog2$ (cw ,(format nil "~A ~D ~~x0~~%" tag i) (if e2 :eval-error (cdr v2)))
                   (value nil))))))

(let* ((args (last sb-ext:*posix-argv* 3))
       (seed (parse-integer (first args))) (count (parse-integer (second args)))
       (dir (third args)) (forms nil) (made 0) (tried 0) (kinds-used nil))
  (setf *rs* (sb-ext:seed-random-state seed))
  (setf *elem* (ti -9 9) *fields* nil *feats* nil *consts* nil *fns* (make-hash-table)
        *int-fns* nil *mv-fns* nil *list-fns* nil *val-fns* nil)
  (loop while (and (< made count) (< tried (* 40 count)))
        do (incf tried)
           (let* ((*restrict* t)
                  (f (first (valid-or-nil (build 'zn :plain (+ 2 (rnd 3))))))
                  (f (and f (finish f 0))))
             (remhash 'zn *fns*)
             (when (and f (intp* (fn-rtype f)))
               (fresh-queries f)
               (let* ((cell (list nil))
                      (env (mapcar #'cons (fn-params f) (fn-ptypes f)))
                      (sites (progn (let ((*trace* cell)) (infer (fn-ir f) env))
                                    (remove-if-not (lambda (s) (small-int-p (third s))) (car cell))))
                      (site (and sites (pick sites)))
                      (hit (and site
                                (loop for q in (fn-queries f)
                                      for a = (mapcar (lambda (x) (if (consp x) (second x) x)) (cdr q))
                                      for r = (run-probed f (first site) a)
                                      when r return (cons (cdr q) (first r))))))
                 (when hit
                   (destructuring-bind (wargs . v) hit
                     (let* ((kind (pick '(:the :the :let :mbe)))
                            (spec (pick (bad-specs v (second (third site)) (third (third site)))))
                            (bad (intern (format nil "ZB~D" made) :zs))
                            (good (intern (format nil "ZG~D" made) :zs))
                            (ty (third site))
                            (i made))
                       (incf (getf kinds-used kind 0))
                       (push `(cw ,(format nil "@N ~D ~S ~S~~%" i kind (if (eq kind :mbe) :exec spec))) forms)
                       (push (neg-defun bad f (plant f (first site) kind spec wargs)) forms)
                       (push (neg-defun good f (plant f (first site) (if (eq kind :mbe) :the kind)
                                                      `(integer ,(second ty) ,(third ty)) wargs))
                             forms)
                       (push `(with-prover-step-limit 20000 (verify-guards ,bad)) forms)
                       (push `(cw ,(format nil "@NV ~D ~~x0~~%" i)
                                  (getpropc ',bad 'symbol-class nil (w state)))
                             forms)
                       (push (obligation-form "@NO" i bad f wargs) forms)
                       (unless (eq kind :mbe)
                         (push `(cw ,(format nil "@NX ~D :RETURNED ~~x0~~%" i) (,bad ,@wargs)) forms))
                       (dolist (q (fn-queries f))
                         (push (obligation-form "@PO" i good f (cdr q)) forms))
                       (push `(with-prover-step-limit 20000 (verify-guards ,good)) forms)
                       (push `(cw ,(format nil "@PV ~D ~~x0~~%" i)
                                  (getpropc ',good 'symbol-class nil (w state)))
                             forms)
                       (incf made))))))))
  (write-forms (format nil "~Aneg.lisp" dir)
               (append '((set-ignore-ok t) (set-guard-checking :all)
                         (defmacro zm-id (x) x)
                         (defmacro zm-inc (x) (list (quote +) 1 x))
                         (defmacro zm-sel (c a b) (list (quote if) c a b)))
                       (nreverse forms)
                       '((cw "@NEND~%"))))
  (format t "~D planted functions from ~D attempts; kinds ~S~%" made tried kinds-used))
